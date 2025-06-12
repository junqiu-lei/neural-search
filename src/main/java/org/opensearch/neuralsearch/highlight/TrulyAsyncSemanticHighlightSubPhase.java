/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.highlight;

import lombok.extern.log4j.Log4j2;
import org.apache.lucene.index.LeafReaderContext;
import org.apache.lucene.search.Query;
import org.opensearch.search.fetch.FetchContext;
import org.opensearch.search.fetch.FetchSubPhase;
import org.opensearch.search.fetch.FetchSubPhaseProcessor;
import org.opensearch.search.fetch.subphase.highlight.FieldHighlightContext;
import org.opensearch.search.fetch.subphase.highlight.SearchHighlightContext;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Truly asynchronous semantic highlighting with minimal blocking.
 *
 * Key innovation: Submit ALL ML requests immediately, wait only at the end.
 * This achieves true concurrency by overlapping ML inference calls.
 */
@Log4j2
public class TrulyAsyncSemanticHighlightSubPhase implements FetchSubPhase {

    private final int parallelism;

    /** Performance monitoring counters */
    private static final AtomicInteger TOTAL_PROCESSED = new AtomicInteger();
    private static final AtomicLong TOTAL_SUBMIT_TIME_MS = new AtomicLong();
    private static final AtomicLong TOTAL_WAIT_TIME_MS = new AtomicLong();
    private static final AtomicLong TOTAL_ML_TIME_MS = new AtomicLong();
    private static final AtomicInteger CONCURRENT_REQUESTS = new AtomicInteger();
    private static final AtomicInteger PEAK_CONCURRENT_REQUESTS = new AtomicInteger();

    public TrulyAsyncSemanticHighlightSubPhase(int parallelism) {
        this.parallelism = parallelism;
        log.info("[semantic-hl-async] TrulyAsyncSemanticHighlightSubPhase created with parallelism={}", parallelism);
    }

    @Override
    public FetchSubPhaseProcessor getProcessor(FetchContext context) {
        if (context.highlight() == null) {
            return null;
        }

        boolean hasSemantic = context.highlight()
            .fields()
            .stream()
            .anyMatch(f -> SemanticHighlighter.NAME.equals(f.fieldOptions().highlighterType()));

        if (!hasSemantic) {
            return null;
        }

        log.info("[semantic-hl-async] Creating TrulyAsyncProcessor for semantic highlighting");
        return new TrulyAsyncProcessor(context, context.highlight(), context.parsedQuery().query());
    }

    private class TrulyAsyncProcessor implements FetchSubPhaseProcessor {
        private final FetchContext fetchContext;
        private final SearchHighlightContext highlightContext;
        private final Query originalQuery;

        // Pre-submitted futures for all documents
        private final Map<Integer, List<CompletableFuture<HighlightResult>>> pendingFutures = new ConcurrentHashMap<>();
        private final AtomicInteger submittedTasks = new AtomicInteger();
        private final long processorStartTime;

        TrulyAsyncProcessor(FetchContext fetchContext, SearchHighlightContext highlightContext, Query originalQuery) {
            this.fetchContext = fetchContext;
            this.highlightContext = highlightContext;
            this.originalQuery = originalQuery;
            this.processorStartTime = System.currentTimeMillis();

            log.info("[semantic-hl-async] TrulyAsyncProcessor initialized");
        }

        @Override
        public void setNextReader(LeafReaderContext readerContext) {
            // no-op
        }

