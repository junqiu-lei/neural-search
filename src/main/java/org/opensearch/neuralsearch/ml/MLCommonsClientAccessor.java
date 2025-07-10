/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.ml;

import static org.opensearch.neuralsearch.processor.TextImageEmbeddingProcessor.INPUT_IMAGE;
import static org.opensearch.neuralsearch.processor.TextImageEmbeddingProcessor.INPUT_TEXT;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Consumer;
import java.util.stream.Collectors;

import org.opensearch.core.action.ActionListener;
import org.opensearch.core.common.util.CollectionUtils;
import org.opensearch.ml.client.MachineLearningNodeClient;
import org.opensearch.ml.common.FunctionName;
import org.opensearch.ml.common.MLModel;
import org.opensearch.ml.common.dataset.MLInputDataset;
import org.opensearch.ml.common.dataset.TextDocsInputDataSet;
import org.opensearch.ml.common.dataset.TextSimilarityInputDataSet;
import org.opensearch.ml.common.dataset.remote.RemoteInferenceInputDataSet;
import org.opensearch.ml.common.input.MLInput;
import org.opensearch.ml.common.output.MLOutput;
import org.opensearch.ml.common.output.model.ModelResultFilter;
import org.opensearch.ml.common.output.model.ModelTensor;
import org.opensearch.ml.common.output.model.ModelTensorOutput;
import org.opensearch.ml.common.output.model.ModelTensors;
import org.opensearch.neuralsearch.processor.InferenceRequest;
import org.opensearch.neuralsearch.processor.MapInferenceRequest;
import org.opensearch.neuralsearch.processor.SimilarityInferenceRequest;
import org.opensearch.neuralsearch.processor.TextInferenceRequest;
import org.opensearch.neuralsearch.util.RetryUtil;
import org.opensearch.ml.common.dataset.QuestionAnsweringInputDataSet;
import org.opensearch.neuralsearch.processor.highlight.SentenceHighlightingRequest;

import lombok.NonNull;
import lombok.RequiredArgsConstructor;
import lombok.extern.log4j.Log4j2;

/**
 * This class will act as an abstraction on the MLCommons client for accessing the ML Capabilities
 */
@RequiredArgsConstructor
@Log4j2
public class MLCommonsClientAccessor {
    private final MachineLearningNodeClient mlClient;

    /**
     * Wrapper around {@link #inferenceSentences} that expected a single input text and produces a single floating
     * point vector as a response.
     *
     * @param modelId {@link String}
     * @param inputText {@link String}
     * @param listener {@link ActionListener} which will be called when prediction is completed or errored out
     */
    public void inferenceSentence(
        @NonNull final String modelId,
        @NonNull final String inputText,
        @NonNull final ActionListener<List<Number>> listener
    ) {

        inferenceSentences(
            TextInferenceRequest.builder().modelId(modelId).inputTexts(List.of(inputText)).build(),
            ActionListener.wrap(response -> {
                if (response.size() != 1) {
                    listener.onFailure(
                        new IllegalStateException(
                            "Unexpected number of vectors produced. Expected 1 vector to be returned, but got [" + response.size() + "]"
                        )
                    );
                    return;
                }

                listener.onResponse(response.getFirst());
            }, listener::onFailure)
        );
    }

    /**
     * Abstraction to call predict function of api of MLClient with provided targetResponse filters. It uses the
     * custom model provided as modelId and run the {@link FunctionName#TEXT_EMBEDDING}. The return will be sent
     * using the actionListener which will have a {@link List} of {@link List} of {@link Float} in the order of
     * inputText. We are not making this function generic enough to take any function or TaskType as currently we
     * need to run only TextEmbedding tasks only.
     *
     * @param inferenceRequest {@link InferenceRequest}
     * @param listener {@link ActionListener} which will be called when prediction is completed or errored out.
     */
    public void inferenceSentences(
        @NonNull final TextInferenceRequest inferenceRequest,
        @NonNull final ActionListener<List<List<Number>>> listener
    ) {
        retryableInferenceSentencesWithVectorResult(inferenceRequest, 0, listener);
    }

