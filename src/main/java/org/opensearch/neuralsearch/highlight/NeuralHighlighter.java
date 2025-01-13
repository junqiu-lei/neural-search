/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.highlight;

import lombok.extern.log4j.Log4j2;
import org.opensearch.OpenSearchException;
import org.opensearch.core.common.text.Text;
import org.opensearch.index.mapper.MappedFieldType;
import org.opensearch.neuralsearch.ml.MLCommonsClientAccessor;
import org.opensearch.search.fetch.subphase.highlight.FieldHighlightContext;
import org.opensearch.search.fetch.subphase.highlight.HighlightField;
import org.opensearch.search.fetch.subphase.highlight.Highlighter;
import org.opensearch.core.action.ActionListener;

import java.io.IOException;
import java.util.Map;
import java.util.List;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.concurrent.CompletableFuture;
import java.util.regex.Pattern;

/**
 * Neural highlighter that uses question-answering models to identify relevant text spans
 */
@Log4j2
public class NeuralHighlighter implements Highlighter {
    public static final String NAME = "neural";
    private static final String MODEL_ID_OPTION = "model";
    private static final String SCORE_THRESHOLD_OPTION = "score_threshold";
    private static final String MAX_SNIPPETS_OPTION = "max_snippets";
    private static final float DEFAULT_SCORE_THRESHOLD = 0.5f;
    private static final int DEFAULT_MAX_SNIPPETS = 2;
    private static final Pattern SENTENCE_BOUNDARY = Pattern.compile("[.!?]+\\s+");

    private static MLCommonsClientAccessor mlCommonsClient;

    @Override
    public boolean canHighlight(MappedFieldType fieldType) {
        return true; // Can highlight any text field
    }

    public static void initialize(MLCommonsClientAccessor mlClient) {
        NeuralHighlighter.mlCommonsClient = mlClient;
    }

    // initial

    @Override
    public HighlightField highlight(FieldHighlightContext fieldContext) throws IOException {
        try {
            // Get highlighting options
            Map<String, Object> options = fieldContext.field.fieldOptions().options();
            String modelId = getModelId(options);
            int maxSnippets = getMaxSnippets(options);

            // Get the field text and query
            String fieldText = getFieldText(fieldContext);
            String searchQuery = extractOriginalQuery(fieldContext.query.toString());

            if (fieldText.isEmpty()) {
                return null;
            }

            // Split text into sentences for processing
            List<String> sentences = splitIntoSentences(fieldText);
            if (sentences.isEmpty()) {
                return null;
            }

            // Process each sentence with the QA model and collect highlights
            List<Text> highlights = new ArrayList<>();
            for (String sentence : sentences) {
                CompletableFuture<Map<String, Object>> future = new CompletableFuture<>();

                // Make async inference call
                mlCommonsClient.inferenceQA(
                    modelId,
                    searchQuery,
                    sentence,
                    ActionListener.wrap(result -> future.complete(result), e -> future.completeExceptionally(e))
                );

                // Process model output
                Map<String, Object> result = future.get();
                if (result != null) {
                    Number[] labelsArray = (Number[]) result.get("labels");
                    List<Integer> labels = Arrays.stream(labelsArray).map(Number::intValue).collect(java.util.stream.Collectors.toList());
                    log.info("Sentence: {}", sentence);
                    log.info("Labels: {}", labels);

                    int expectedSpans = ((Number) result.get("num_spans")).intValue();
                    if (expectedSpans == 0) {
                        continue;  // Skip if no spans expected
                    }

                    String[] words = sentence.split("\\s+");
                    StringBuilder sentenceWithHighlights = new StringBuilder();
                    int labelIndex = 0;
                    boolean inSpan = false;
                    int spanCount = 0;

                    // Process each word and its corresponding label
                    for (int i = 0; i < words.length && labelIndex < labels.size(); i++) {
                        String word = words[i];

                        // Add space before word unless it's the first word
                        if (sentenceWithHighlights.length() > 0) {
                            sentenceWithHighlights.append(" ");
                        }

                        if (labelIndex < labels.size()) {
                            int label = labels.get(labelIndex);

                            if (label == 1) {  // Beginning of span
                                inSpan = true;
                                sentenceWithHighlights.append("<em>");
                            } else if (label == 0 && inSpan) {  // End of span
                                inSpan = false;
                                sentenceWithHighlights.append("</em>");
                            }
                            // label == 2 means continue the current span

                            sentenceWithHighlights.append(word);
                            labelIndex++;
                        }
                    }

                    // Close any open highlight span
                    if (inSpan) {
                        sentenceWithHighlights.append("</em>");
                    }

                    highlights.add(new Text(sentenceWithHighlights.toString()));

                    // Limit number of highlighted snippets
                    if (highlights.size() >= maxSnippets) {
                        break;
                    }
                }
            }

            if (highlights.isEmpty()) {
                return null;
            }

            return new HighlightField(fieldContext.fieldName, highlights.toArray(new Text[0]));

        } catch (Exception e) {
            log.error("Error during neural highlighting", e);
            throw new OpenSearchException("Failed to perform neural highlighting", e);
        }
    }

    private String getModelId(Map<String, Object> options) {
        Object modelId = options.get(MODEL_ID_OPTION);
        if (modelId == null) {
            throw new IllegalArgumentException("Model ID must be specified for neural highlighting");
        }
        return modelId.toString();
    }

    private float getScoreThreshold(Map<String, Object> options) {
        Object threshold = options.get(SCORE_THRESHOLD_OPTION);
        if (threshold == null) {
            return DEFAULT_SCORE_THRESHOLD;
        }
        return Float.parseFloat(threshold.toString());
    }

    private int getMaxSnippets(Map<String, Object> options) {
        Object maxSnippets = options.get(MAX_SNIPPETS_OPTION);
        if (maxSnippets == null) {
            return DEFAULT_MAX_SNIPPETS;
        }
        return Integer.parseInt(maxSnippets.toString());
    }

    private String getFieldText(FieldHighlightContext fieldContext) {
        Object value = fieldContext.hitContext.sourceLookup().extractValue(fieldContext.fieldName, null);
        return value != null ? value.toString() : "";
    }

    private List<String> splitIntoSentences(String text) {
        return Arrays.asList(SENTENCE_BOUNDARY.split(text.trim()));
    }

    private String formatHighlight(String text) {
        return "<em>" + text + "</em>";
    }

    private String extractOriginalQuery(String queryString) {
        // Remove any field prefixes like "field_name:" and combine the terms
        return queryString.replaceAll("\\w+:", "").replaceAll("\\s+", " ").trim();
    }

    private boolean isPunctuation(String token) {
        return token.length() == 1 && !Character.isLetterOrDigit(token.charAt(0)) && !Character.isWhitespace(token.charAt(0));
    }
}
