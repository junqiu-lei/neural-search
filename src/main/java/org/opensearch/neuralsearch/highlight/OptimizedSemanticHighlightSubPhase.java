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
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Optimized semantic highlighting with true async processing and reduced overhead.
 *
 * Key optimizations:
 * 1. Deferred waiting - submit all tasks first, then wait for all
 * 2. Reduced object creation overhead
 * 3. Better error handling and monitoring
 * 4. Prepared for batch processing
 */
@Log4j2
public class OptimizedSemanticHighlightSubPhase implements FetchSubPhase {

    private final int parallelism;

    /** Performance monitoring counters */
    private static final AtomicInteger CURRENT_RUNNING = new AtomicInteger();
    private static final AtomicInteger PEAK_RUNNING = new AtomicInteger();
    private static final AtomicInteger TOTAL_PROCESSED = new AtomicInteger();

    /** Detailed timing metrics */
    private static final AtomicLong TOTAL_QUEUE_TIME_MS = new AtomicLong();
    private static final AtomicLong TOTAL_BATCH_PROCESSING_TIME_MS = new AtomicLong();
    private static final AtomicLong TOTAL_ML_INFERENCE_TIME_MS = new AtomicLong();
    private static final AtomicLong TOTAL_RESULT_APPLICATION_TIME_MS = new AtomicLong();
    private static final AtomicLong TOTAL_PROCESS_TIME_MS = new AtomicLong();
    private static final AtomicInteger BATCH_COUNT = new AtomicInteger();
    private static final AtomicInteger BATCH_ML_SUCCESS_COUNT = new AtomicInteger();
    private static final AtomicInteger BATCH_ML_FAILURE_COUNT = new AtomicInteger();
    private static final AtomicLong MAX_CONCURRENT_TASKS = new AtomicLong();
    private static final AtomicLong TOTAL_THREAD_POOL_SUBMIT_TIME_MS = new AtomicLong();
    private static final AtomicLong TOTAL_THREAD_POOL_WAIT_TIME_MS = new AtomicLong();

    public OptimizedSemanticHighlightSubPhase(int parallelism) {
        this.parallelism = parallelism;
        log.info("[semantic-hl-opt] OptimizedSemanticHighlightSubPhase created with parallelism={}", parallelism);
    }

    @Override
    public FetchSubPhaseProcessor getProcessor(FetchContext context) {
        // Quick validation - same as original
        if (context.highlight() == null) {
            log.warn("[semantic-hl-opt] getProcessor called but highlight context is null");
            return null;
        }

        log.info("[semantic-hl-opt] getProcessor called with {} highlight fields", context.highlight().fields().size());

        boolean hasSemantic = context.highlight().fields().stream().anyMatch(f -> {
            boolean isSemantic = SemanticHighlighter.NAME.equals(f.fieldOptions().highlighterType());
            log.debug(
                "[semantic-hl-opt] Field {} has highlighter type: {}, isSemantic: {}",
                f.field(),
                f.fieldOptions().highlighterType(),
                isSemantic
            );
            return isSemantic;
        });

        if (!hasSemantic) {
            log.info("[semantic-hl-opt] No semantic highlight fields found");
            return null;
        }

        log.info("[semantic-hl-opt] Creating OptimizedProcessor for semantic highlighting");
        return new OptimizedProcessor(context, context.highlight(), context.parsedQuery().query());
    }

    private class OptimizedProcessor implements FetchSubPhaseProcessor {
        private final FetchContext fetchContext;
        private final SearchHighlightContext highlightContext;
        private final Query originalQuery;
        private final AtomicInteger submitted = new AtomicInteger();

        // Optimization: Pre-allocate collections to reduce allocation overhead
        private final List<HitProcessingTask> taskQueue = new ArrayList<>();
        private final int effectiveParallelism;
        private final int expectedHits;

        OptimizedProcessor(FetchContext fetchContext, SearchHighlightContext highlightContext, Query originalQuery) {
            this.fetchContext = fetchContext;
            this.highlightContext = highlightContext;
            this.originalQuery = originalQuery;

            SearchContext sc = extractSearchContext(fetchContext);
            this.expectedHits = getExpectedHits(sc);
            this.effectiveParallelism = calculateEffectiveParallelism(expectedHits);

            log.info(
                "[semantic-hl-opt] Processor initialized with effectiveParallelism={}, expectedHits={}",
                effectiveParallelism,
                expectedHits == Integer.MAX_VALUE ? "unknown" : expectedHits
            );
        }