    public void inferenceSentencesWithMapResult(
        @NonNull final TextInferenceRequest inferenceRequest,
        @NonNull final ActionListener<List<Map<String, ?>>> listener
    ) {
        retryableInferenceSentencesWithMapResult(inferenceRequest, 0, listener);
    }

    /**
     * Abstraction to call predict function of api of MLClient with provided targetResponse filters. It uses the
     * custom model provided as modelId and run the {@link FunctionName#TEXT_EMBEDDING}. The return will be sent
     * using the actionListener which will have a list of floats in the order of inputText.
     *
     * @param inferenceRequest {@link InferenceRequest}
     * @param listener {@link ActionListener} which will be called when prediction is completed or errored out.
     */
    public void inferenceSentencesMap(@NonNull MapInferenceRequest inferenceRequest, @NonNull final ActionListener<List<Number>> listener) {
        retryableInferenceSentencesWithSingleVectorResult(inferenceRequest, 0, listener);
    }

    /**
     * Abstraction to call predict function of api of MLClient. It uses the custom model provided as modelId and the
     * {@link FunctionName#TEXT_SIMILARITY}. The return will be sent via actionListener as a list of floats representing
     * the similarity scores of the texts w.r.t. the query text, in the order of the input texts.
     *
     * @param inferenceRequest {@link InferenceRequest}
     * @param listener {@link ActionListener} receives the result of the inference
     */
    public void inferenceSimilarity(
        @NonNull SimilarityInferenceRequest inferenceRequest,
        @NonNull final ActionListener<List<Float>> listener
    ) {
        retryableInferenceSimilarityWithVectorResult(inferenceRequest, 0, listener);
    }

    private void retryableInferenceSentencesWithMapResult(
        final TextInferenceRequest inferenceRequest,
        final int retryTime,
        final ActionListener<List<Map<String, ?>>> listener
    ) {
        MLInput mlInput = createMLTextInput(null, inferenceRequest.getInputTexts());
        mlClient.predict(inferenceRequest.getModelId(), mlInput, ActionListener.wrap(mlOutput -> {
            final List<Map<String, ?>> result = buildMapResultFromResponse(mlOutput);
            listener.onResponse(result);
        },
            e -> RetryUtil.handleRetryOrFailure(
                e,
                retryTime,
                () -> retryableInferenceSentencesWithMapResult(inferenceRequest, retryTime + 1, listener),
                listener
            )
        ));
    }

    private void retryableInferenceSentencesWithVectorResult(
        final TextInferenceRequest inferenceRequest,
        final int retryTime,
        final ActionListener<List<List<Number>>> listener
    ) {
        MLInput mlInput = createMLTextInput(inferenceRequest.getTargetResponseFilters(), inferenceRequest.getInputTexts());
        mlClient.predict(inferenceRequest.getModelId(), mlInput, ActionListener.wrap(mlOutput -> {
            final List<List<Number>> vector = buildVectorFromResponse(mlOutput);
            listener.onResponse(vector);
        },
            e -> RetryUtil.handleRetryOrFailure(
                e,
                retryTime,
                () -> retryableInferenceSentencesWithVectorResult(inferenceRequest, retryTime + 1, listener),
                listener
            )
        ));
    }

    private void retryableInferenceSimilarityWithVectorResult(
        final SimilarityInferenceRequest inferenceRequest,
        final int retryTime,
        final ActionListener<List<Float>> listener
    ) {
        MLInput mlInput = createMLTextPairsInput(inferenceRequest.getQueryText(), inferenceRequest.getInputTexts());
        mlClient.predict(inferenceRequest.getModelId(), mlInput, ActionListener.wrap(mlOutput -> {
            final List<Float> scores = buildVectorFromResponse(mlOutput).stream()
                .map(v -> v.getFirst().floatValue())
                .collect(Collectors.toList());
            listener.onResponse(scores);
        },
            e -> RetryUtil.handleRetryOrFailure(
                e,
                retryTime,
                () -> retryableInferenceSimilarityWithVectorResult(inferenceRequest, retryTime + 1, listener),
                listener
            )
        ));
    }

