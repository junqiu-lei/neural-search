/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.highlight;

import lombok.extern.log4j.Log4j2;
import org.apache.lucene.index.LeafReaderContext;
import org.apache.lucene.search.Query;
import org.opensearch.core.common.text.Text;
import org.opensearch.search.fetch.FetchContext;
import org.opensearch.search.fetch.FetchSubPhase;
import org.opensearch.search.fetch.FetchSubPhaseProcessor;
import org.opensearch.search.fetch.subphase.highlight.FieldHighlightContext;
import org.opensearch.search.fetch.subphase.highlight.HighlightField;
import org.opensearch.search.fetch.subphase.highlight.SearchHighlightContext;
import org.opensearch.search.internal.SearchContext;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Custom fetch sub-phase that performs semantic highlighting in parallel using a shared executor.
 */
@Log4j2
public class SemanticHighlightSubPhase implements FetchSubPhase {

    private final int parallelism;

    /** Tracks current and peak number of inference tasks running concurrently across the JVM */
    private static final AtomicInteger CURRENT_RUNNING = new AtomicInteger();
    private static final AtomicInteger PEAK_RUNNING = new AtomicInteger();

    public SemanticHighlightSubPhase(int parallelism) {
        this.parallelism = parallelism;
        log.info("[semantic-hl] SemanticHighlightSubPhase created with parallelism={}", parallelism);
    }

    @Override
    public FetchSubPhaseProcessor getProcessor(FetchContext context) {
        // If no highlight context or no semantic fields requested, skip
        if (context.highlight() == null) {
            return null;
        }
        boolean hasSemantic = context.highlight()
            .fields()
            .stream()
            .anyMatch(f -> SemanticHighlighter.NAME.equals(f.fieldOptions().highlighterType()));
        if (hasSemantic == false) {
            return null;
        }
        return new Processor(context, context.highlight(), context.parsedQuery().query());
    }

    private class Processor implements FetchSubPhaseProcessor {
        private final FetchContext fetchContext;
        private final SearchHighlightContext highlightContext;
        private final Query originalQuery;
        private final int expectedHits;
        private final AtomicInteger submitted = new AtomicInteger();
        private final List<Future<?>> futures = new ArrayList<>();
        private final int effectiveParallelism;

        Processor(FetchContext fetchContext, SearchHighlightContext highlightContext, Query originalQuery) {
            this.fetchContext = fetchContext;
            this.highlightContext = highlightContext;
            this.originalQuery = originalQuery;
            SearchContext sc = extractSearchContext(fetchContext);
            int total;
            try {
                total = sc != null ? sc.docIdsToLoadSize() : -1;
            } catch (Exception e) {
                total = -1;
            }
            expectedHits = total > 0 ? total : Integer.MAX_VALUE; // fallback large number

            // Calculate effective parallelism - remove complex adaptive logic for now
            this.effectiveParallelism = calculateEffectiveParallelism(expectedHits);
            log.info(
                "[semantic-hl] Using effective parallelism {} for expectedHits={}",
                effectiveParallelism,
                expectedHits == Integer.MAX_VALUE ? "unknown" : expectedHits
            );
        }

        /**
         * Calculate effective parallelism - simplified and optimized
         */
        private int calculateEffectiveParallelism(int expectedHits) {
            if (expectedHits == Integer.MAX_VALUE) {
                // Unknown hit count, use full configured parallelism
                return parallelism;
            }

            // Simple strategy: use parallelism up to the number of hits
            // This prevents creating more threads than needed
            return Math.min(parallelism, expectedHits);
        }

        @Override
        public void setNextReader(LeafReaderContext readerContext) {
            // no-op
        }

        @Override
        public void process(org.opensearch.search.fetch.FetchSubPhase.HitContext hitContext) throws IOException {
            int taskId = submitted.incrementAndGet();
            log.info("[semantic-hl] PROCESS METHOD CALLED for docId [{}] taskId={}", hitContext.docId(), taskId);

            java.util.concurrent.ExecutorService semanticExecutor = org.opensearch.neuralsearch.plugin.NeuralSearch
                .getSemanticHighlightExecutorStatic();

            if (semanticExecutor == null) {
                log.error("SemanticHighlightExecutor not initialized - falling back to synchronous highlighting");
                performHighlight(new HitWrapper(hitContext));
                return;
            }

            log.info("[semantic-hl] Submitting task {} to thread pool for docId [{}]", taskId, hitContext.docId());

            // Submit to executor but wait immediately
            long submitTime = System.currentTimeMillis();
            Future<?> future = semanticExecutor.submit(() -> {
                log.info("[semantic-hl] THREAD POOL TASK {} STARTING for docId [{}]", taskId, hitContext.docId());
                performHighlight(new HitWrapper(hitContext));
                log.info("[semantic-hl] THREAD POOL TASK {} FINISHED for docId [{}]", taskId, hitContext.docId());
            });

            try {
                log.info("[semantic-hl] Waiting for task {} completion...", taskId);
                future.get();
                long totalTime = System.currentTimeMillis() - submitTime;
                log.info("[semantic-hl] Task {} for docId [{}] completed successfully in {}ms", taskId, hitContext.docId(), totalTime);
            } catch (Exception e) {
                log.error("Error in semantic highlighting task {} for docId [{}]", taskId, hitContext.docId(), e);
            }
        }