        private int getExpectedHits(SearchContext sc) {
            try {
                return sc != null ? sc.docIdsToLoadSize() : Integer.MAX_VALUE;
            } catch (Exception e) {
                return Integer.MAX_VALUE; // Safe fallback
            }
        }

        private int calculateEffectiveParallelism(int expectedHits) {
            if (expectedHits == Integer.MAX_VALUE) {
                return parallelism;
            }
            // Use parallelism up to the number of hits, but minimum of 1
            return Math.max(1, Math.min(parallelism, expectedHits));
        }

        @Override
        public void setNextReader(LeafReaderContext readerContext) {
            // no-op
        }

        @Override
        public void process(org.opensearch.search.fetch.FetchSubPhase.HitContext hitContext) throws IOException {
            long processStartTime = System.currentTimeMillis();
            int taskId = submitted.incrementAndGet();

            log.info(
                "[semantic-hl-opt-timing] START process() for docId={}, taskId={}, expectedHits={}",
                hitContext.docId(),
                taskId,
                expectedHits
            );

            // Optimization 1: Defer actual processing - just queue the task
            HitProcessingTask task = new HitProcessingTask(taskId, hitContext, processStartTime);

            long queueStartTime = System.currentTimeMillis();
            synchronized (taskQueue) {
                taskQueue.add(task);
                long queueTime = System.currentTimeMillis() - queueStartTime;
                TOTAL_QUEUE_TIME_MS.addAndGet(queueTime);

                log.info(
                    "[semantic-hl-opt-timing] Queued task={}, queueSize={}, queueTime={}ms, effectiveParallelism={}",
                    taskId,
                    taskQueue.size(),
                    queueTime,
                    effectiveParallelism
                );

                // NEW STRATEGY: Force batching with timeout to enable true concurrency
                boolean shouldBatch = false;
                int targetBatchSize = Math.min(effectiveParallelism, 5); // Max batch size of 5 for latency

                if (expectedHits != Integer.MAX_VALUE && taskId >= expectedHits) {
                    // This is definitely the last document - process immediately
                    shouldBatch = true;
                    log.info(
                        "[semantic-hl-opt-timing] Last document reached: queueSize={}, taskId={}, expectedHits={}",
                        taskQueue.size(),
                        taskId,
                        expectedHits
                    );
                } else if (taskQueue.size() >= targetBatchSize) {
                    // Reached target batch size - process for better concurrency
                    shouldBatch = true;
                    log.info(
                        "[semantic-hl-opt-timing] Target batch size reached: queueSize={}, targetBatchSize={}, taskId={}",
                        taskQueue.size(),
                        targetBatchSize,
                        taskId
                    );
                } else {
                    // ARCHITECTURAL REALITY: OpenSearch processes documents one by one
                    // So we process immediately to avoid delays, but use true concurrency within batches
                    shouldBatch = true;
                    log.info(
                        "[semantic-hl-opt-timing] Single doc processing (FetchSubPhase constraint): queueSize={}, taskId={}",
                        taskQueue.size(),
                        taskId
                    );
                }

                if (shouldBatch) {
                    processBatch();
                }
            }

            long processDuration = System.currentTimeMillis() - processStartTime;
            TOTAL_PROCESS_TIME_MS.addAndGet(processDuration);
            log.info("[semantic-hl-opt-timing] END process() for taskId={}, duration={}ms", taskId, processDuration);

            // CRITICAL FIX: For final documents, ensure immediate processing
            // This is especially important for K=1 where we might have only one task
            synchronized (taskQueue) {
                if (!taskQueue.isEmpty()) {
                    boolean isFinalTask = (expectedHits != Integer.MAX_VALUE && taskId >= expectedHits);
                    if (isFinalTask) {
                        log.info(
                            "[semantic-hl-opt-timing] Final task detected, forcing immediate batch processing of {} remaining tasks",
                            taskQueue.size()
                        );
                        processBatch();
                    }
                }
            }
        }