    private MLInput createMLTextInput(final List<String> targetResponseFilters, List<String> inputText) {
        final ModelResultFilter modelResultFilter = new ModelResultFilter(false, true, targetResponseFilters, null);
        final MLInputDataset inputDataset = new TextDocsInputDataSet(inputText, modelResultFilter);
        return new MLInput(FunctionName.TEXT_EMBEDDING, null, inputDataset);
    }

    private MLInput createMLTextPairsInput(final String query, final List<String> inputText) {
        final MLInputDataset inputDataset = new TextSimilarityInputDataSet(query, inputText);
        return new MLInput(FunctionName.TEXT_SIMILARITY, null, inputDataset);
    }

    private <T extends Number> List<List<T>> buildVectorFromResponse(MLOutput mlOutput) {
        final List<List<T>> vector = new ArrayList<>();
        final ModelTensorOutput modelTensorOutput = (ModelTensorOutput) mlOutput;
        final List<ModelTensors> tensorOutputList = modelTensorOutput.getMlModelOutputs();
        for (final ModelTensors tensors : tensorOutputList) {
            final List<ModelTensor> tensorsList = tensors.getMlModelTensors();
            for (final ModelTensor tensor : tensorsList) {
                vector.add(Arrays.stream(tensor.getData()).map(value -> (T) value).collect(Collectors.toList()));
            }
        }
        return vector;
    }

    private List<Map<String, ?>> buildMapResultFromResponse(MLOutput mlOutput) {
        final ModelTensorOutput modelTensorOutput = (ModelTensorOutput) mlOutput;
        final List<ModelTensors> tensorOutputList = modelTensorOutput.getMlModelOutputs();
        if (CollectionUtils.isEmpty(tensorOutputList) || CollectionUtils.isEmpty(tensorOutputList.get(0).getMlModelTensors())) {
            throw new IllegalStateException(
                "Empty model result produced. Expected at least [1] tensor output and [1] model tensor, but got [0]"
            );
        }
        List<Map<String, ?>> resultMaps = new ArrayList<>();
        for (ModelTensors tensors : tensorOutputList) {
            List<ModelTensor> tensorList = tensors.getMlModelTensors();
            for (ModelTensor tensor : tensorList) {
                resultMaps.add(tensor.getDataAsMap());
            }
        }
        return resultMaps;
    }

    private <T extends Number> List<T> buildSingleVectorFromResponse(final MLOutput mlOutput) {
        final List<List<T>> vector = buildVectorFromResponse(mlOutput);
        return vector.isEmpty() ? new ArrayList<>() : vector.get(0);
    }

    private void retryableInferenceSentencesWithSingleVectorResult(
        final MapInferenceRequest inferenceRequest,
        final int retryTime,
        final ActionListener<List<Number>> listener
    ) {
        MLInput mlInput = createMLMultimodalInput(inferenceRequest.getTargetResponseFilters(), inferenceRequest.getInputObjects());
        mlClient.predict(inferenceRequest.getModelId(), mlInput, ActionListener.wrap(mlOutput -> {
            final List<Number> vector = buildSingleVectorFromResponse(mlOutput);
            log.debug("Inference Response for input sentence is : {} ", vector);
            listener.onResponse(vector);
        },
            e -> RetryUtil.handleRetryOrFailure(
                e,
                retryTime,
                () -> retryableInferenceSentencesWithSingleVectorResult(inferenceRequest, retryTime + 1, listener),
                listener
            )
        ));
    }

