/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.highlight;

import lombok.extern.log4j.Log4j2;
import org.opensearch.action.search.SearchRequest;
import org.opensearch.action.search.SearchResponse;
import org.opensearch.core.action.ActionListener;
import org.opensearch.core.common.text.Text;
import org.opensearch.neuralsearch.ml.MLCommonsClientAccessor;
import org.opensearch.neuralsearch.processor.highlight.SentenceHighlightingRequest;
import org.opensearch.neuralsearch.processor.util.ProcessorUtils;
import org.opensearch.search.SearchHit;
import org.opensearch.search.builder.SearchSourceBuilder;
import org.opensearch.search.fetch.subphase.highlight.HighlightBuilder;
import org.opensearch.search.fetch.subphase.highlight.HighlightField;
import org.opensearch.search.pipeline.PipelineProcessingContext;
import org.opensearch.search.pipeline.SearchResponseProcessor;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;

import static org.opensearch.neuralsearch.highlight.SemanticHighlightingConstants.HIGHLIGHTS_KEY;
import static org.opensearch.neuralsearch.highlight.SemanticHighlightingConstants.PROCESSOR_TYPE;
import static org.opensearch.neuralsearch.highlight.SemanticHighlightingConstants.START_KEY;
import static org.opensearch.neuralsearch.highlight.SemanticHighlightingConstants.END_KEY;

/**
 * Semantic highlighting response processor that implements batch semantic highlighting
 * using composition pattern with ML inference capabilities
 */
@Log4j2
public class SemanticHighlightingResponseProcessor implements SearchResponseProcessor {
    private static final int DEFAULT_MAX_BATCH_SIZE = 100;
    private static final String DEFAULT_PRE_TAG = "<em>";
    private static final String DEFAULT_POST_TAG = "</em>";
    private static final String MODEL_ID_OPTION = "model_id";

    private final MLCommonsClientAccessor mlClientAccessor;

    private final String tag;
    private final String description;
    private final boolean ignoreFailure;
    private final String modelId;
    private final boolean batchInference;
    private final int maxInferenceBatchSize;
    private final String preTag;
    private final String postTag;

    public SemanticHighlightingResponseProcessor(
        String tag,
        String description,
        boolean ignoreFailure,
        String modelId,
        MLCommonsClientAccessor mlClientAccessor,
        boolean batchInference,
        int maxInferenceBatchSize,
        String preTag,
        String postTag
    ) {
        this.tag = tag;
        this.description = description;
        this.ignoreFailure = ignoreFailure;
        this.modelId = modelId;
        this.mlClientAccessor = mlClientAccessor;
        this.batchInference = batchInference;
        this.maxInferenceBatchSize = maxInferenceBatchSize;
        this.preTag = preTag;
        this.postTag = postTag;
    }

    @Override
    public void processResponseAsync(
        SearchRequest request,
        SearchResponse response,
        PipelineProcessingContext responseContext,
        ActionListener<SearchResponse> responseListener
    ) {
        long startTime = System.currentTimeMillis();

        try {
            validateHighlightRequest(request);
            String semanticHighlightField = extractSemanticHighlightField(request);

            // Extract model ID if specified in highlight options
            String effectiveModelId = extractModelIdFromHighlight(request);

            if (semanticHighlightField == null) {
                responseListener.onResponse(response);
                return;
            }

            SearchHit[] hits = response.getHits().getHits();
            if (hits.length == 0) {
                responseListener.onResponse(response);
                return;
            }

            String queryText = extractQueryText(request);

            // Process semantic highlighting
            processSemanticHighlighting(response, queryText, semanticHighlightField, effectiveModelId, responseListener, startTime);
        } catch (Exception e) {
            handleProcessingError(e, response, responseListener);
        }
    }

    @Override
    public SearchResponse processResponse(SearchRequest request, SearchResponse response) {
        throw new UnsupportedOperationException(String.format(Locale.ROOT, "%s processor requires async processing", PROCESSOR_TYPE));
    }

    /**
     * Validate highlight request using ProcessorUtils patterns
     */
    private void validateHighlightRequest(SearchRequest request) {
        if (request == null) {
            throw new IllegalArgumentException(String.format(Locale.ROOT, "search request cannot be null"));
        }
        if (request.source() == null) {
            throw new IllegalArgumentException(String.format(Locale.ROOT, "search request source cannot be null"));
        }
    }

