/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.highlight;

import lombok.Builder;
import lombok.Getter;
import lombok.NonNull;
import lombok.With;

/**
 * Immutable configuration for semantic highlighting.
 * Replaces ValidationResult with a cleaner builder-based approach.
 */
@Getter
@Builder(toBuilder = true)
public class HighlightConfig {

    @NonNull
    private final String fieldName;

    @NonNull
    private final String modelId;

    @NonNull
    private final String queryText;

    @Builder.Default
    private final String preTag = SemanticHighlightingConstants.DEFAULT_PRE_TAG;

    @Builder.Default
    private final String postTag = SemanticHighlightingConstants.DEFAULT_POST_TAG;

    @Builder.Default
    private final boolean batchInference = false;

    @Builder.Default
    private final int maxBatchSize = SemanticHighlightingConstants.DEFAULT_MAX_INFERENCE_BATCH_SIZE;

    @With
    private final String validationError;

    /**
     * Check if the configuration is valid
     * @return true if no validation error exists
     */
    public boolean isValid() {
        return validationError == null;
    }

    /**
     * Create an invalid configuration with an error message
     * @param errorMessage the validation error message
     * @return invalid configuration
     */
    public static HighlightConfig invalid(String errorMessage) {
        return HighlightConfig.builder().fieldName("").modelId("").queryText("").validationError(errorMessage).build();
    }
}
