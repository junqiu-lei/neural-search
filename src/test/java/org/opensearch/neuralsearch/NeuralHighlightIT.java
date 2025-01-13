/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch;

import org.junit.Before;
import org.opensearch.client.Request;
import org.opensearch.client.Response;
import org.opensearch.common.settings.Settings;
import org.opensearch.core.rest.RestStatus;
import org.opensearch.neuralsearch.test.OpenSearchSecureRestTestCase;

import java.io.IOException;
import java.util.List;
import java.util.Map;

import static org.opensearch.neuralsearch.TestUtils.toMap;

/**
 * Integration test for neural highlighting using QA models
 */
public class NeuralHighlightIT extends OpenSearchSecureRestTestCase {

    private static final String MODEL_GROUP_ID = "neural_highlight_test_group";
    private static final String MODEL_ID = "neural_highlight_test_model";
    private static final String INDEX_NAME = "neural_highlight_test_index";
    private static final String PIPELINE_NAME = "neural_highlight_test_pipeline";

    @Before
    public void setup() throws IOException {
        // Register model group
        Request createModelGroup = new Request("POST", "/_plugins/_ml/model_groups/" + MODEL_GROUP_ID);
        createModelGroup.setJsonEntity(
            "{\"name\": \"Neural Highlight Test Group\", \"description\": \"Test group for neural highlighting\"}"
        );
        Response response = client().performRequest(createModelGroup);
        assertEquals(RestStatus.OK.getStatus(), response.getStatusLine().getStatusCode());

        // Register QA model
        Request registerModel = new Request("POST", "/_plugins/_ml/models/" + MODEL_ID);
        String modelConfig = "{"
            + "\"name\": \"Neural Highlight Test Model\","
            + "\"version\": 1,"
            + "\"model_group_id\": \""
            + MODEL_GROUP_ID
            + "\","
            + "\"model_format\": \"TORCH_SCRIPT\","
            + "\"description\": \"RoBERTa base model fine-tuned on SQuAD2 for question answering\","
            + "\"function_name\": \"QUESTION_ANSWERING\""
            + "}";
        registerModel.setJsonEntity(modelConfig);
        response = client().performRequest(registerModel);
        assertEquals(RestStatus.OK.getStatus(), response.getStatusLine().getStatusCode());

        // Upload model file
        Request uploadModel = new Request("POST", "/_plugins/_ml/models/" + MODEL_ID + "/_upload");
        uploadModel.setJsonEntity(
            "{"
                + "\"url\": \"https://artifacts.opensearch.org/models/ml-models/huggingface/deepset/roberta-base-squad2/1.0.0/torch_script/deepset_roberta-base-squad2-1.0.0-torch_script.zip\","
                + "\"content_type\": \"application/zip\""
                + "}"
        );
        response = client().performRequest(uploadModel);
        assertEquals(RestStatus.OK.getStatus(), response.getStatusLine().getStatusCode());

        // Deploy model
        Request deployModel = new Request("POST", "/_plugins/_ml/models/" + MODEL_ID + "/_deploy");
        response = client().performRequest(deployModel);
        assertEquals(RestStatus.OK.getStatus(), response.getStatusLine().getStatusCode());

        // Wait for model deployment
        waitForModelDeployment();

        // Create test index
        createTestIndex();
    }

    private void waitForModelDeployment() throws IOException {
        // Wait up to 2 minutes for model deployment
        long endTime = System.currentTimeMillis() + 120_000;

        while (System.currentTimeMillis() < endTime) {
            Request getModel = new Request("GET", "/_plugins/_ml/models/" + MODEL_ID);
            Response response = client().performRequest(getModel);
            Map<String, Object> responseMap = toMap(response);

            @SuppressWarnings("unchecked")
            Map<String, Object> model = (Map<String, Object>) responseMap.get("model");
            String modelState = (String) model.get("model_state");

            if ("DEPLOYED".equals(modelState)) {
                return;
            }

            try {
                Thread.sleep(5000); // Wait 5 seconds before next check
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new IOException("Interrupted while waiting for model deployment", e);
            }
        }

        throw new IOException("Timeout waiting for model deployment");
    }