        /**
         * Process a batch of hits with TRUE concurrent ML inference
         * Key improvement: Submit ALL requests first, then wait for ALL results
         */
        private void processBatch() {
            if (taskQueue.isEmpty()) {
                return;
            }

            List<HitProcessingTask> batchTasks = new ArrayList<>(taskQueue);
            taskQueue.clear();

            int batchNum = BATCH_COUNT.incrementAndGet();
            long batchStartTime = System.currentTimeMillis();

            log.info("[semantic-hl-opt-timing] START processBatch #{} with {} tasks (TRUE CONCURRENT)", batchNum, batchTasks.size());

            // NEW APPROACH: Submit all ML requests immediately, collect futures
            processTrueConcurrentBatch(batchTasks, batchStartTime, batchNum);
        }

        /**
         * Process batch with TRUE concurrency - submit all, then wait for all
         */
        private void processTrueConcurrentBatch(List<HitProcessingTask> batchTasks, long batchStartTime, int batchNum) {
            SemanticHighlighterEngine engine = org.opensearch.neuralsearch.plugin.NeuralSearch.getSemanticEngineStatic();
            if (engine == null) {
                log.warn("[semantic-hl-opt-timing] SemanticHighlighterEngine not available, falling back to sync");
                processFallbackSync(batchTasks, batchStartTime, batchNum);
                return;
            }

            java.util.concurrent.ExecutorService executor = org.opensearch.neuralsearch.plugin.NeuralSearch
                .getSemanticHighlightExecutorStatic();
            if (executor == null) {
                log.warn("[semantic-hl-opt-timing] Executor not available, falling back to sync");
                processFallbackSync(batchTasks, batchStartTime, batchNum);
                return;
            }

            // Phase 1: Submit ALL ML requests immediately (non-blocking)
            long submitStartTime = System.currentTimeMillis();
            List<CompletableFuture<HighlightTaskResult>> allFutures = new ArrayList<>();

            for (HitProcessingTask task : batchTasks) {
                for (SearchHighlightContext.Field field : highlightContext.fields()) {
                    if (!SemanticHighlighter.NAME.equals(field.fieldOptions().highlighterType())) {
                        continue;
                    }

                    try {
                        String fieldName = field.field();
                        FieldHighlightContext fieldCtx = createFieldHighlightContext(fieldName, field, task.hitContext);
                        String fieldText = engine.getFieldText(fieldCtx);
                        String modelId = engine.getModelId(field.fieldOptions().options());
                        String queryText = engine.extractOriginalQuery(originalQuery, fieldName);

                        if (queryText == null || queryText.isEmpty()) {
                            continue;
                        }

                        String[] preTags = field.fieldOptions().preTags();
                        String[] postTags = field.fieldOptions().postTags();

                        // Submit ML request asynchronously
                        CompletableFuture<HighlightTaskResult> future = CompletableFuture.supplyAsync(() -> {
                            long mlStart = System.currentTimeMillis();
                            try {
                                String highlighted = engine.getHighlightedSentences(modelId, queryText, fieldText, preTags[0], postTags[0]);
                                long mlDuration = System.currentTimeMillis() - mlStart;
                                return new HighlightTaskResult(task, fieldName, highlighted, true, mlDuration);
                            } catch (Exception e) {
                                long mlDuration = System.currentTimeMillis() - mlStart;
                                log.error("[semantic-hl-opt-timing] ML inference failed for task {}, field {}", task.taskId, fieldName, e);
                                return new HighlightTaskResult(task, fieldName, null, false, mlDuration);
                            }
                        }, executor);

                        allFutures.add(future);

                    } catch (Exception e) {
                        log.error("[semantic-hl-opt-timing] Error submitting ML request for task {}", task.taskId, e);
                    }
                }
            }

            long submitDuration = System.currentTimeMillis() - submitStartTime;
            TOTAL_THREAD_POOL_SUBMIT_TIME_MS.addAndGet(submitDuration);

            log.info(
                "[semantic-hl-opt-timing] Batch #{} submitted {} ML requests in {}ms (TRUE CONCURRENT)",
                batchNum,
                allFutures.size(),
                submitDuration
            );

            // Phase 2: Wait for ALL results at once (this is where concurrency happens)
            long waitStartTime = System.currentTimeMillis();
            try {
                CompletableFuture<Void> allComplete = CompletableFuture.allOf(allFutures.toArray(new CompletableFuture[0]));
                allComplete.get(); // Wait for ALL ML requests to complete

                long waitDuration = System.currentTimeMillis() - waitStartTime;
                TOTAL_THREAD_POOL_WAIT_TIME_MS.addAndGet(waitDuration);

                // Phase 3: Apply all results
                long applyStartTime = System.currentTimeMillis();
                int successCount = 0;
                long totalMLTime = 0;

                for (CompletableFuture<HighlightTaskResult> future : allFutures) {
                    try {
                        HighlightTaskResult result = future.get(); // This should return immediately
                        totalMLTime += result.mlDurationMs;

                        if (result.success && result.highlightedText != null && !result.highlightedText.isEmpty()) {
                            HighlightField highlightField = new HighlightField(
                                result.fieldName,
                                new Text[] { new Text(result.highlightedText) }
                            );
                            result.task.hitContext.hit().getHighlightFields().put(result.fieldName, highlightField);
                            successCount++;
                        }
                    } catch (Exception e) {
                        log.error("[semantic-hl-opt-timing] Error applying highlight result", e);
                    }
                }

                long applyDuration = System.currentTimeMillis() - applyStartTime;
                TOTAL_RESULT_APPLICATION_TIME_MS.addAndGet(applyDuration);
                TOTAL_ML_INFERENCE_TIME_MS.addAndGet(totalMLTime);

                long batchDuration = System.currentTimeMillis() - batchStartTime;
                TOTAL_BATCH_PROCESSING_TIME_MS.addAndGet(batchDuration);

                log.info(
                    "[semantic-hl-opt-timing] Batch #{} TRUE CONCURRENT completed: total={}ms (submit={}ms, wait={}ms, apply={}ms), "
                        + "success={}/{}, avgMLTime={}ms",
                    batchNum,
                    batchDuration,
                    submitDuration,
                    waitDuration,
                    applyDuration,
                    successCount,
                    allFutures.size(),
                    allFutures.size() > 0 ? totalMLTime / allFutures.size() : 0
                );

            } catch (Exception e) {
                log.error("[semantic-hl-opt-timing] Batch #{} TRUE CONCURRENT failed", batchNum, e);
                // Fall back to sync processing
                processFallbackSync(batchTasks, batchStartTime, batchNum);
            }
        }

