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
        // Stub implementation: main inference work is performed by SemanticHighlightSubPhase
        // Still increment stat counters for visibility but return null immediately to skip default highlighting.
        EventStatsManager.increment(EventStatName.SEMANTIC_HIGHLIGHTING_REQUEST_COUNT);
        return null;
    }
}
