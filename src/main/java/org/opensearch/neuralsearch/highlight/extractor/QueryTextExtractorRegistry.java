/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.highlight.extractor;

import org.apache.lucene.search.BooleanQuery;
import org.apache.lucene.search.Query;
import org.apache.lucene.search.TermQuery;
import org.opensearch.neuralsearch.query.NeuralKNNQuery;
import org.opensearch.neuralsearch.query.HybridQuery;

import lombok.extern.log4j.Log4j2;

import java.util.HashMap;
import java.util.Map;

/**
 * Registry for query text extractors that manages the extraction process
 */
@Log4j2
public class QueryTextExtractorRegistry {

    private final Map<Class<? extends Query>, QueryTextExtractor> extractors = new HashMap<>();

    /**
     * Creates a new registry with default extractors
     */
    public QueryTextExtractorRegistry() {
        initialize();
    }

    /**
     * Initializes the registry with default extractors
     */
    private void initialize() {
        register(NeuralKNNQuery.class, new NeuralQueryTextExtractor());
        register(TermQuery.class, new TermQueryTextExtractor());
        register(HybridQuery.class, new HybridQueryTextExtractor(this));

        // BooleanQueryTextExtractor needs a reference to this registry
        // so we need to register it after creating the registry instance
        register(BooleanQuery.class, new BooleanQueryTextExtractor(this));
    }

    /**
     * Registers an extractor for a specific query type
     *
     * @param queryClass The query class to register for
     * @param extractor The extractor to use for this query type
     */
    public <T extends Query> void register(Class<T> queryClass, QueryTextExtractor extractor) {
        extractors.put(queryClass, extractor);
    }

    /**
     * Extracts text from a query using the appropriate extractor
     *
     * @param query The query to extract text from
     * @param fieldName The name of the field being highlighted
     * @return The extracted query text
     */
    public String extractQueryText(Query query, String fieldName) {
        if (query == null) {
            log.warn("Cannot extract text from null query");
            return null;
        }

        // Log detailed information about the query for debugging
        log.warn("Query class: {}, Query toString: {}", query.getClass().getName(), query);
        log.warn(
            "Available extractors: {}",
            extractors.keySet().stream().map(Class::getName).collect(java.util.stream.Collectors.joining(", "))
        );

        Class<?> queryClass = query.getClass();
        QueryTextExtractor extractor;

        extractor = extractors.get(queryClass);

        if (extractor == null) {
            log.warn("No extractor found for query type: {}", queryClass.getName());
            // Log parent/interface hierarchy to help identify potential matches
            Class<?> superClass = queryClass.getSuperclass();
            log.warn("Parent class hierarchy: {}", getSuperClassHierarchy(queryClass));
            return null;
        }

        String extractedText = extractor.extractQueryText(query, fieldName);
        log.warn("Successfully extracted text using {} extractor: '{}'", extractor.getClass().getSimpleName(), extractedText);
        return extractedText;
    }

    /**
     * Helper method to get the hierarchy of superclasses for a given class
     */
    private String getSuperClassHierarchy(Class<?> clazz) {
        StringBuilder hierarchy = new StringBuilder();
        Class<?> current = clazz;
        while (current != null && !current.equals(Object.class)) {
            if (hierarchy.length() > 0) {
                hierarchy.append(" -> ");
            }
            hierarchy.append(current.getName());
            current = current.getSuperclass();
        }
        return hierarchy.toString();
    }
}