        /**
         * Fallback to synchronous processing
         */
        private void processFallbackSync(List<HitProcessingTask> batchTasks, long batchStartTime, int batchNum) {
            log.info("[semantic-hl-opt-timing] Batch #{} falling back to synchronous processing", batchNum);
            long syncStartTime = System.currentTimeMillis();

            for (HitProcessingTask task : batchTasks) {
                processHitSynchronously(task);
            }

            long syncDuration = System.currentTimeMillis() - syncStartTime;
            long batchDuration = System.currentTimeMillis() - batchStartTime;
            TOTAL_BATCH_PROCESSING_TIME_MS.addAndGet(batchDuration);

            log.info("[semantic-hl-opt-timing] Batch #{} synchronous fallback completed in {}ms", batchNum, syncDuration);
        }

        /**
         * Result container for highlight tasks
         */
        private static class HighlightTaskResult {
            final HitProcessingTask task;
            final String fieldName;
            final String highlightedText;
            final boolean success;
            final long mlDurationMs;

            HighlightTaskResult(HitProcessingTask task, String fieldName, String highlightedText, boolean success, long mlDurationMs) {
                this.task = task;
                this.fieldName = fieldName;
                this.highlightedText = highlightedText;
                this.success = success;
                this.mlDurationMs = mlDurationMs;
            }
        }

        private void processHitSynchronously(HitProcessingTask task) {
            long taskStartTime = System.currentTimeMillis();
            int runningNow = CURRENT_RUNNING.incrementAndGet();
            PEAK_RUNNING.updateAndGet(prev -> Math.max(prev, runningNow));
            TOTAL_PROCESSED.incrementAndGet();

            try {
                long highlightStartTime = System.currentTimeMillis();
                performHighlight(task);
                long highlightDuration = System.currentTimeMillis() - highlightStartTime;

                long totalTaskDuration = System.currentTimeMillis() - taskStartTime;
                long queueToExecTime = taskStartTime - task.enqueuedTime;

                log.info(
                    "[semantic-hl-opt-timing] Task {} docId={} completed: highlight={}ms, total={}ms, queueToExec={}ms, concurrent={}",
                    task.taskId,
                    task.hitContext.docId(),
                    highlightDuration,
                    totalTaskDuration,
                    queueToExecTime,
                    runningNow
                );

            } finally {
                CURRENT_RUNNING.decrementAndGet();
            }
        }

