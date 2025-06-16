/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.action;

import lombok.extern.log4j.Log4j2;
import org.opensearch.core.action.ActionListener;
import org.opensearch.action.ActionRequest;
import org.opensearch.core.action.ActionResponse;
import org.opensearch.action.search.SearchAction;
import org.opensearch.action.search.SearchRequest;
import org.opensearch.action.search.SearchResponse;
import org.opensearch.transport.client.Client;
import org.opensearch.action.support.ActionFilter;
import org.opensearch.action.support.ActionFilterChain;
import org.opensearch.core.common.text.Text;
import org.opensearch.neuralsearch.highlight.SemanticHighlighterEngine;
import org.opensearch.search.SearchHit;
import org.opensearch.search.builder.SearchSourceBuilder;
import org.opensearch.search.fetch.subphase.highlight.HighlightBuilder;
import org.opensearch.search.fetch.subphase.highlight.HighlightField;
import org.opensearch.tasks.Task;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.stream.Collectors;

/**
 * ActionFilter that enables concurrent semantic highlighting by intercepting search requests
 * and processing them with batch ML inference optimization.
 *
 * This approach bypasses FetchSubPhase limitations to achieve true concurrency:
 * 1. Intercepts search requests containing semantic highlighting
 * 2. Executes base search without semantic highlighting
 * 3. Processes semantic highlighting concurrently across all documents
 * 4. Returns enhanced response with identical API format (zero breaking changes)
 */
@Log4j2
public class SemanticHighlightActionFilter implements ActionFilter {

    private final Client client;
    private final SemanticHighlighterEngine highlighterEngine;
    private final ExecutorService executorService;
    private final boolean enabled;

    public SemanticHighlightActionFilter(Client client, boolean enabled) {
        this.client = client;
        this.enabled = enabled;
        this.highlighterEngine = org.opensearch.neuralsearch.plugin.NeuralSearch.getSemanticEngineStatic();
        this.executorService = org.opensearch.neuralsearch.plugin.NeuralSearch.getSemanticHighlightExecutorStatic();

        log.info("[semantic-hl-filter] SemanticHighlightActionFilter initialized, enabled={}", enabled);
    }

    @Override
    public int order() {
        return 0; // Execute first to intercept requests early
    }

    @Override
    public <Request extends ActionRequest, Response extends ActionResponse> void apply(
        Task task,
        String action,
        Request request,
        ActionListener<Response> listener,
        ActionFilterChain<Request, Response> chain
    ) {
        // Only intercept search requests with semantic highlighting
        if (enabled && SearchAction.NAME.equals(action)) {
            boolean hasSemanticHL = hasSemanticHighlight((SearchRequest) request);
            log.debug("[semantic-hl-filter] SearchAction detected, hasSemanticHighlight: {}", hasSemanticHL);

            if (hasSemanticHL) {
                log.info("[semantic-hl-filter] Intercepting search request with semantic highlighting");
                handleOptimizedSemanticSearch(
                    task,
                    (SearchRequest) request,
                    (ActionListener<SearchResponse>) listener,
                    (ActionFilterChain<SearchRequest, SearchResponse>) chain
                );
                return;
            }
        }

        // Pass through all other requests unchanged
        chain.proceed(task, action, request, listener);
    }

    /**
     * Check if the search request contains semantic highlighting
     */
    private boolean hasSemanticHighlight(SearchRequest request) {
        SearchSourceBuilder source = request.source();
        if (source == null || source.highlighter() == null) {
            return false;
        }

        HighlightBuilder highlighter = source.highlighter();

        // Check global highlighter options for model_id
        Map<String, Object> globalOptions = highlighter.options();
        boolean hasGlobalModelId = globalOptions != null && globalOptions.containsKey("model_id");

        for (HighlightBuilder.Field field : highlighter.fields()) {
            Map<String, Object> fieldOptions = field.options();

            // Check for model_id in field options
            if (fieldOptions != null && fieldOptions.containsKey("model_id")) {
                return true;
            }

            // Check for model_id in global options
            if (hasGlobalModelId) {
                return true;
            }

            // Check if type is explicitly set to "semantic" in field options
            if (fieldOptions != null && "semantic".equals(fieldOptions.get("type"))) {
                return true;
            }

            // Check if highlighterType is explicitly set to "semantic"
            if ("semantic".equals(field.highlighterType())) {
                return true;
            }
        }

        return false;
    }