    /**
     * Extract semantic highlight field from search request
     */
    private String extractSemanticHighlightField(SearchRequest request) {
        List<HighlightBuilder.Field> fields = Optional.ofNullable(request.source())
            .map(SearchSourceBuilder::highlighter)
            .map(HighlightBuilder::fields)
            .orElse(Collections.emptyList());

        return fields.stream()
            .filter(field -> SemanticHighlightingConstants.HIGHLIGHTER_TYPE.equals(field.highlighterType()))
            .findFirst()
            .map(HighlightBuilder.Field::name)
            .orElse(null);
    }

    /**
     * Extract model ID from highlight options if present
     */
    private String extractModelIdFromHighlight(SearchRequest request) {
        if (request.source() == null || request.source().highlighter() == null) {
            return modelId; // Use default from constructor
        }

        HighlightBuilder highlighter = request.source().highlighter();

        // Check global highlighter options first
        Map<String, Object> options = highlighter.options();
        if (options != null && options.containsKey(MODEL_ID_OPTION)) {
            Object modelIdValue = options.get(MODEL_ID_OPTION);
            if (modelIdValue instanceof String) {
                return (String) modelIdValue;
            }
        }

        // Check field-specific options for semantic highlighting field
        for (HighlightBuilder.Field field : highlighter.fields()) {
            if (SemanticHighlightingConstants.HIGHLIGHTER_TYPE.equals(field.highlighterType())) {
                Map<String, Object> fieldOptions = field.options();
                if (fieldOptions != null && fieldOptions.containsKey(MODEL_ID_OPTION)) {
                    Object modelIdValue = fieldOptions.get(MODEL_ID_OPTION);
                    if (modelIdValue instanceof String) {
                        return (String) modelIdValue;
                    }
                }
            }
        }

        return modelId; // Use default from constructor
    }

    /**
     * Extract query text from search request for semantic highlighting
     */
    private String extractQueryText(SearchRequest request) {
        return Optional.ofNullable(request.source())
            .map(SearchSourceBuilder::query)
            .map(ProcessorUtils::extractQueryTextFromBuilder)
            .orElseThrow(() -> new IllegalArgumentException("Query text is required for semantic highlighting"));
    }

    /**
     * Extract field text from search hit using ProcessorUtils
     */
    private String extractFieldText(SearchHit hit, String fieldName) {
        return ProcessorUtils.getValueFromSource(hit.getSourceAsMap(), fieldName).map(Object::toString).orElse(null);
    }

    /**
     * Process semantic highlighting
     */
    private void processSemanticHighlighting(
        SearchResponse response,
        String queryText,
        String semanticHighlightField,
        String effectiveModelId,
        ActionListener<SearchResponse> responseListener,
        long startTime
    ) {
        try {
            SearchHit[] hits = response.getHits().getHits();

            // Collect regular hits for processing
            List<SentenceHighlightingRequest> requests = new ArrayList<>();
            List<SearchHit> validHits = new ArrayList<>();

            for (SearchHit hit : hits) {
                String fieldText = extractFieldText(hit, semanticHighlightField);
                if (fieldText != null && !fieldText.isEmpty()) {
                    requests.add(
                        SentenceHighlightingRequest.builder().modelId(effectiveModelId).question(queryText).context(fieldText).build()
                    );
                    validHits.add(hit);
                }
            }

            if (requests.isEmpty()) {
                responseListener.onResponse(response);
                return;
            }

            // Process requests
            if (batchInference) {
                processBatchRequests(requests, validHits, response, semanticHighlightField, responseListener, startTime);
            } else {
                processSequentialRequests(requests, validHits, response, semanticHighlightField, responseListener, startTime);
            }
        } catch (Exception e) {
            handleProcessingError(e, response, responseListener);
        }
    }

    /**
     * Handle errors with ignore failure logic
     */
    private void handleProcessingError(Exception error, SearchResponse response, ActionListener<SearchResponse> responseListener) {
        if (ignoreFailure) {
            log.warn(String.format(Locale.ROOT, "semantic highlighting failed but ignoring failure: %s", error.getMessage()));
            responseListener.onResponse(response);
        } else {
            responseListener.onFailure(error);
        }
    }

    /**
     * Process requests sequentially
     */
    private void processSequentialRequests(
        List<SentenceHighlightingRequest> requests,
        List<SearchHit> validHits,
        SearchResponse response,
        String semanticHighlightField,
        ActionListener<SearchResponse> responseListener,
        long startTime
    ) {
        processNextRequest(requests, validHits, 0, response, semanticHighlightField, responseListener, startTime);
    }