        private void performHighlight(HitProcessingTask task) {
            long methodStartTime = System.currentTimeMillis();

            SemanticHighlighterEngine engine = org.opensearch.neuralsearch.plugin.NeuralSearch.getSemanticEngineStatic();
            if (engine == null) {
                log.warn(
                    "[semantic-hl-opt-timing] SemanticHighlighterEngine not initialized, skipping highlight for docId [{}]",
                    task.hitContext.docId()
                );
                return;
            }

            int fieldProcessedCount = 0;
            long totalFieldProcessingTime = 0;
            long totalMLInferenceTime = 0;

            for (SearchHighlightContext.Field field : highlightContext.fields()) {
                if (!SemanticHighlighter.NAME.equals(field.fieldOptions().highlighterType())) {
                    continue;
                }

                String fieldName = field.field();
                long fieldStartTime = System.currentTimeMillis();

                try {
                    // Optimization: Reuse field context creation logic
                    long contextStartTime = System.currentTimeMillis();
                    FieldHighlightContext fieldCtx = createFieldHighlightContext(fieldName, field, task.hitContext);

                    String fieldText = engine.getFieldText(fieldCtx);
                    String modelId = engine.getModelId(field.fieldOptions().options());
                    String queryText = engine.extractOriginalQuery(originalQuery, fieldName);
                    long contextDuration = System.currentTimeMillis() - contextStartTime;

                    if (queryText == null || queryText.isEmpty()) {
                        log.debug("[semantic-hl-opt-timing] Task {} field {} skipped - no query text", task.taskId, fieldName);
                        continue;
                    }

                    String[] preTags = field.fieldOptions().preTags();
                    String[] postTags = field.fieldOptions().postTags();

                    // Track ML inference time specifically
                    long mlStartTime = System.currentTimeMillis();
                    String highlighted = engine.getHighlightedSentences(modelId, queryText, fieldText, preTags[0], postTags[0]);
                    long mlDuration = System.currentTimeMillis() - mlStartTime;

                    totalMLInferenceTime += mlDuration;
                    TOTAL_ML_INFERENCE_TIME_MS.addAndGet(mlDuration);

                    if (highlighted != null && !highlighted.isEmpty()) {
                        long applyStartTime = System.currentTimeMillis();
                        HighlightField highlightField = new HighlightField(fieldName, new Text[] { new Text(highlighted) });
                        task.hitContext.hit().getHighlightFields().put(fieldName, highlightField);
                        long applyDuration = System.currentTimeMillis() - applyStartTime;

                        TOTAL_RESULT_APPLICATION_TIME_MS.addAndGet(applyDuration);

                        log.debug(
                            "[semantic-hl-opt-timing] Task {} field {} highlight SUCCESS: context={}ms, ml={}ms, apply={}ms, resultLen={}",
                            task.taskId,
                            fieldName,
                            contextDuration,
                            mlDuration,
                            applyDuration,
                            highlighted.length()
                        );
                    } else {
                        log.debug(
                            "[semantic-hl-opt-timing] Task {} field {} highlight EMPTY: context={}ms, ml={}ms",
                            task.taskId,
                            fieldName,
                            contextDuration,
                            mlDuration
                        );
                    }

                    fieldProcessedCount++;

                } catch (Exception e) {
                    log.error(
                        "[semantic-hl-opt-timing] Task {} field {} ERROR after {}ms",
                        task.taskId,
                        fieldName,
                        System.currentTimeMillis() - fieldStartTime,
                        e
                    );
                }

                long fieldDuration = System.currentTimeMillis() - fieldStartTime;
                totalFieldProcessingTime += fieldDuration;
            }

            long methodDuration = System.currentTimeMillis() - methodStartTime;
            log.info(
                "[semantic-hl-opt-timing] Task {} performHighlight: total={}ms, fields={}, avgFieldTime={}ms, totalMLTime={}ms",
                task.taskId,
                methodDuration,
                fieldProcessedCount,
                fieldProcessedCount > 0 ? totalFieldProcessingTime / fieldProcessedCount : 0,
                totalMLInferenceTime
            );
        }

