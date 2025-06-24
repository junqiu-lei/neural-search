/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.processor.highlight;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import lombok.experimental.SuperBuilder;
import org.opensearch.neuralsearch.processor.InferenceRequest;

import java.util.List;

/**
 * Implementation of InferenceRequest for batch sentence highlighting inference requests.
 * This class handles multiple question-context pairs for batch processing.
 *
 * @see InferenceRequest
 */
@SuperBuilder
@NoArgsConstructor
@Getter
@Setter
public class BatchHighlightingRequest extends InferenceRequest {
    /**
     * List of highlighting items to process in batch
     */
    private List<HighlightingItem> items;

    /**
     * Represents a single item in the batch highlighting request
     */
    @Builder
    @AllArgsConstructor
    @NoArgsConstructor
    @Getter
    @Setter
    public static class HighlightingItem {
        /**
         * Document ID for correlation in response
         */
        private String documentId;

        /**
         * The question to be answered from the context
         */
        private String question;

        /**
         * The context text in which to find the answer
         */
        private String context;
    }
}