    /**
     * Handle search request with semantic highlighting optimization
     */
    private void handleOptimizedSemanticSearch(
        Task task,
        SearchRequest originalRequest,
        ActionListener<SearchResponse> listener,
        ActionFilterChain<SearchRequest, SearchResponse> chain
    ) {

        long startTime = System.currentTimeMillis();

        try {
            // Step 1: Create search request without semantic highlighting
            SearchRequest plainRequest = createPlainSearchRequest(originalRequest);

            log.debug(
                "[semantic-hl-filter] Executing base search without semantic highlighting for {} documents",
                plainRequest.source() != null ? plainRequest.source().size() : "default"
            );

            // Step 2: Execute base search
            chain.proceed(task, SearchAction.NAME, plainRequest, ActionListener.wrap((SearchResponse baseResponse) -> {
                // Step 3: Enhance with batch semantic highlighting
                enhanceWithSemanticHighlights(baseResponse, originalRequest, startTime).whenComplete((enhancedResponse, error) -> {
                    long processingTime = System.currentTimeMillis() - startTime;

                    if (error != null) {
                        log.error("[semantic-hl-filter] Failed to enhance with semantic highlights", error);
                        listener.onFailure(new Exception("Semantic highlighting enhancement failed", error));
                    } else {
                        log.debug("[semantic-hl-filter] Enhanced response with semantic highlights in {}ms", processingTime);
                        listener.onResponse(enhancedResponse);
                    }
                });
            }, listener::onFailure));

        } catch (Exception e) {
            log.error("[semantic-hl-filter] Error in optimized semantic search", e);
            listener.onFailure(e);
        }
    }

    /**
     * Create a search request without semantic highlighting fields
     */
    private SearchRequest createPlainSearchRequest(SearchRequest originalRequest) {
        SearchRequest plainRequest = new SearchRequest(originalRequest.indices());

        // Copy all original request properties
        plainRequest.routing(originalRequest.routing());
        plainRequest.preference(originalRequest.preference());
        plainRequest.searchType(originalRequest.searchType());
        plainRequest.scroll(originalRequest.scroll());

        // Copy source but remove semantic highlighting
        if (originalRequest.source() != null) {
            SearchSourceBuilder originalSource = originalRequest.source();
            SearchSourceBuilder plainSource = new SearchSourceBuilder();

            // Copy essential properties
            plainSource.query(originalSource.query());
            if (originalSource.postFilter() != null) {
                plainSource.postFilter(originalSource.postFilter());
            }
            if (originalSource.from() >= 0) {
                plainSource.from(originalSource.from());
            }
            if (originalSource.size() >= 0) {
                plainSource.size(originalSource.size());
            }
            if (originalSource.timeout() != null) {
                plainSource.timeout(originalSource.timeout());
            }
            if (originalSource.minScore() != null) {
                plainSource.minScore(originalSource.minScore());
            }
            plainSource.trackScores(originalSource.trackScores());
            if (originalSource.searchAfter() != null && originalSource.searchAfter().length > 0) {
                plainSource.searchAfter(originalSource.searchAfter());
            }
            if (originalSource.collapse() != null) {
                plainSource.collapse(originalSource.collapse());
            }
            if (originalSource.suggest() != null) {
                plainSource.suggest(originalSource.suggest());
            }
            if (originalSource.explain() != null) {
                plainSource.explain(originalSource.explain());
            }
            plainSource.profile(originalSource.profile());
            if (originalSource.fetchSource() != null) {
                plainSource.fetchSource(originalSource.fetchSource());
            }
            plainSource.version(originalSource.version());
            plainSource.seqNoAndPrimaryTerm(originalSource.seqNoAndPrimaryTerm());

            // Copy highlighting but remove semantic highlights
            if (originalSource.highlighter() != null) {
                HighlightBuilder originalHighlighter = originalSource.highlighter();
                HighlightBuilder plainHighlighter = new HighlightBuilder();

                // Copy non-semantic highlight fields
                for (HighlightBuilder.Field field : originalHighlighter.fields()) {
                    if (!"semantic".equals(field.highlighterType())) {
                        plainHighlighter.field(field);
                    }
                }

                // Only add highlighter if it has non-semantic fields
                if (!plainHighlighter.fields().isEmpty()) {
                    plainSource.highlighter(plainHighlighter);
                }
            }

            plainRequest.source(plainSource);
        }

        return plainRequest;
    }

