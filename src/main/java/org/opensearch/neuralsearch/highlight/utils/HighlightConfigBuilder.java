/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.highlight.utils;

import lombok.extern.log4j.Log4j2;
import org.apache.lucene.search.Query;
import org.opensearch.action.search.SearchRequest;
import org.opensearch.action.search.SearchResponse;
import org.opensearch.neuralsearch.highlight.batch.config.HighlightConfig;
import org.opensearch.neuralsearch.highlight.single.extractor.QueryTextExtractorRegistry;
import org.opensearch.search.fetch.subphase.highlight.FieldHighlightContext;
import org.opensearch.search.fetch.subphase.highlight.HighlightBuilder;

import java.util.Map;

/**
 * Unified configuration builder for semantic highlighting.
 * Provides configuration building for both single and batch semantic highlighting modes.
 */
@Log4j2
public class HighlightConfigBuilder {

    /**
     * Build configuration from search request and response (for batch processing)
     * @param request the search request
     * @param response the search response
     * @return extracted and validated configuration
     */
    public static HighlightConfig buildFromSearchRequest(SearchRequest request, SearchResponse response) {
        try {
            if (request == null || request.source() == null) {
                log.debug("No search request source to extract from");
                return HighlightConfig.empty();
            }

            HighlightBuilder highlighter = request.source().highlighter();
            if (highlighter == null) {
                log.debug("No highlighter in request");
                return HighlightConfig.empty();
            }

            String fieldName = HighlightExtractorUtils.extractSemanticField(highlighter);
            String modelId = HighlightExtractorUtils.extractModelId(highlighter);
            String queryText = HighlightExtractorUtils.extractQueryText(request);

            // Extract batch inference settings from options
            boolean batchInference = HighlightExtractorUtils.extractBatchInference(highlighter);
            int maxBatchSize = HighlightExtractorUtils.extractMaxBatchSize(highlighter);

            HighlightConfig config = HighlightConfig.builder()
                .fieldName(fieldName)      // Can be null
                .modelId(modelId)          // Can be null
                .queryText(queryText)      // Can be null
                .preTag(HighlightExtractorUtils.extractPreTag(highlighter))
                .postTag(HighlightExtractorUtils.extractPostTag(highlighter))
                .batchInference(batchInference)
                .maxBatchSize(maxBatchSize)
                .build();

            // Validate the configuration
            return HighlightValidator.validate(config, response);

        } catch (Exception e) {
            log.error("Failed to extract highlight configuration", e);
            return HighlightConfig.invalid("Configuration extraction failed: " + e.getMessage());
        }
    }

    /**
     * Build configuration from field highlight context (for single field highlighting)
     * @param fieldContext the field highlight context
     * @param query the search query
     * @param queryTextExtractorRegistry the query text extractor registry
     * @return extracted and validated configuration
     */
    public static HighlightConfig buildFromFieldContext(
        FieldHighlightContext fieldContext,
        Query query,
        QueryTextExtractorRegistry queryTextExtractorRegistry
    ) {
        try {
            String fieldName = fieldContext.fieldName;
            String modelId = HighlightExtractorUtils.getModelId(fieldContext.field.fieldOptions().options());

            // Extract query text using the registry (provided as parameter)
            String queryText = null;
            if (queryTextExtractorRegistry != null) {
                queryText = HighlightExtractorUtils.extractOriginalQuery(query, fieldName, queryTextExtractorRegistry);
            }
            // Note: Query text extraction for single field mode works via the passed registry parameter

            HighlightConfig config = HighlightConfig.builder()
                .fieldName(fieldName)
                .modelId(modelId)
                .queryText(queryText)
                .preTag(extractPreTagFromField(fieldContext))
                .postTag(extractPostTagFromField(fieldContext))
                .batchInference(false) // Single field mode doesn't use batch
                .build();

            // Basic validation (no response context in single field mode)
            return HighlightValidator.validateBasic(config);

        } catch (Exception e) {
            log.error("Failed to build configuration from field context", e);
            return HighlightConfig.invalid("Configuration building failed: " + e.getMessage());
        }
    }

    /**
     * Extract pre tag from field context
     * @param fieldContext the field highlight context
     * @return pre tag
     */
    private static String extractPreTagFromField(FieldHighlightContext fieldContext) {
        Map<String, Object> fieldOptions = fieldContext.field.fieldOptions().options();
        if (fieldOptions != null && fieldOptions.containsKey("pre_tag")) {
            Object preTagValue = fieldOptions.get("pre_tag");
            if (preTagValue instanceof String) {
                return (String) preTagValue;
            }
        }
        // Default pre tag if not found in field options
        return "<em>";
    }

    /**
     * Extract post tag from field context
     * @param fieldContext the field highlight context
     * @return post tag
     */
    private static String extractPostTagFromField(FieldHighlightContext fieldContext) {
        Map<String, Object> fieldOptions = fieldContext.field.fieldOptions().options();
        if (fieldOptions != null && fieldOptions.containsKey("post_tag")) {
            Object postTagValue = fieldOptions.get("post_tag");
            if (postTagValue instanceof String) {
                return (String) postTagValue;
            }
        }
        // Default post tag if not found in field options
        return "</em>";
    }
}
