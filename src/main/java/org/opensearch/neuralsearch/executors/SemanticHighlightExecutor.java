/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.executors;

import lombok.extern.log4j.Log4j2;
import org.opensearch.common.settings.Settings;
import org.opensearch.threadpool.ExecutorBuilder;
import org.opensearch.threadpool.FixedExecutorBuilder;
import org.opensearch.threadpool.ThreadPool;

import java.util.concurrent.ExecutorService;

/**
 * Executor for semantic highlighting tasks that enables concurrent ML inference processing.
 */
@Log4j2
public class SemanticHighlightExecutor {

    public static final String SEMANTIC_HIGHLIGHT_THREAD_POOL_NAME = "semantic_highlight";
    private static volatile ExecutorService staticExecutorService;

    /**
     * Initialize the semantic highlight executor with the given thread pool
     */
    public static void initialize(ThreadPool threadPool) {
        staticExecutorService = threadPool.executor(SEMANTIC_HIGHLIGHT_THREAD_POOL_NAME);
        log.info("SemanticHighlightExecutor initialized with thread pool: {}", SEMANTIC_HIGHLIGHT_THREAD_POOL_NAME);
    }

    /**
     * Get the executor service for semantic highlighting
     */
    public static ExecutorService getExecutorService() {
        return staticExecutorService;
    }

    /**
     * Get the executor builder for semantic highlighting thread pool
     */
    public static ExecutorBuilder<?> getExecutorBuilder(Settings settings) {
        int threadPoolSize = Math.max(1, Runtime.getRuntime().availableProcessors());
        int queueSize = 1000;

        log.info("Creating SemanticHighlightExecutor with {} threads and queue size {}", threadPoolSize, queueSize);

        return new FixedExecutorBuilder(
            settings,
            SEMANTIC_HIGHLIGHT_THREAD_POOL_NAME,
            threadPoolSize,
            queueSize,
            "thread_pool." + SEMANTIC_HIGHLIGHT_THREAD_POOL_NAME
        );
    }
}