    /**
     * Process the highlighting output from ML model response.
     * Converts the model output into a list of maps containing highlighting information.
     */
    private List<Map<String, Object>> processHighlightingOutput(ModelTensorOutput modelTensorOutput) {
        List<Map<String, Object>> results = new ArrayList<>();

        try {
            final List<ModelTensors> tensorOutputList = modelTensorOutput.getMlModelOutputs();

            if (CollectionUtils.isEmpty(tensorOutputList)) {
                return results;
            }

            for (ModelTensors tensors : tensorOutputList) {
                List<ModelTensor> tensorsList = tensors.getMlModelTensors();

                if (CollectionUtils.isEmpty(tensorsList)) {
                    log.warn("No tensors in model output");
                    continue;
                }

                // Process each tensor in the output
                for (ModelTensor tensor : tensorsList) {
                    Map<String, ?> dataMap = tensor.getDataAsMap(); // it stored in "result" in string type
                    if (dataMap != null && !dataMap.isEmpty()) {
                        // Cast the map to Map<String, Object> - this is safe as we're only reading from it
                        @SuppressWarnings("unchecked")
                        Map<String, Object> typedDataMap = (Map<String, Object>) dataMap;
                        results.add(typedDataMap);
                    }
                }
            }

            // If no results were found, add an empty map to maintain consistent response format
            if (results.isEmpty()) {
                results.add(Collections.emptyMap());
            }

            return results;
        } catch (Exception e) {
            throw new IllegalStateException("Error processing sentence highlighting output", e);
        }
    }

    private MLInput createMLMultimodalInput(final List<String> targetResponseFilters, final Map<String, String> input) {
        List<String> inputText = new ArrayList<>();
        inputText.add(input.get(INPUT_TEXT));
        if (input.containsKey(INPUT_IMAGE)) {
            inputText.add(input.get(INPUT_IMAGE));
        }
        final ModelResultFilter modelResultFilter = new ModelResultFilter(false, true, targetResponseFilters, null);
        final MLInputDataset inputDataset = new TextDocsInputDataSet(inputText, modelResultFilter);
        return new MLInput(FunctionName.TEXT_EMBEDDING, null, inputDataset);
    }

    public void getModel(@NonNull final String modelId, @NonNull final ActionListener<MLModel> listener) {
        retryableGetModel(modelId, 0, listener);
    }

    /**
     * Get model info for multiple model ids. It will send multiple getModel requests to get the model info in parallel.
     * It will fail if any one of the get model request fail. Only return the success result if all model info is
     * successfully retrieved.
     * @param modelIds a set of model ids
     * @param onSuccess onSuccess consumer
     * @param onFailure onFailure consumer
     */
    public void getModels(
        @NonNull final Set<String> modelIds,
        @NonNull final Consumer<Map<String, MLModel>> onSuccess,
        @NonNull final Consumer<Exception> onFailure
    ) {
        if (modelIds.isEmpty()) {
            try {
                onSuccess.accept(Collections.emptyMap());
            } catch (Exception e) {
                onFailure.accept(e);
            }
            return;
        }

        final Map<String, MLModel> modelMap = new ConcurrentHashMap<>();
        final AtomicInteger counter = new AtomicInteger(modelIds.size());
        final AtomicBoolean hasError = new AtomicBoolean(false);
        final List<String> errors = Collections.synchronizedList(new ArrayList<>());

        for (String modelId : modelIds) {
            try {
                getModel(modelId, ActionListener.wrap(model -> {
                    modelMap.put(modelId, model);
                    if (counter.decrementAndGet() == 0) {
                        if (hasError.get()) {
                            onFailure.accept(new RuntimeException(String.join(";", errors)));
                        } else {
                            try {
                                onSuccess.accept(modelMap);
                            } catch (Exception e) {
                                onFailure.accept(e);
                            }
                        }
                    }
                }, e -> { handleGetModelException(hasError, errors, modelId, e, counter, onFailure); }));
            } catch (Exception e) {
                handleGetModelException(hasError, errors, modelId, e, counter, onFailure);
            }
        }

    }

    private void handleGetModelException(
        AtomicBoolean hasError,
        List<String> errors,
        String modelId,
        Exception e,
        AtomicInteger counter,
        @NonNull Consumer<Exception> onFailure
    ) {
        hasError.set(true);
        errors.add("Failed to fetch model [" + modelId + "]: " + e.getMessage());
        if (counter.decrementAndGet() == 0) {
            onFailure.accept(new RuntimeException(String.join(";", errors)));
        }
    }

