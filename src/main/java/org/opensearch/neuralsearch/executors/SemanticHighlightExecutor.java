/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.executors;

import lombok.AccessLevel;
import lombok.NoArgsConstructor;
import lombok.experimental.PackagePrivate;
import lombok.extern.log4j.Log4j2;
import org.opensearch.common.settings.Settings;
import org.opensearch.common.util.concurrent.OpenSearchExecutors;
import org.opensearch.threadpool.ExecutorBuilder;
import org.opensearch.threadpool.FixedExecutorBuilder;
import org.opensearch.threadpool.ThreadPool;

import java.util.concurrent.ExecutorService;

/**
 * {@link SemanticHighlightExecutor} provides dedicated thread pool implementation for
 * semantic highlighting operations. This ensures that semantic highlighting operations
 * do not compete with generic OpenSearch operations for thread pool resources.
 * The thread pool size is configured based on available processors to optimize
 * parallel processing of semantic highlighting tasks.
 */
@Log4j2
@NoArgsConstructor(access = AccessLevel.PRIVATE)
public final class SemanticHighlightExecutor {
    private static final String SEMANTIC_HIGHLIGHT_THREAD_POOL_NAME = "_plugin_neural_search_semantic_highlight";
    private static final Integer SEMANTIC_HIGHLIGHT_THREAD_POOL_QUEUE_SIZE = 1000;
    private static final Integer MAX_THREAD_SIZE = 500;
    private static final Integer MIN_THREAD_SIZE = 2;
    private static final Integer PROCESSOR_COUNT_MULTIPLIER = 1;
    private static ExecutorService executorService;

    /**
     * Provide fixed executor builder to use for semantic highlight executors
     * @param settings Node level settings
     * @return the executor builder for semantic highlight's custom thread pool.
     */
    public static ExecutorBuilder getExecutorBuilder(final Settings settings) {
        int numberOfThreads = getFixedNumberOfThreadSize(settings);
        log.info("[semantic-hl] Creating dedicated thread pool with {} threads", numberOfThreads);
        return new FixedExecutorBuilder(
            settings,
            SEMANTIC_HIGHLIGHT_THREAD_POOL_NAME,
            numberOfThreads,
            SEMANTIC_HIGHLIGHT_THREAD_POOL_QUEUE_SIZE,
            SEMANTIC_HIGHLIGHT_THREAD_POOL_NAME
        );
    }

    /**
     * Initialize ExecutorService to run semantic highlighting tasks using dedicated {@link ThreadPool}
     * @param threadPool OpenSearch's thread pool instance
     */
    public static void initialize(ThreadPool threadPool) {
        if (threadPool == null) {
            log.error("[semantic-hl] ThreadPool is null - cannot initialize SemanticHighlightExecutor");
            throw new IllegalArgumentException(
                "Argument thread-pool to Semantic Highlight Executor cannot be null. This is required to build executor to run semantic highlighting in parallel"
            );
        }
        try {
            executorService = threadPool.executor(SEMANTIC_HIGHLIGHT_THREAD_POOL_NAME);
            if (executorService == null) {
                log.error("[semantic-hl] Failed to get executor from thread pool: {}", SEMANTIC_HIGHLIGHT_THREAD_POOL_NAME);
                throw new IllegalStateException("Failed to initialize semantic highlight executor from thread pool");
            }
            log.info("[semantic-hl] Dedicated thread pool initialized: {}", SEMANTIC_HIGHLIGHT_THREAD_POOL_NAME);
        } catch (Exception e) {
            log.error("[semantic-hl] Error initializing SemanticHighlightExecutor", e);
            throw e;
        }
    }

    /**
     * Return ExecutorService for semantic highlighting tasks
     * @return ExecutorService instance to run semantic highlighting tasks in parallel
     */
    public static ExecutorService getExecutor() {
        if (executorService == null) {
            log.warn("[semantic-hl] ExecutorService is null - SemanticHighlightExecutor may not be properly initialized");
        }
        return executorService;
    }

    @PackagePrivate
    public static String getThreadPoolName() {
        return SEMANTIC_HIGHLIGHT_THREAD_POOL_NAME;
    }

    /**
     * Calculate thread size based on allocated processors.
     * For semantic highlighting, we use 1x allocated processors as it's more CPU intensive.
     * Minimum is 2 threads, maximum is 500 threads to avoid resource exhaustion.
     */
    private static int getFixedNumberOfThreadSize(final Settings settings) {
        final int allocatedProcessors = OpenSearchExecutors.allocatedProcessors(settings);
        int threadSize = Math.max(PROCESSOR_COUNT_MULTIPLIER * allocatedProcessors, MIN_THREAD_SIZE);
        return Math.min(threadSize, MAX_THREAD_SIZE);
    }
}
