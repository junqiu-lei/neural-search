/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.highlight;

import lombok.extern.log4j.Log4j2;
import org.opensearch.index.mapper.MappedFieldType;
import org.opensearch.neuralsearch.stats.events.EventStatName;
import org.opensearch.neuralsearch.stats.events.EventStatsManager;
import org.opensearch.search.fetch.subphase.highlight.BatchHighlighter;
import org.opensearch.search.fetch.subphase.highlight.FieldHighlightContext;
import org.opensearch.search.fetch.subphase.highlight.HighlightField;
import org.opensearch.core.common.text.Text;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Semantic highlighter that uses ML models to identify relevant text spans for highlighting.
 * Implements BatchHighlighter to support efficient batch processing of multiple fields.
 */
@Log4j2
public class SemanticHighlighter implements BatchHighlighter {
    public static final String NAME = "semantic";

    private SemanticHighlighterEngine semanticHighlighterEngine;

    static {
        log.warn("!!!!!!!!!! SEMANTIC HIGHLIGHTER CLASS LOADED - BatchHighlighter interface implemented !!!!!!!!!");
    }

    public void initialize(SemanticHighlighterEngine semanticHighlighterEngine) {
        if (this.semanticHighlighterEngine != null) {
            throw new IllegalStateException(
                "SemanticHighlighterEngine has already been initialized. Multiple initializations are not permitted."
            );
        }
        this.semanticHighlighterEngine = semanticHighlighterEngine;
    }

    @Override
    public boolean canHighlight(MappedFieldType fieldType) {
        return true;
    }

    /**
     * Highlights a field using semantic highlighting
     *
     * @param fieldContext The field context containing the query and field information
     * @return The highlighted field or null if highlighting is not possible
     */
    @Override
    public HighlightField highlight(FieldHighlightContext fieldContext) {
        log.warn("!!!!!!!!!! SEMANTIC HIGHLIGHTER 'highlight' method CALLED !!!!!!!!!! for field {}", fieldContext.fieldName);
        if (semanticHighlighterEngine == null) {
            throw new IllegalStateException("SemanticHighlighter has not been initialized");
        }

        EventStatsManager.increment(EventStatName.SEMANTIC_HIGHLIGHTING_REQUEST_COUNT);

        // Extract field text
        String fieldText = semanticHighlighterEngine.getFieldText(fieldContext);

        // Get model ID
        String modelId = semanticHighlighterEngine.getModelId(fieldContext.field.fieldOptions().options());

        // Try to extract query text
        String originalQueryText = semanticHighlighterEngine.extractOriginalQuery(fieldContext.query, fieldContext.fieldName);

        if (originalQueryText == null || originalQueryText.isEmpty()) {
            log.warn("No query text found for field {}", fieldContext.fieldName);
            return null;
        }

        // The pre- and post- tags are provided by the user or defaulted to <em> and </em>
        String[] preTags = fieldContext.field.fieldOptions().preTags();
        String[] postTags = fieldContext.field.fieldOptions().postTags();

        // Get highlighted text - allow any exceptions from this call to propagate
        String highlightedResponse = semanticHighlighterEngine.getHighlightedSentences(
            modelId,
            originalQueryText,
            fieldText,
            preTags[0],
            postTags[0]
        );

        if (highlightedResponse == null || highlightedResponse.isEmpty()) {
            log.warn("No highlighted text found for field {}", fieldContext.fieldName);
            return null;
        }

        // Create highlight field
        Text[] fragments = new Text[] { new Text(highlightedResponse) };
        return new HighlightField(fieldContext.fieldName, fragments);
    }

    /**
     * Indicates that this highlighter supports batch highlighting for better performance
     */
    @Override
    public boolean supportsBatchHighlighting() {
        log.warn("!!!!!!!!!! SEMANTIC HIGHLIGHTER 'supportsBatchHighlighting' method CALLED - returning TRUE !!!!!!!!!");
        return true;
    }

    /**
     * Performs batch highlighting on multiple field contexts in a single ML request.
     * This is more efficient than individual highlight calls as it reduces ML model invocations.
     *
     * @param contexts List of field contexts to highlight
     * @return Map of field context to highlighted field
     * @throws IOException if an error occurs during highlighting
     */
    @Override
    public Map<FieldHighlightContext, HighlightField> batchHighlight(List<FieldHighlightContext> contexts) throws IOException {
        log.warn("!!!!!!!!!! SEMANTIC HIGHLIGHTER 'batchHighlight' method CALLED !!!!!!!!!!");

        if (semanticHighlighterEngine == null) {
            throw new IllegalStateException("SemanticHighlighter has not been initialized");
        }

        if (contexts == null || contexts.isEmpty()) {
            return new HashMap<>();
        }

        log.debug("Processing batch highlighting for {} contexts", contexts.size());
        // Increment stats for each context in the batch
        for (int i = 0; i < contexts.size(); i++) {
            EventStatsManager.increment(EventStatName.SEMANTIC_HIGHLIGHTING_REQUEST_COUNT);
        }

        Map<FieldHighlightContext, HighlightField> results = new HashMap<>();

        // Group contexts by model ID for efficient batch processing
        Map<String, List<FieldHighlightContext>> contextsByModel = new HashMap<>();
        for (FieldHighlightContext context : contexts) {
            String modelId = semanticHighlighterEngine.getModelId(context.field.fieldOptions().options());
            contextsByModel.computeIfAbsent(modelId, k -> new ArrayList<>()).add(context);
        }

        // Process each model's batch
        for (Map.Entry<String, List<FieldHighlightContext>> entry : contextsByModel.entrySet()) {
            String modelId = entry.getKey();
            List<FieldHighlightContext> modelContexts = entry.getValue();

            try {
                Map<FieldHighlightContext, HighlightField> batchResults = semanticHighlighterEngine.batchHighlight(modelId, modelContexts);
                results.putAll(batchResults);
            } catch (Exception e) {
                log.error("Error in batch highlighting for model {}: {}", modelId, e.getMessage(), e);
                // Return empty highlights for failed batch to avoid recursion
                // TODO: Implement proper fallback to single-document processing
                for (FieldHighlightContext context : modelContexts) {
                    results.put(context, new HighlightField(context.fieldName, new Text[0]));
                }
            }
        }

        log.debug("Batch highlighting completed, processed {} out of {} contexts", results.size(), contexts.size());

        return results;
    }
}