    private void retryableGetModel(@NonNull final String modelId, final int retryTime, @NonNull final ActionListener<MLModel> listener) {
        mlClient.getModel(
            modelId,
            null,
            ActionListener.wrap(
                listener::onResponse,
                e -> RetryUtil.handleRetryOrFailure(e, retryTime, () -> retryableGetModel(modelId, retryTime + 1, listener), listener)
            )
        );
    }

    /**
     * Retryable method to perform sentence highlighting inference.
     * This method will retry up to 3 times if a retryable exception occurs.
     */
    private void retryableInferenceSentenceHighlighting(
        final SentenceHighlightingRequest inferenceRequest,
        final int retryTime,
        final ActionListener<List<Map<String, Object>>> listener
    ) {
        try {
            MLInputDataset inputDataset = new QuestionAnsweringInputDataSet(inferenceRequest.getQuestion(), inferenceRequest.getContext());
            MLInput mlInput = new MLInput(FunctionName.QUESTION_ANSWERING, null, inputDataset);

            mlClient.predict(inferenceRequest.getModelId(), mlInput, ActionListener.wrap(mlOutput -> {
                try {
                    List<Map<String, Object>> result = processHighlightingOutput((ModelTensorOutput) mlOutput);
                    listener.onResponse(result);
                } catch (Exception e) {
                    listener.onFailure(e);
                }
            },
                e -> RetryUtil.handleRetryOrFailure(
                    e,
                    retryTime,
                    () -> retryableInferenceSentenceHighlighting(inferenceRequest, retryTime + 1, listener),
                    listener
                )
            ));
        } catch (Exception e) {
            listener.onFailure(e);
        }
    }

    /**
     * Performs sentence highlighting inference using the provided model.
     * This method will highlight relevant sentences in the context based on the question.
     *
     * @param inferenceRequest the request containing the question and context for highlighting
     * @param listener the listener to be called with the highlighting results
     */
    public void inferenceSentenceHighlighting(
        @NonNull final SentenceHighlightingRequest inferenceRequest,
        @NonNull final ActionListener<List<Map<String, Object>>> listener
    ) {
        retryableInferenceSentenceHighlighting(inferenceRequest, 0, listener);
    }

    /**
     * This method will highlight relevant sentences in batch for multiple question-context pairs.
     * Processing multiple requests in batch is more efficient than individual inference calls.
     *
     * @param modelId the ID of the model to use for highlighting
     * @param batchRequests list of highlighting requests
     * @param listener the listener to be called with batch highlighting results
     */
    public void inferenceSentenceHighlightingBatch(
        @NonNull final String modelId,
        @NonNull final List<SentenceHighlightingRequest> batchRequests,
        @NonNull final ActionListener<List<List<Map<String, Object>>>> listener
    ) {
        if (batchRequests.isEmpty()) {
            listener.onResponse(Collections.emptyList());
            return;
        }

        // For batch processing, we need to create multiple QuestionAnsweringInputDataSet
        // First, try to use batch-aware approach with remote inference
        if (batchRequests.size() == 1) {
            // Single request - use standard QuestionAnsweringInputDataSet
            SentenceHighlightingRequest request = batchRequests.get(0);
            MLInputDataset inputDataset = new QuestionAnsweringInputDataSet(request.getQuestion(), request.getContext());
            MLInput mlInput = new MLInput(FunctionName.QUESTION_ANSWERING, null, inputDataset);

            // Execute single inference but return as batch format
            mlClient.predict(modelId, mlInput, ActionListener.wrap(mlOutput -> {
                List<Map<String, Object>> singleResult = processHighlightingOutput((ModelTensorOutput) mlOutput);
                List<List<Map<String, Object>>> batchResults = new ArrayList<>();
                batchResults.add(singleResult);
                listener.onResponse(batchResults);
            }, e -> {
                log.error("Failed to run batch sentence highlighting for model " + modelId, e);
                listener.onFailure(e);
            }));
            return;
        }

        // For multiple requests, we need to check if this is a remote model
        // First try to get model information to determine the best approach
        mlClient.getModel(modelId, null, ActionListener.wrap(model -> {
            FunctionName functionName = model.getAlgorithm();

            if (functionName == FunctionName.QUESTION_ANSWERING) {
                // Local QA model - must use individual inference for BWC
                log.debug("Model {} is local QUESTION_ANSWERING type, using individual inference", modelId);
                fallbackToIndividualInference(modelId, batchRequests, listener);
            } else if (functionName == FunctionName.REMOTE) {
                // Remote model - can use batch inference
                log.debug("Model {} is REMOTE type, attempting batch inference", modelId);
                executeBatchInferenceForRemoteModel(modelId, batchRequests, listener);
            } else {
                // Unknown model type - try batch with fallback
                log.warn("Model {} has unexpected function type: {}, trying batch with fallback", modelId, functionName);
                executeBatchInferenceForRemoteModel(modelId, batchRequests, listener);
            }
        }, e -> {
            // If we can't get model info, try batch with fallback
            log.warn("Failed to get model info for {}, trying batch inference with fallback", modelId, e);
            executeBatchInferenceForRemoteModel(modelId, batchRequests, listener);
        }));
    }