        @Override
        public void process(FetchSubPhase.HitContext hitContext) throws IOException {
            long startTime = System.currentTimeMillis();
            int docId = hitContext.docId();

            log.debug("[semantic-hl-async] Processing docId={}", docId);

            SemanticHighlighterEngine engine = org.opensearch.neuralsearch.plugin.NeuralSearch.getSemanticEngineStatic();
            if (engine == null) {
                log.warn("[semantic-hl-async] SemanticHighlighterEngine not available for docId={}", docId);
                return;
            }

            // Submit all ML requests for this document immediately (non-blocking)
            List<CompletableFuture<HighlightResult>> docFutures = new ArrayList<>();

            for (SearchHighlightContext.Field field : highlightContext.fields()) {
                if (!SemanticHighlighter.NAME.equals(field.fieldOptions().highlighterType())) {
                    continue;
                }

                String fieldName = field.field();
                try {
                    FieldHighlightContext fieldCtx = createFieldHighlightContext(fieldName, field, hitContext);
                    String fieldText = engine.getFieldText(fieldCtx);
                    String modelId = engine.getModelId(field.fieldOptions().options());
                    String queryText = engine.extractOriginalQuery(originalQuery, fieldName);

                    if (queryText == null || queryText.isEmpty()) {
                        continue;
                    }

                    String[] preTags = field.fieldOptions().preTags();
                    String[] postTags = field.fieldOptions().postTags();

                    // Submit ML request asynchronously
                    CompletableFuture<HighlightResult> future = submitHighlightRequest(
                        docId,
                        fieldName,
                        modelId,
                        queryText,
                        fieldText,
                        preTags[0],
                        postTags[0],
                        engine
                    );
                    docFutures.add(future);
                    submittedTasks.incrementAndGet();

                } catch (Exception e) {
                    log.error("[semantic-hl-async] Error submitting highlight request for docId={}, field={}", docId, fieldName, e);
                }
            }

            // Store futures for later batch waiting
            if (!docFutures.isEmpty()) {
                pendingFutures.put(docId, docFutures);
            }

            long submitDuration = System.currentTimeMillis() - startTime;
            TOTAL_SUBMIT_TIME_MS.addAndGet(submitDuration);

            log.debug("[semantic-hl-async] Submitted {} requests for docId={} in {}ms", docFutures.size(), docId, submitDuration);
        }

        /**
         * Submit highlight request asynchronously
         */
        private CompletableFuture<HighlightResult> submitHighlightRequest(
            int docId,
            String fieldName,
            String modelId,
            String queryText,
            String fieldText,
            String preTag,
            String postTag,
            SemanticHighlighterEngine engine
        ) {

            long mlStartTime = System.currentTimeMillis();
            int currentConcurrent = CONCURRENT_REQUESTS.incrementAndGet();
            PEAK_CONCURRENT_REQUESTS.updateAndGet(prev -> Math.max(prev, currentConcurrent));

            return CompletableFuture.supplyAsync(() -> {
                try {
                    String highlighted = engine.getHighlightedSentences(modelId, queryText, fieldText, preTag, postTag);
                    long mlDuration = System.currentTimeMillis() - mlStartTime;
                    TOTAL_ML_TIME_MS.addAndGet(mlDuration);

                    log.debug("[semantic-hl-async] ML request completed for docId={}, field={} in {}ms", docId, fieldName, mlDuration);

                    return new HighlightResult(docId, fieldName, highlighted, true, mlDuration);

                } catch (Exception e) {
                    long mlDuration = System.currentTimeMillis() - mlStartTime;
                    log.error("[semantic-hl-async] ML request failed for docId={}, field={} after {}ms", docId, fieldName, mlDuration, e);
                    return new HighlightResult(docId, fieldName, null, false, mlDuration);
                } finally {
                    CONCURRENT_REQUESTS.decrementAndGet();
                }
            }, org.opensearch.neuralsearch.plugin.NeuralSearch.getSemanticHighlightExecutorStatic());
        }

