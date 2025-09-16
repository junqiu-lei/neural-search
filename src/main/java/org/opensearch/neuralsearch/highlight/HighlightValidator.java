/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.highlight;

import lombok.extern.log4j.Log4j2;
import org.opensearch.action.search.SearchResponse;

/**
 * Pure validation logic for highlight configurations.
 * Single responsibility: validation only, no extraction.
 */
@Log4j2
public class HighlightValidator {

    /**
     * Validate the highlight configuration against the search response
     * @param config the configuration to validate
     * @param response the search response to validate against
     * @return validated configuration (may have validation error set)
     */
    public HighlightConfig validate(HighlightConfig config, SearchResponse response) {
        // If already invalid, return as-is
        if (!config.isValid()) {
            return config;
        }

        // Check for required fields
        if (config.getFieldName() == null || config.getFieldName().isEmpty()) {
            return config.withValidationError("No semantic highlight field found");
        }

        if (config.getModelId() == null || config.getModelId().isEmpty()) {
            return config.withValidationError("Model ID is required for semantic highlighting");
        }

        if (config.getQueryText() == null || config.getQueryText().isEmpty()) {
            return config.withValidationError("Query text is required for semantic highlighting");
        }

        // Check response has hits
        if (response == null || response.getHits() == null || response.getHits().getHits().length == 0) {
            return config.withValidationError("No search hits to highlight");
        }

        // Validate batch size if batch inference is enabled
        if (config.isBatchInference()) {
            if (config.getMaxBatchSize() <= 0) {
                return config.withValidationError("Invalid max batch size: " + config.getMaxBatchSize());
            }
            if (config.getMaxBatchSize() > SemanticHighlightingConstants.ABSOLUTE_MAX_BATCH_SIZE) {
                return config.withValidationError("Max batch size exceeds limit: " + config.getMaxBatchSize());
            }
        }

        log.debug("Validation successful for field: {}, modelId: {}", config.getFieldName(), config.getModelId());

        return config; // Valid as-is
    }
}