    /**
     * Process batch requests with size limits
     */
    private void processBatchRequests(
        List<SentenceHighlightingRequest> requests,
        List<SearchHit> validHits,
        SearchResponse response,
        String semanticHighlightField,
        ActionListener<SearchResponse> responseListener,
        long startTime
    ) {
        int maxBatchSize = maxInferenceBatchSize;

        if (requests.size() <= maxBatchSize) {
            mlClientAccessor.batchInferenceSentenceHighlighting(modelId, requests, ActionListener.wrap(batchResults -> {
                SearchResponse highlightedResponse = applyBatchHighlightResults(response, batchResults, validHits, semanticHighlightField);
                finalizeBatchResponse(highlightedResponse, responseListener, startTime);
            }, error -> handleProcessingError(error, response, responseListener)));
        } else {
            processNextBatch(requests, validHits, 0, maxBatchSize, response, semanticHighlightField, responseListener, startTime);
        }
    }

    private void processNextBatch(
        List<SentenceHighlightingRequest> allRequests,
        List<SearchHit> allValidHits,
        int startIndex,
        int batchSize,
        SearchResponse response,
        String semanticHighlightField,
        ActionListener<SearchResponse> responseListener,
        long startTime
    ) {
        if (startIndex >= allRequests.size()) {
            finalizeBatchResponse(response, responseListener, startTime);
            return;
        }

        int endIndex = Math.min(startIndex + batchSize, allRequests.size());

        // Use indices instead of creating sublists for better memory efficiency
        List<SentenceHighlightingRequest> batchRequests = new ArrayList<>(endIndex - startIndex);
        for (int i = startIndex; i < endIndex; i++) {
            batchRequests.add(allRequests.get(i));
        }

        mlClientAccessor.batchInferenceSentenceHighlighting(modelId, batchRequests, ActionListener.wrap(batchResults -> {
            try {
                applyBatchHighlightResultsWithIndices(response, batchResults, allValidHits, startIndex, endIndex, semanticHighlightField);
                processNextBatch(
                    allRequests,
                    allValidHits,
                    endIndex,
                    batchSize,
                    response,
                    semanticHighlightField,
                    responseListener,
                    startTime
                );
            } catch (Exception e) {
                handleProcessingError(e, response, responseListener);
            }
        }, error -> handleProcessingError(error, response, responseListener)));
    }

    private void finalizeBatchResponse(SearchResponse response, ActionListener<SearchResponse> responseListener, long startTime) {
        long totalTime = System.currentTimeMillis() - startTime;
        SearchResponse finalResponse = ProcessorUtils.updateResponseTookTime(response, totalTime);
        responseListener.onResponse(finalResponse);
    }

    private void processNextRequest(
        List<SentenceHighlightingRequest> requests,
        List<SearchHit> validHits,
        int currentIndex,
        SearchResponse response,
        String semanticHighlightField,
        ActionListener<SearchResponse> responseListener,
        long startTime
    ) {
        // Base case: all requests processed
        if (currentIndex >= requests.size()) {
            long totalTime = System.currentTimeMillis() - startTime;
            SearchResponse finalResponse = ProcessorUtils.updateResponseTookTime(response, totalTime);
            responseListener.onResponse(finalResponse);
            return;
        }

        // Process current request
        mlClientAccessor.inferenceSentenceHighlighting(requests.get(currentIndex), ActionListener.wrap(highlightResults -> {
            try {
                applySingleHighlightResults(validHits.get(currentIndex), highlightResults, semanticHighlightField);
                processNextRequest(requests, validHits, currentIndex + 1, response, semanticHighlightField, responseListener, startTime);
            } catch (Exception e) {
                handleProcessingError(e, response, responseListener);
            }
        }, error -> handleProcessingError(error, response, responseListener)));
    }

    /**
     * Apply highlights to a specific search hit
     */
    private void applyHighlightsToHit(SearchHit hit, List<Map<String, Object>> highlights, String fieldName) {
        Map<String, Object> source = hit.getSourceAsMap();
        if (source == null) {
            return;
        }

        String text = (String) source.get(fieldName);
        if (text == null || text.isEmpty()) {
            return;
        }

        String highlightedText = applyPositionHighlights(text, highlights);
        Map<String, HighlightField> highlightFields = Optional.ofNullable(hit.getHighlightFields()).orElse(new HashMap<>());
        HighlightField highlightField = new HighlightField(fieldName, new Text[] { new Text(highlightedText) });
        highlightFields.put(fieldName, highlightField);
        hit.highlightFields(highlightFields);
    }