    /**
     * Parse the ML output for batch highlighting results
     */
    private List<List<Map<String, Object>>> parseBatchHighlightingOutput(MLOutput mlOutput) {
        List<List<Map<String, Object>>> results = new ArrayList<>();

        if (mlOutput instanceof ModelTensorOutput) {
            ModelTensorOutput modelTensorOutput = (ModelTensorOutput) mlOutput;
            List<ModelTensors> tensorsList = modelTensorOutput.getMlModelOutputs();

            for (ModelTensors tensors : tensorsList) {
                List<ModelTensor> mlModelTensors = tensors.getMlModelTensors();
                if (!mlModelTensors.isEmpty()) {
                    Map<String, ?> dataMap = mlModelTensors.get(0).getDataAsMap();
                    Object highlightsObj = dataMap.get("highlights");
                    if (highlightsObj instanceof List) {
                        @SuppressWarnings("unchecked")
                        List<?> highlightsList = (List<?>) highlightsObj;

                        // Check if this is a batch response (list of lists)
                        if (!highlightsList.isEmpty() && highlightsList.get(0) instanceof List) {
                            // This is a batch response - each element is a list of highlights for one document
                            for (Object docHighlights : highlightsList) {
                                if (docHighlights instanceof List) {
                                    @SuppressWarnings("unchecked")
                                    List<Map<String, Object>> highlights = (List<Map<String, Object>>) docHighlights;
                                    results.add(highlights);
                                }
                            }
                        } else {
                            // This is a single response - add it as is
                            @SuppressWarnings("unchecked")
                            List<Map<String, Object>> highlights = (List<Map<String, Object>>) highlightsObj;
                            results.add(highlights);
                        }
                    } else {
                        results.add(Collections.emptyList());
                    }
                }
            }
        }

        return results;
    }