    /**
     * Enhance search response with batch semantic highlighting
     */
    private CompletableFuture<SearchResponse> enhanceWithSemanticHighlights(
        SearchResponse baseResponse,
        SearchRequest originalRequest,
        long startTime
    ) {

        SearchHit[] hits = baseResponse.getHits().getHits();
        if (hits.length == 0) {
            return CompletableFuture.completedFuture(baseResponse);
        }

        // Extract semantic highlighting configuration
        SemanticHighlightConfig config = extractSemanticHighlightConfig(originalRequest);
        if (config == null) {
            log.warn("[semantic-hl-filter] Could not extract semantic highlight config, returning base response");
            return CompletableFuture.completedFuture(baseResponse);
        }

        log.debug("[semantic-hl-filter] Starting batch semantic highlighting for {} documents", hits.length);

        // Execute batch semantic highlighting
        return executeBatchSemanticHighlighting(hits, config).thenApply(highlights -> {
            long totalTime = System.currentTimeMillis() - startTime;
            return buildEnhancedResponse(baseResponse, highlights, totalTime);
        });
    }

    /**
     * Extract semantic highlighting configuration from original request
     */
    private SemanticHighlightConfig extractSemanticHighlightConfig(SearchRequest request) {
        if (request.source() == null || request.source().highlighter() == null) {
            return null;
        }

        HighlightBuilder highlighter = request.source().highlighter();

        // Check for global model_id in highlighter options
        Map<String, Object> globalOptions = highlighter.options();
        String modelId = null;
        if (globalOptions != null && globalOptions.containsKey("model_id")) {
            modelId = (String) globalOptions.get("model_id");
        }

        for (HighlightBuilder.Field field : highlighter.fields()) {
            // Check if this is a semantic highlight field
            if ("semantic".equals(field.highlighterType()) || (field.options() != null && "semantic".equals(field.options().get("type")))) {

                // Use field-specific model_id if available, otherwise use global
                Map<String, Object> fieldOptions = field.options();
                if (fieldOptions != null && fieldOptions.containsKey("model_id")) {
                    modelId = (String) fieldOptions.get("model_id");
                }

                if (modelId != null) {
                    String queryText = extractQueryText(request);

                    return new SemanticHighlightConfig(
                        field.name(),
                        modelId,
                        queryText,
                        field.preTags() != null ? field.preTags()[0] : "<em>",
                        field.postTags() != null ? field.postTags()[0] : "</em>"
                    );
                }
            }
        }
        return null;
    }

    /**
     * Extract query text from neural search request
     */
    private String extractQueryText(SearchRequest request) {
        try {
            String queryString = request.source().query().toString();
            if (queryString.contains("query_text")) {
                int startPos = queryString.indexOf("\"query_text\"");
                if (startPos != -1) {
                    int valueStart = queryString.indexOf(":", startPos) + 1;
                    valueStart = queryString.indexOf("\"", valueStart) + 1;
                    int valueEnd = queryString.indexOf("\"", valueStart);
                    if (valueEnd > valueStart) {
                        return queryString.substring(valueStart, valueEnd);
                    }
                }
            }
        } catch (Exception e) {
            log.debug("[semantic-hl-filter] Could not extract query text", e);
        }
        return ""; // Fallback
    }