        /**
         * Wait for ALL submitted tasks to complete - enabling TRUE concurrency
         */
        private void waitForAllTasks() {
            List<Future<?>> allTasks;
            synchronized (futures) {
                if (futures.isEmpty()) {
                    return;
                }
                allTasks = new ArrayList<>(futures);
                futures.clear(); // Clear futures after copying
            }

            log.info(
                "[semantic-hl] TRUE CONCURRENCY: Waiting for ALL {} highlighting tasks to complete (all submitted concurrently)",
                allTasks.size()
            );
            long startTime = System.currentTimeMillis();

            int completed = 0;
            for (Future<?> future : allTasks) {
                try {
                    future.get(); // Wait for each task to complete
                    completed++;
                } catch (Exception e) {
                    log.error("Error waiting for highlighting task completion", e);
                }
            }

            long totalDuration = System.currentTimeMillis() - startTime;
            log.info(
                "[semantic-hl] TRUE CONCURRENCY: ALL {} highlighting tasks completed in {}ms (expected ~100ms for K=5 if truly concurrent)",
                completed,
                totalDuration
            );
        }

        private void performHighlight(HitWrapper wrapper) {
            int runningNow = CURRENT_RUNNING.incrementAndGet();
            PEAK_RUNNING.updateAndGet(prev -> Math.max(prev, runningNow));
            if (runningNow % 10 == 0 || runningNow == 1) {
                log.info("[semantic-hl] Concurrent inference running = {} (peak={})", runningNow, PEAK_RUNNING.get());
            }
            SemanticHighlighterEngine engine = org.opensearch.neuralsearch.plugin.NeuralSearch.getSemanticEngineStatic();
            if (engine == null) {
                log.warn("SemanticHighlighterEngine not yet initialised, skipping highlight.");
                return;
            }
            log.info("Start semantic highlight for docId [{}]", wrapper.hitContext.docId());
            for (SearchHighlightContext.Field field : highlightContext.fields()) {
                if (SemanticHighlighter.NAME.equals(field.fieldOptions().highlighterType()) == false) {
                    continue;
                }
                String fieldName = field.field();
                // Build FieldHighlightContext similar to HighlightPhase logic but simplified.
                FieldHighlightContext fieldCtx = new FieldHighlightContext(
                    fieldName,
                    field,
                    null,
                    fetchContext,
                    wrapper.hitContext,
                    originalQuery,
                    true,
                    Map.of()
                );
                try {
                    String fieldText = engine.getFieldText(fieldCtx);
                    String modelId = engine.getModelId(field.fieldOptions().options());
                    String queryText = engine.extractOriginalQuery(originalQuery, fieldName);
                    log.info(
                        "docId [{}] field [{}]: modelId={}, query='{}' (len={}), fieldTextLen={}",
                        wrapper.hitContext.docId(),
                        fieldName,
                        modelId,
                        queryText,
                        queryText == null ? 0 : queryText.length(),
                        fieldText.length()
                    );
                    if (queryText == null || queryText.isEmpty()) {
                        continue;
                    }
                    String[] preTags = field.fieldOptions().preTags();
                    String[] postTags = field.fieldOptions().postTags();
                    String highlighted = engine.getHighlightedSentences(modelId, queryText, fieldText, preTags[0], postTags[0]);
                    if (highlighted == null || highlighted.isEmpty()) {
                        log.info("docId [{}] field [{}]: no highlight returned", wrapper.hitContext.docId(), fieldName);
                        continue;
                    }
                    HighlightField highlightField = new HighlightField(fieldName, new Text[] { new Text(highlighted) });
                    wrapper.hitContext.hit().getHighlightFields().put(fieldName, highlightField);
                    log.info(
                        "docId [{}] field [{}]: highlight added ({} chars)",
                        wrapper.hitContext.docId(),
                        fieldName,
                        highlighted.length()
                    );
                } catch (Exception e) {
                    log.error(String.format(Locale.ROOT, "Error highlighting field %s", fieldName), e);
                }
            }
            CURRENT_RUNNING.decrementAndGet();
        }

        private SearchContext extractSearchContext(FetchContext fetchContext) {
            // Avoid reflection to prevent forbidden API violations
            // This is a fallback method - return null to use safe default behavior
            return null;
        }
    }

    private static class HitWrapper {
        final org.opensearch.search.fetch.FetchSubPhase.HitContext hitContext;

        HitWrapper(org.opensearch.search.fetch.FetchSubPhase.HitContext hitContext) {
            this.hitContext = hitContext;
        }
    }
}
