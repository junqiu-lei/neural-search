/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.highlight;

import lombok.extern.log4j.Log4j2;
import org.opensearch.index.mapper.MappedFieldType;
import org.opensearch.neuralsearch.stats.events.EventStatName;
import org.opensearch.neuralsearch.stats.events.EventStatsManager;
import org.opensearch.search.fetch.subphase.highlight.FieldHighlightContext;
import org.opensearch.search.fetch.subphase.highlight.HighlightField;
import org.opensearch.search.fetch.subphase.highlight.Highlighter;
import org.opensearch.core.common.text.Text;

import java.util.Map;

/**
 * Semantic highlighter that uses ML models to identify relevant text spans for highlighting
 */
@Log4j2
public class SemanticHighlighter implements Highlighter {
    public static final String NAME = "semantic";

    private SemanticHighlighterEngine semanticHighlighterEngine;

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
        if (semanticHighlighterEngine == null) {
            throw new IllegalStateException("SemanticHighlighter has not been initialized");
        }

        EventStatsManager.increment(EventStatName.SEMANTIC_HIGHLIGHTING_REQUEST_COUNT);

        // Extract field text
        String fieldText = semanticHighlighterEngine.getFieldText(fieldContext);

        // Get model ID and check batch mode
        Map<String, Object> options = fieldContext.field.fieldOptions().options();
        String modelId = semanticHighlighterEngine.getModelId(options);
        boolean useBatch = semanticHighlighterEngine.isUseBatch(options);

        // Try to extract query text
        String originalQueryText = semanticHighlighterEngine.extractOriginalQuery(fieldContext.query, fieldContext.fieldName);

        if (originalQueryText == null || originalQueryText.isEmpty()) {
            log.warn("No query text found for field {}", fieldContext.fieldName);
            return null;
        }

        // The pre- and post- tags are provided by the user or defaulted to <em> and </em>
        String[] preTags = fieldContext.field.fieldOptions().preTags();
        String[] postTags = fieldContext.field.fieldOptions().postTags();

        // Get highlighted text
        String highlightedResponse;
        if (useBatch) {
            // TODO: Batch processing requires collecting multiple documents before processing
            // For now, falling back to single document processing
            // True batch processing would require changes to the Highlighter interface
            // to process multiple fields at once
            log.debug("Batch mode is enabled but processing single document due to interface constraints");
            highlightedResponse = semanticHighlighterEngine.getHighlightedSentences(
                modelId,
                originalQueryText,
                fieldText,
                preTags[0],
                postTags[0]
            );
        } else {
            highlightedResponse = semanticHighlighterEngine.getHighlightedSentences(
                modelId,
                originalQueryText,
                fieldText,
                preTags[0],
                postTags[0]
            );
        }

        if (highlightedResponse == null || highlightedResponse.isEmpty()) {
            log.warn("No highlighted text found for field {}", fieldContext.fieldName);
            return null;
        }

        // Create highlight field
        Text[] fragments = new Text[] { new Text(highlightedResponse) };
        return new HighlightField(fieldContext.fieldName, fragments);
    }
}
