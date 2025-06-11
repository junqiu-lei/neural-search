/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.highlight;

import lombok.extern.log4j.Log4j2;
import org.opensearch.common.settings.Settings;
import org.opensearch.core.common.text.Text;
import org.opensearch.neuralsearch.settings.NeuralSearchSettings;
import org.opensearch.search.SearchHit;
import org.opensearch.search.fetch.FetchContext;
import org.opensearch.search.fetch.FetchSubPhase;
import org.opensearch.search.fetch.subphase.highlight.FieldHighlightContext;
import org.opensearch.search.fetch.subphase.highlight.HighlightField;
import org.opensearch.search.fetch.subphase.highlight.HighlightPhase;
import org.opensearch.search.fetch.subphase.highlight.SearchHighlightContext;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/**
 * FetchSubPhase implementation for parallel semantic highlighting.
 * This phase intercepts the fetch process and performs semantic highlighting
 * in parallel for improved performance.
 */
@Log4j2
public class ParallelSemanticHighlightFetchSubPhase implements FetchSubPhase {
    
    private final SemanticHighlighterEngine semanticHighlighterEngine;
    private final Settings settings;
    private volatile ExecutorService executorService;
    private volatile int parallelismLevel;
    
    public ParallelSemanticHighlightFetchSubPhase(SemanticHighlighterEngine semanticHighlighterEngine, Settings settings) {
        this.semanticHighlighterEngine = semanticHighlighterEngine;
        this.settings = settings;
        this.parallelismLevel = NeuralSearchSettings.SEMANTIC_HIGHLIGHT_PARALLELISM_LEVEL.get(settings);
        initializeExecutorService();
    }
    
    private void initializeExecutorService() {
        if (executorService != null) {
            executorService.shutdown();
        }
        executorService = Executors.newFixedThreadPool(parallelismLevel, r -> {
            Thread t = new Thread(r, "semantic-highlight-parallel");
            t.setDaemon(true);
            return t;
        });
    }
    
    public void updateParallelismLevel(int newLevel) {
        if (newLevel != parallelismLevel) {
            parallelismLevel = newLevel;
            initializeExecutorService();
        }
    }
    
    @Override
    public FetchSubPhase.FetchSubPhaseProcessor getProcessor(FetchContext context) throws IOException {
        // Check if semantic highlighting is requested
        SearchHighlightContext highlightContext = context.highlight();
        if (highlightContext == null) {
            return null;
        }
        
        // Check if any field uses semantic highlighting
        boolean hasSemanticHighlighting = false;
        for (SearchHighlightContext.Field field : highlightContext.fields()) {
            if (SemanticHighlighter.NAME.equals(field.fieldOptions().highlighterType())) {
                hasSemanticHighlighting = true;
                break;
            }
        }
        
        if (!hasSemanticHighlighting) {
            return null;
        }
        
        // Return our processor that will handle parallel highlighting
        return new ParallelSemanticHighlightProcessor(context);
    }
    
    /**
     * Processor that performs parallel semantic highlighting for each hit
     */
    private class ParallelSemanticHighlightProcessor implements FetchSubPhase.FetchSubPhaseProcessor {
        private final FetchContext fetchContext;
        
        ParallelSemanticHighlightProcessor(FetchContext fetchContext) {
            this.fetchContext = fetchContext;
        }
        
        @Override
        public void process(FetchSubPhase.HitContext hitContext) throws IOException {
            SearchHighlightContext highlightContext = fetchContext.highlight();
            if (highlightContext == null) {
                return;
            }
            
            // Process semantic highlighting for this hit
            SearchHit searchHit = hitContext.hit();
            Map<String, HighlightField> highlightFields = new HashMap<>();
            List<CompletableFuture<Void>> futures = new ArrayList<>();
            
            // Process each field that needs semantic highlighting
            for (SearchHighlightContext.Field field : highlightContext.fields()) {
                if (!SemanticHighlighter.NAME.equals(field.fieldOptions().highlighterType())) {
                    continue;
                }
                
                CompletableFuture<Void> future = CompletableFuture.runAsync(() -> {
                    try {
                        // Create field context
                        FieldHighlightContext fieldContext = new FieldHighlightContext(
                            field.field(),
                            field,
                            null, // mapper
                            fetchContext,
                            hitContext,
                            fetchContext.parsedQuery().query(),
                            highlightContext.forceSource(field),
                            new HashMap<>() // cache
                        );
                        
                        // Get field text
                        String fieldText = semanticHighlighterEngine.getFieldText(fieldContext);
                        
                        // Get model ID
                        String modelId = semanticHighlighterEngine.getModelId(field.fieldOptions().options());
                        
                        // Extract query text
                        String originalQueryText = semanticHighlighterEngine.extractOriginalQuery(
                            fetchContext.parsedQuery().query(),
                            field.field()
                        );
                        
                        if (originalQueryText == null || originalQueryText.isEmpty()) {
                            log.warn("No query text found for field {}", field.field());
                            return;
                        }
                        
                        // Get pre/post tags
                        String[] preTags = field.fieldOptions().preTags();
                        String[] postTags = field.fieldOptions().postTags();
                        
                        // Perform inference
                        String highlightedResponse = semanticHighlighterEngine.getHighlightedSentences(
                            modelId,
                            originalQueryText,
                            fieldText,
                            preTags[0],
                            postTags[0]
                        );
                        
                        if (highlightedResponse != null && !highlightedResponse.isEmpty()) {
                            Text[] fragments = new Text[] { new Text(highlightedResponse) };
                            HighlightField highlightField = new HighlightField(field.field(), fragments);
                            
                            synchronized (highlightFields) {
                                highlightFields.put(field.field(), highlightField);
                            }
                        }
                    } catch (Exception e) {
                        log.error("Error during parallel semantic highlighting for field {}", field.field(), e);
                    }
                }, executorService);
                
                futures.add(future);
            }
            
            // Wait for all highlighting tasks to complete
            if (!futures.isEmpty()) {
                CompletableFuture<Void> allOf = CompletableFuture.allOf(futures.toArray(new CompletableFuture[0]));
                try {
                    allOf.get(30, TimeUnit.SECONDS); // 30 second timeout
                    
                    // Apply highlight fields to the search hit
                    if (!highlightFields.isEmpty()) {
                        searchHit.highlightFields(highlightFields);
                    }
                } catch (Exception e) {
                    log.error("Error waiting for parallel highlighting to complete", e);
                }
            }
        }
    }
    
    public void shutdown() {
        if (executorService != null) {
            executorService.shutdown();
            try {
                if (!executorService.awaitTermination(5, TimeUnit.SECONDS)) {
                    executorService.shutdownNow();
                }
            } catch (InterruptedException e) {
                executorService.shutdownNow();
                Thread.currentThread().interrupt();
            }
        }
    }
}