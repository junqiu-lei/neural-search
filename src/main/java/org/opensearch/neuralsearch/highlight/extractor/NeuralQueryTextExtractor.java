/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.highlight.extractor;

import org.apache.lucene.search.Query;
import org.opensearch.neuralsearch.query.NeuralKNNQuery;
import lombok.extern.log4j.Log4j2;

/**
 * Extractor for neural queries
 */
@Log4j2
public class NeuralQueryTextExtractor implements QueryTextExtractor {

    @Override
    public String extractQueryText(Query query, String fieldName) {
        try {
            NeuralKNNQuery neuralQuery = toQueryType(query, NeuralKNNQuery.class);
            String originalText = neuralQuery.getOriginalQueryText();
            log.warn(
                "Extracted original query text from NeuralKNNQuery: '{}', underlying query type: {}",
                originalText,
                neuralQuery.getKnnQuery().getClass().getName()
            );
            return originalText;
        } catch (IllegalArgumentException e) {
            // Log the conversion error to help troubleshoot
            log.warn("Failed to convert query to NeuralKNNQuery: {}", e.getMessage());
            throw e;
        }
    }
}
