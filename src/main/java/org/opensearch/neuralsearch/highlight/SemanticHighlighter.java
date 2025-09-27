/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.highlight;

import lombok.extern.log4j.Log4j2;
import org.opensearch.cluster.service.ClusterService;
import org.opensearch.common.settings.Settings;
import org.opensearch.core.common.text.Text;
import org.opensearch.index.mapper.MappedFieldType;
import org.opensearch.neuralsearch.highlight.single.SemanticHighlighterEngine;
import org.opensearch.neuralsearch.highlight.utils.HighlightExtractorUtils;
import org.opensearch.neuralsearch.stats.events.EventStatName;
import org.opensearch.neuralsearch.stats.events.EventStatsManager;
import org.opensearch.search.fetch.subphase.highlight.FieldHighlightContext;
import org.opensearch.search.fetch.subphase.highlight.HighlightField;
import org.opensearch.search.fetch.subphase.highlight.Highlighter;
import org.opensearch.search.pipeline.SearchPipelineService;

import java.util.List;
import java.util.Map;

/**
 * Semantic highlighter that uses ML models to identify relevant text spans for highlighting
 */
@Log4j2
public class SemanticHighlighter implements Highlighter {
    public static final String NAME = "semantic";

    private SemanticHighlighterEngine semanticHighlighterEngine;
    private ClusterService clusterService;

    public void initialize(SemanticHighlighterEngine semanticHighlighterEngine) {
        if (this.semanticHighlighterEngine != null) {
            throw new IllegalStateException(
                "SemanticHighlighterEngine has already been initialized. Multiple initializations are not permitted."
            );
        }
        this.semanticHighlighterEngine = semanticHighlighterEngine;
    }

    public void setClusterService(ClusterService clusterService) {
        this.clusterService = clusterService;
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
        // Extract batch_inference option from field options
        Map<String, Object> options = fieldContext.field.fieldOptions().options();
        boolean batchInference = extractBatchInference(options);

        if (batchInference) {
            // Check if system processor is enabled
            if (!isSystemProcessorEnabled()) {
                throw new IllegalStateException(
                    "Batch inference for semantic highlighting requires enabling the system-generated processor. "
                        + "Please add the following to opensearch.yml:\n"
                        + "search.pipeline.enabled_system_generated_factories: [\"org.opensearch.neuralsearch.highlight.SemanticHighlightingProcessorFactory\"]"
                );
            }

            // Return null - actual highlighting will be done by SemanticHighlightingProcessor
            // This highlighter only serves to validate the system processor is enabled for batch mode
            return null;
        }

        // Below is the EXACT code from main branch without any changes
        if (semanticHighlighterEngine == null) {
            throw new IllegalStateException("SemanticHighlighter has not been initialized");
        }

        EventStatsManager.increment(EventStatName.SEMANTIC_HIGHLIGHTING_REQUEST_COUNT);

        // Extract field text
        String fieldText = HighlightExtractorUtils.getFieldText(fieldContext);

        // Get model ID
        String modelId = HighlightExtractorUtils.getModelId(fieldContext.field.fieldOptions().options());

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

    private boolean extractBatchInference(Map<String, Object> options) {
        // Use utility method, but need to create a mock highlighter
        // For now, keep the logic here since we only have field options, not full highlighter
        if (options != null && options.containsKey("batch_inference")) {
            Object value = options.get("batch_inference");
            if (value instanceof Boolean) {
                return (Boolean) value;
            } else if (value instanceof String) {
                return Boolean.parseBoolean((String) value);
            }
        }
        return false; // Default to false for backward compatibility
    }

    private boolean isSystemProcessorEnabled() {
        if (clusterService == null) {
            log.warn("ClusterService not available, cannot check system processor setting");
            return false;
        }

        Settings settings = clusterService.getSettings();
        List<String> enabledFactories = settings.getAsList(SearchPipelineService.ENABLED_SYSTEM_GENERATED_FACTORIES_SETTING.getKey());

        return enabledFactories != null && enabledFactories.contains(SemanticHighlightingConstants.SYSTEM_FACTORY_TYPE);
    }
}