    /**
     * Execute batch inference for remote models
     */
    private void executeBatchInferenceForRemoteModel(
        String modelId,
        List<SentenceHighlightingRequest> batchRequests,
        ActionListener<List<List<Map<String, Object>>>> listener
    ) {
        try {
            // For remote models, we use RemoteInferenceInputDataSet with proper parameters
            Map<String, String> parameters = new HashMap<>();

            // Build the inputs array for batch processing
            // Using proper JSON escaping
            StringBuilder inputsJson = new StringBuilder("[");
            for (int i = 0; i < batchRequests.size(); i++) {
                if (i > 0) inputsJson.append(",");
                SentenceHighlightingRequest request = batchRequests.get(i);

                // Properly escape JSON special characters
                String escapedQuestion = escapeJsonString(request.getQuestion());
                String escapedContext = escapeJsonString(request.getContext());

                inputsJson.append("{\"question\":\"")
                    .append(escapedQuestion)
                    .append("\",\"context\":\"")
                    .append(escapedContext)
                    .append("\"}");
            }
            inputsJson.append("]");

            // Pass the JSON string as a parameter
            parameters.put("inputs", inputsJson.toString());

            // Create RemoteInferenceInputDataSet
            RemoteInferenceInputDataSet inputDataset = new RemoteInferenceInputDataSet(parameters);
            MLInput mlInput = MLInput.builder().algorithm(FunctionName.REMOTE).inputDataset(inputDataset).build();

            // Execute batch inference
            mlClient.predict(modelId, mlInput, ActionListener.wrap(mlOutput -> {
                List<List<Map<String, Object>>> results = parseBatchHighlightingOutput(mlOutput);
                listener.onResponse(results);
            }, e -> {
                log.warn("Batch inference failed for remote model {}, falling back to individual inference", modelId, e);
                fallbackToIndividualInference(modelId, batchRequests, listener);
            }));
        } catch (Exception e) {
            log.error("Error preparing batch inference for model " + modelId, e);
            fallbackToIndividualInference(modelId, batchRequests, listener);
        }
    }

    /**
     * Fallback to individual inference when batch processing fails
     */
    private void fallbackToIndividualInference(
        String modelId,
        List<SentenceHighlightingRequest> batchRequests,
        ActionListener<List<List<Map<String, Object>>>> listener
    ) {
        List<List<Map<String, Object>>> results = new ArrayList<>();
        AtomicInteger completedRequests = new AtomicInteger(0);
        AtomicBoolean hasError = new AtomicBoolean(false);

        for (int i = 0; i < batchRequests.size(); i++) {
            results.add(new ArrayList<>());
        }

        for (int i = 0; i < batchRequests.size(); i++) {
            final int index = i;
            SentenceHighlightingRequest request = batchRequests.get(i);

            // Create individual inference request
            SentenceHighlightingRequest individualRequest = SentenceHighlightingRequest.builder()
                .modelId(modelId)
                .question(request.getQuestion())
                .context(request.getContext())
                .build();

            // Execute individual inference
            inferenceSentenceHighlighting(individualRequest, ActionListener.wrap(individualResult -> {
                synchronized (results) {
                    results.set(index, individualResult);
                    if (completedRequests.incrementAndGet() == batchRequests.size()) {
                        if (!hasError.get()) {
                            listener.onResponse(results);
                        }
                    }
                }
            }, individualError -> {
                synchronized (results) {
                    log.warn("Individual inference failed for request " + index + ", using empty result", individualError);
                    results.set(index, Collections.emptyList());
                    if (completedRequests.incrementAndGet() == batchRequests.size()) {
                        if (!hasError.get()) {
                            listener.onResponse(results);
                        }
                    }
                }
            }));
        }
    }

    /**
     * Escapes special characters in a string for JSON serialization
     *
     * @param input The string to escape
     * @return The escaped string
     */
    private String escapeJsonString(String input) {
        if (input == null) {
            return "";
        }

        StringBuilder result = new StringBuilder();
        for (char c : input.toCharArray()) {
            switch (c) {
                case '"':
                    result.append("\\\"");
                    break;
                case '\\':
                    result.append("\\\\");
                    break;
                case '\b':
                    result.append("\\b");
                    break;
                case '\f':
                    result.append("\\f");
                    break;
                case '\n':
                    result.append("\\n");
                    break;
                case '\r':
                    result.append("\\r");
                    break;
                case '\t':
                    result.append("\\t");
                    break;
                default:
                    if (c < 0x20 || c > 0x7E) {
                        // Escape non-printable characters
                        result.append(String.format(java.util.Locale.ROOT, "\\u%04x", (int) c));
                    } else {
                        result.append(c);
                    }
                    break;
            }
        }
        return result.toString();
    }
}