    /**
     * Apply position-based highlights to text using ProcessorUtils for validation
     */
    private String applyPositionHighlights(String text, List<Map<String, Object>> highlights) {
        List<Map<String, Object>> validHighlights = new ArrayList<>();
        for (Map<String, Object> highlight : highlights) {
            Object startObj = highlight.get(START_KEY);
            Object endObj = highlight.get(END_KEY);

            if (ProcessorUtils.isNumeric(startObj) && ProcessorUtils.isNumeric(endObj)) {
                validHighlights.add(highlight);
            }
        }

        if (validHighlights.isEmpty()) {
            return text;
        }

        StringBuilder result = new StringBuilder(text);
        for (int i = validHighlights.size() - 1; i >= 0; i--) {
            Map<String, Object> highlight = validHighlights.get(i);
            int start = ((Number) highlight.get(START_KEY)).intValue();
            int end = ((Number) highlight.get(END_KEY)).intValue();

            if (start >= 0 && end <= text.length() && start < end) {
                result.insert(end, postTag);
                result.insert(start, preTag);
            }
        }

        return result.toString();
    }

    /**
     * Apply batch highlight results to search response using valid hits list
     */
    private SearchResponse applyBatchHighlightResults(
        SearchResponse response,
        List<List<Map<String, Object>>> batchResults,
        List<SearchHit> validHits,
        String semanticHighlightField
    ) {
        try {

            for (int i = 0; i < validHits.size() && i < batchResults.size(); i++) {
                List<Map<String, Object>> highlights = batchResults.get(i);
                if (!highlights.isEmpty()) {
                    applyHighlightsToHit(validHits.get(i), highlights, semanticHighlightField);
                }
            }
            return response;
        } catch (Exception e) {
            log.error("Error applying batch highlight results: {}", e.getMessage(), e);
            if (ignoreFailure) {
                return response;
            } else {
                throw new RuntimeException("Failed to apply batch highlight results", e);
            }
        }
    }

    /**
     * Apply batch highlight results using indices to avoid creating sublists
     */
    private void applyBatchHighlightResultsWithIndices(
        SearchResponse response,
        List<List<Map<String, Object>>> batchResults,
        List<SearchHit> allValidHits,
        int startIndex,
        int endIndex,
        String semanticHighlightField
    ) {
        try {
            int batchIndex = 0;
            for (int i = startIndex; i < endIndex && batchIndex < batchResults.size(); i++, batchIndex++) {
                List<Map<String, Object>> highlights = batchResults.get(batchIndex);
                if (!highlights.isEmpty()) {
                    applyHighlightsToHit(allValidHits.get(i), highlights, semanticHighlightField);
                }
            }
        } catch (Exception e) {
            log.error("Error applying batch highlight results with indices: {}", e.getMessage(), e);
            if (!ignoreFailure) {
                throw new RuntimeException("Failed to apply batch highlight results with indices", e);
            }
        }
    }

    /**
     * Apply single highlight results to a hit
     */
    private void applySingleHighlightResults(SearchHit hit, List<Map<String, Object>> highlightResults, String fieldName) {
        if (highlightResults == null || highlightResults.isEmpty()) {
            return;
        }

        Map<String, Object> mlResponse = highlightResults.get(0);
        if (mlResponse == null) {
            throw new IllegalStateException("ML response cannot be null");
        }
        if (!mlResponse.containsKey(HIGHLIGHTS_KEY)) {
            throw new IllegalStateException("ML response missing required '" + HIGHLIGHTS_KEY + "' field");
        }

        Object highlightsObj = mlResponse.get(HIGHLIGHTS_KEY);
        if (!(highlightsObj instanceof List)) {
            throw new IllegalStateException(
                "Expected highlights to be a List, got: " + (highlightsObj != null ? highlightsObj.getClass().getSimpleName() : "null")
            );
        }

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> highlights = (List<Map<String, Object>>) highlightsObj;
        applyHighlightsToHit(hit, highlights, fieldName);
    }

    @Override
    public String getType() {
        return PROCESSOR_TYPE;
    }

    @Override
    public String getTag() {
        return tag;
    }

    @Override
    public String getDescription() {
        return description;
    }

    @Override
    public boolean isIgnoreFailure() {
        return ignoreFailure;
    }

}