    private void createTestIndex() throws IOException {
        // Create index with text field
        Request createIndex = new Request("PUT", "/" + INDEX_NAME);
        String mapping = "{"
            + "\"settings\": {"
            + "  \"index\": {"
            + "    \"highlight\": {"
            + "      \"max_analyzed_offset\": 1000000"
            + "    }"
            + "  }"
            + "},"
            + "\"mappings\": {"
            + "  \"properties\": {"
            + "    \"content\": {"
            + "      \"type\": \"text\""
            + "    }"
            + "  }"
            + "}"
            + "}";
        createIndex.setJsonEntity(mapping);
        Response response = client().performRequest(createIndex);
        assertEquals(RestStatus.OK.getStatus(), response.getStatusLine().getStatusCode());

        // Index test document with sample text from highlight_model.py
        Request indexDoc = new Request("POST", "/" + INDEX_NAME + "/_doc/1");
        String document = "{"
            + "\"content\": \"The brain is composed of many important regions that work together to process information. The cerebral cortex is responsible for higher-level thinking and decision making. The hippocampus plays a crucial role in memory formation and spatial navigation. The amygdala is involved in processing emotions and fear responses. The cerebellum coordinates movement and balance. The brain stem regulates basic life functions like breathing and heart rate.\""
            + "}";
        indexDoc.setJsonEntity(document);
        response = client().performRequest(indexDoc);
        assertEquals(RestStatus.CREATED.getStatus(), response.getStatusLine().getStatusCode());

        // Refresh index
        Request refresh = new Request("POST", "/" + INDEX_NAME + "/_refresh");
        client().performRequest(refresh);
    }

    public void testNeuralHighlighting() throws IOException {
        // Search with neural highlighting using question from highlight_model.py
        Request searchRequest = new Request("GET", "/" + INDEX_NAME + "/_search");
        String query = "{"
            + "\"query\": {"
            + "  \"match\": {"
            + "    \"content\": \"What are the different regions of the brain and their functions?\""
            + "  }"
            + "},"
            + "\"highlight\": {"
            + "  \"fields\": {"
            + "    \"content\": {"
            + "      \"type\": \"neural\","
            + "      \"model\": \""
            + MODEL_ID
            + "\","
            + "      \"score_threshold\": 0.5,"
            + "      \"max_snippets\": 5"
            + "    }"
            + "  }"
            + "}"
            + "}";
        searchRequest.setJsonEntity(query);
        Response response = client().performRequest(searchRequest);
        assertEquals(RestStatus.OK.getStatus(), response.getStatusLine().getStatusCode());

        // Parse response
        Map<String, Object> responseMap = toMap(response);
        Map<String, Object> hits = (Map<String, Object>) responseMap.get("hits");
        Map<String, Object> firstHit = (Map<String, Object>) ((List<Object>) hits.get("hits")).get(0);
        Map<String, Object> highlight = (Map<String, Object>) firstHit.get("highlight");
        List<String> contentHighlights = (List<String>) highlight.get("content");

        // Verify highlights
        assertNotNull("Should have highlights", contentHighlights);
        assertFalse("Should have non-empty highlights", contentHighlights.isEmpty());

        // Check for specific brain region mentions in highlights
        boolean foundBrainRegions = contentHighlights.stream()
            .anyMatch(
                h -> h.contains("cerebral cortex")
                    || h.contains("hippocampus")
                    || h.contains("amygdala")
                    || h.contains("cerebellum")
                    || h.contains("brain stem")
            );
        assertTrue("Highlights should contain brain region descriptions", foundBrainRegions);
    }

    @Override
    protected Settings restClientSettings() {
        return Settings.builder()
            .put(super.restClientSettings())
            // Add any additional client settings if needed
            .build();
    }
}