        /**
         * Wait for all pending highlights and apply results
         * This should be called when all documents have been processed
         */
        public void finalizePendingHighlights() {
            if (pendingFutures.isEmpty()) {
                log.info("[semantic-hl-async] No pending highlights to finalize");
                return;
            }

            long waitStartTime = System.currentTimeMillis();
            int totalFutures = pendingFutures.values().stream().mapToInt(List::size).sum();

            log.info(
                "[semantic-hl-async] Starting to wait for {} pending highlights across {} documents",
                totalFutures,
                pendingFutures.size()
            );

            // Wait for all futures and apply results
            int successCount = 0;
            int failureCount = 0;

            for (Map.Entry<Integer, List<CompletableFuture<HighlightResult>>> entry : pendingFutures.entrySet()) {
                int docId = entry.getKey();
                List<CompletableFuture<HighlightResult>> docFutures = entry.getValue();

                for (CompletableFuture<HighlightResult> future : docFutures) {
                    try {
                        HighlightResult result = future.get(); // Wait for this specific result

                        if (result.success && result.highlightedText != null && !result.highlightedText.isEmpty()) {
                            // Apply highlight to the hit context
                            // Note: We need to find the hit context by docId
                            applyHighlightResult(result);
                            successCount++;
                        } else {
                            failureCount++;
                        }

                    } catch (Exception e) {
                        log.error("[semantic-hl-async] Error waiting for highlight result docId={}", docId, e);
                        failureCount++;
                    }
                }
            }

            long waitDuration = System.currentTimeMillis() - waitStartTime;
            TOTAL_WAIT_TIME_MS.addAndGet(waitDuration);

            long totalDuration = System.currentTimeMillis() - processorStartTime;
            TOTAL_PROCESSED.addAndGet(pendingFutures.size());

            log.info(
                "[semantic-hl-async] Finalized {} highlights: success={}, failure={}, waitTime={}ms, totalTime={}ms",
                totalFutures,
                successCount,
                failureCount,
                waitDuration,
                totalDuration
            );

            // Clear futures
            pendingFutures.clear();
        }

        /**
         * Apply highlight result to hit context
         * Note: This is a limitation - we need access to hit contexts by docId
         */
        private void applyHighlightResult(HighlightResult result) {
            // TODO: This requires architectural changes to maintain hit context mapping
            // For now, we log the issue and will need to refactor the approach
            log.warn(
                "[semantic-hl-async] Cannot apply highlight result - need hit context mapping for docId={}, field={}",
                result.docId,
                result.fieldName
            );
        }

        private FieldHighlightContext createFieldHighlightContext(
            String fieldName,
            SearchHighlightContext.Field field,
            FetchSubPhase.HitContext hitContext
        ) {
            return new FieldHighlightContext(fieldName, field, null, fetchContext, hitContext, originalQuery, true, Map.of());
        }
    }

    /**
     * Highlight result container
     */
    private static class HighlightResult {
        final int docId;
        final String fieldName;
        final String highlightedText;
        final boolean success;
        final long durationMs;

        HighlightResult(int docId, String fieldName, String highlightedText, boolean success, long durationMs) {
            this.docId = docId;
            this.fieldName = fieldName;
            this.highlightedText = highlightedText;
            this.success = success;
            this.durationMs = durationMs;
        }
    }

    /**
     * Get performance statistics
     */
    public static String getPerformanceStats() {
        int totalProcessed = TOTAL_PROCESSED.get();
        return String.format(
            "TrulyAsync SemanticHighlight Performance Stats:\n"
                + "Documents: processed=%d\n"
                + "Timing (total ms): submit=%d, wait=%d, ml=%d\n"
                + "Concurrency: peak_concurrent=%d\n"
                + "Averages: submit=%.1fms, wait=%.1fms, ml=%.1fms per document",
            totalProcessed,
            TOTAL_SUBMIT_TIME_MS.get(),
            TOTAL_WAIT_TIME_MS.get(),
            TOTAL_ML_TIME_MS.get(),
            PEAK_CONCURRENT_REQUESTS.get(),
            totalProcessed > 0 ? (double) TOTAL_SUBMIT_TIME_MS.get() / totalProcessed : 0.0,
            totalProcessed > 0 ? (double) TOTAL_WAIT_TIME_MS.get() / totalProcessed : 0.0,
            totalProcessed > 0 ? (double) TOTAL_ML_TIME_MS.get() / totalProcessed : 0.0
        );
    }
}