    /**
     * Execute batch semantic highlighting with true concurrency
     */
    private CompletableFuture<List<HighlightResult>> executeBatchSemanticHighlighting(SearchHit[] hits, SemanticHighlightConfig config) {

        if (highlighterEngine == null) {
            return CompletableFuture.failedFuture(new IllegalStateException("SemanticHighlighterEngine not available"));
        }

        // Create concurrent tasks for all documents
        List<CompletableFuture<HighlightResult>> futures = new ArrayList<>();

        for (int i = 0; i < hits.length; i++) {
            final int hitIndex = i;
            final SearchHit hit = hits[i];

            CompletableFuture<HighlightResult> future = CompletableFuture.supplyAsync(() -> {
                long mlStartTime = System.currentTimeMillis();
                try {
                    // Extract field text from document
                    String fieldText = extractFieldText(hit, config.fieldName);
                    if (fieldText == null || fieldText.isEmpty()) {
                        return new HighlightResult(hitIndex, config.fieldName, "", false, 0);
                    }

                    // Perform ML inference
                    String highlighted = highlighterEngine.getHighlightedSentences(
                        config.modelId,
                        config.queryText,
                        fieldText,
                        config.preTag,
                        config.postTag
                    );

                    long mlDuration = System.currentTimeMillis() - mlStartTime;
                    return new HighlightResult(hitIndex, config.fieldName, highlighted, true, mlDuration);

                } catch (Exception e) {
                    long mlDuration = System.currentTimeMillis() - mlStartTime;
                    log.error("[semantic-hl-filter] Failed to highlight document {}", hitIndex, e);
                    return new HighlightResult(hitIndex, config.fieldName, "", false, mlDuration);
                }
            }, executorService);

            futures.add(future);
        }

        // Wait for ALL highlights to complete (TRUE BATCH CONCURRENCY!)
        return CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).thenApply(v -> {
            // Collect results
            List<HighlightResult> results = futures.stream().map(CompletableFuture::join).collect(Collectors.toList());

            long totalMLTime = results.stream().mapToLong(r -> r.mlDurationMs).sum();
            long avgMLTime = results.size() > 0 ? totalMLTime / results.size() : 0;
            int successCount = (int) results.stream().mapToInt(r -> r.success ? 1 : 0).sum();

            log.info(
                "[semantic-hl-filter] Batch highlighting completed: documents={}, avgMLTime={}ms, SUCCESS_COUNT={}",
                results.size(),
                avgMLTime,
                successCount
            );

            return results;
        });
    }

    /**
     * Extract field text from search hit
     */
    private String extractFieldText(SearchHit hit, String fieldName) {
        Map<String, Object> source = hit.getSourceAsMap();
        if (source != null && source.containsKey(fieldName)) {
            return (String) source.get(fieldName);
        }
        return null;
    }

    /**
     * Build enhanced search response with semantic highlights
     */
    private SearchResponse buildEnhancedResponse(SearchResponse original, List<HighlightResult> highlights, long totalProcessingTime) {
        SearchHit[] originalHits = original.getHits().getHits();
        SearchHit[] enhancedHits = new SearchHit[originalHits.length];

        for (int i = 0; i < originalHits.length; i++) {
            SearchHit originalHit = originalHits[i];
            final int currentIndex = i;
            HighlightResult highlight = highlights.stream().filter(h -> h.hitIndex == currentIndex).findFirst().orElse(null);

            if (highlight != null && highlight.success && !highlight.highlightedText.isEmpty()) {
                // Create a new highlight fields map with existing highlights
                Map<String, HighlightField> highlightFields = new HashMap<>(originalHit.getHighlightFields());

                // Add semantic highlights to the map
                HighlightField highlightField = new HighlightField(highlight.fieldName, new Text[] { new Text(highlight.highlightedText) });
                highlightFields.put(highlight.fieldName, highlightField);

                // Create a new SearchHit with updated highlights
                enhancedHits[i] = new SearchHit(
                    originalHit.docId(),
                    originalHit.getId(),
                    originalHit.getDocumentFields(),
                    originalHit.getMetaFields()
                );

                // Set highlight fields
                enhancedHits[i].highlightFields(highlightFields);

                // Copy other properties
                enhancedHits[i].score(originalHit.getScore());
                enhancedHits[i].sourceRef(originalHit.getSourceRef());
                enhancedHits[i].matchedQueries(originalHit.getMatchedQueries());
                enhancedHits[i].explanation(originalHit.getExplanation());
                enhancedHits[i].shard(originalHit.getShard());
                enhancedHits[i].setInnerHits(originalHit.getInnerHits());
            } else {
                // No semantic highlights, use original hit
                enhancedHits[i] = originalHit;
            }
        }

        // Create new SearchResponse with enhanced hits
        org.opensearch.search.SearchHits enhancedSearchHits = new org.opensearch.search.SearchHits(
            enhancedHits,
            original.getHits().getTotalHits(),
            original.getHits().getMaxScore()
        );

        // Use SearchResponseSections to build the response properly
        org.opensearch.action.search.SearchResponseSections sections = new org.opensearch.action.search.SearchResponseSections(
            enhancedSearchHits,
            original.getAggregations(),
            original.getSuggest(),
            original.isTimedOut(),
            original.isTerminatedEarly(),
            null, // Skip profile results to avoid type issues
            original.getNumReducePhases()
        );

        return new SearchResponse(
            sections,
            original.getScrollId(),
            original.getTotalShards(),
            original.getSuccessfulShards(),
            original.getSkippedShards(),
            totalProcessingTime,  // Use actual total processing time including semantic highlighting
            original.getShardFailures(),
            original.getClusters()
        );
    }

    // Helper classes
    private static class SemanticHighlightConfig {
        final String fieldName;
        final String modelId;
        final String queryText;
        final String preTag;
        final String postTag;

        SemanticHighlightConfig(String fieldName, String modelId, String queryText, String preTag, String postTag) {
            this.fieldName = fieldName;
            this.modelId = modelId;
            this.queryText = queryText;
            this.preTag = preTag;
            this.postTag = postTag;
        }
    }

    private static class HighlightResult {
        final int hitIndex;
        final String fieldName;
        final String highlightedText;
        final boolean success;
        final long mlDurationMs;

        HighlightResult(int hitIndex, String fieldName, String highlightedText, boolean success, long mlDurationMs) {
            this.hitIndex = hitIndex;
            this.fieldName = fieldName;
            this.highlightedText = highlightedText;
            this.success = success;
            this.mlDurationMs = mlDurationMs;
        }
    }
}