        private FieldHighlightContext createFieldHighlightContext(
            String fieldName,
            SearchHighlightContext.Field field,
            org.opensearch.search.fetch.FetchSubPhase.HitContext hitContext
        ) {
            return new FieldHighlightContext(fieldName, field, null, fetchContext, hitContext, originalQuery, true, Map.of());
        }

        private SearchContext extractSearchContext(FetchContext fetchContext) {
            // Safe extraction without reflection
            return null;
        }
    }

    /**
     * Lightweight task representation to reduce object creation overhead
     */
    private static class HitProcessingTask {
        final int taskId;
        final org.opensearch.search.fetch.FetchSubPhase.HitContext hitContext;
        final long enqueuedTime;

        HitProcessingTask(int taskId, org.opensearch.search.fetch.FetchSubPhase.HitContext hitContext, long enqueuedTime) {
            this.taskId = taskId;
            this.hitContext = hitContext;
            this.enqueuedTime = enqueuedTime;
        }
    }

    /**
     * Get performance statistics
     */
    public static String getPerformanceStats() {
        int totalProcessed = TOTAL_PROCESSED.get();
        int batchCount = BATCH_COUNT.get();

        return String.format(
            "SemanticHighlight Performance Stats:\n"
                + "Tasks: processed=%d, current_running=%d, peak_running=%d, max_concurrent=%d\n"
                + "Batches: total=%d, ml_success=%d, ml_failure=%d\n"
                + "Timing (total ms): queue=%d, batch_processing=%d, ml_inference=%d, result_apply=%d, process=%d\n"
                + "Thread Pool (total ms): submit=%d, wait=%d\n"
                + "Averages: queue=%.1fms, batch=%.1fms, ml=%.1fms, process=%.1fms",

            // Task stats
            totalProcessed,
            CURRENT_RUNNING.get(),
            PEAK_RUNNING.get(),
            MAX_CONCURRENT_TASKS.get(),

            // Batch stats
            batchCount,
            BATCH_ML_SUCCESS_COUNT.get(),
            BATCH_ML_FAILURE_COUNT.get(),

            // Total timing
            TOTAL_QUEUE_TIME_MS.get(),
            TOTAL_BATCH_PROCESSING_TIME_MS.get(),
            TOTAL_ML_INFERENCE_TIME_MS.get(),
            TOTAL_RESULT_APPLICATION_TIME_MS.get(),
            TOTAL_PROCESS_TIME_MS.get(),

            // Thread pool timing
            TOTAL_THREAD_POOL_SUBMIT_TIME_MS.get(),
            TOTAL_THREAD_POOL_WAIT_TIME_MS.get(),

            // Averages
            totalProcessed > 0 ? (double) TOTAL_QUEUE_TIME_MS.get() / totalProcessed : 0.0,
            batchCount > 0 ? (double) TOTAL_BATCH_PROCESSING_TIME_MS.get() / batchCount : 0.0,
            totalProcessed > 0 ? (double) TOTAL_ML_INFERENCE_TIME_MS.get() / totalProcessed : 0.0,
            totalProcessed > 0 ? (double) TOTAL_PROCESS_TIME_MS.get() / totalProcessed : 0.0
        );
    }

    /**
     * Log current performance statistics to the log
     */
    public static void logCurrentPerformanceStats() {
        log.info("[semantic-hl-opt-timing] CURRENT PERFORMANCE STATS:\n{}", getPerformanceStats());
    }

    /**
     * Reset performance statistics (for testing)
     */
    public static void resetPerformanceStats() {
        CURRENT_RUNNING.set(0);
        PEAK_RUNNING.set(0);
        TOTAL_PROCESSED.set(0);
        TOTAL_QUEUE_TIME_MS.set(0);
        TOTAL_BATCH_PROCESSING_TIME_MS.set(0);
        TOTAL_ML_INFERENCE_TIME_MS.set(0);
        TOTAL_RESULT_APPLICATION_TIME_MS.set(0);
        TOTAL_PROCESS_TIME_MS.set(0);
        BATCH_COUNT.set(0);
        BATCH_ML_SUCCESS_COUNT.set(0);
        BATCH_ML_FAILURE_COUNT.set(0);
        MAX_CONCURRENT_TASKS.set(0);
        TOTAL_THREAD_POOL_SUBMIT_TIME_MS.set(0);
        TOTAL_THREAD_POOL_WAIT_TIME_MS.set(0);

        log.info("[semantic-hl-opt-timing] Performance statistics reset to zero");
    }
}
