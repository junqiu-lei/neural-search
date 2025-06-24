#!/bin/bash

OPENSEARCH_HOST="localhost"
OPENSEARCH_PORT="9200"

echo "=== Deploying Semantic Highlighting Model ==="

# Step 1: Register the semantic highlighting model
echo "Registering semantic highlighting model..."
MODEL_REGISTER_RESPONSE=$(curl -s -XPOST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/_register" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "amazon/sentence-highlighting/opensearch-semantic-highlighter-v1",
    "version": "1.0.0",
    "model_format": "TORCH_SCRIPT",
    "function_name": "QUESTION_ANSWERING",
    "description": "This is a sentence highlighting model that selects top k sentences from passages with a cross-attention QA model with an option to highlight words, based on semantic relevance rather than lexical matching.",
    "model_content_hash_value": "0fe5b96517b87ff7e9c4ba3cf925ab19ff8db2bb23e0c993f50f5e09c8affa3c",
    "url": "https://artifacts.opensearch.org/models/ml-models/amazon/sentence-highlighting/opensearch-semantic-highlighter-v1/1.0.0/torch_script/opensearch-semantic-highlighter-v1-1.0.0-torch_script.zip",
    "deploy": false
  }')

echo "Model registration response:"
echo "$MODEL_REGISTER_RESPONSE" | jq '.'

# Extract model ID
MODEL_ID=$(echo "$MODEL_REGISTER_RESPONSE" | jq -r '.model_id')
if [ -z "$MODEL_ID" ] || [ "$MODEL_ID" = "null" ]; then
    echo "Failed to register model"
    exit 1
fi

echo "Model registered with ID: $MODEL_ID"

# Step 2: Wait for model to be registered
echo "Waiting for model to be fully registered..."
sleep 5

# Check model status
STATUS_RESPONSE=$(curl -s -XGET "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/${MODEL_ID}")
echo "Model status:"
echo "$STATUS_RESPONSE" | jq '.'

# Step 3: Deploy the model
echo "Deploying model..."
DEPLOY_RESPONSE=$(curl -s -XPOST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/${MODEL_ID}/_deploy")
echo "Deploy response:"
echo "$DEPLOY_RESPONSE" | jq '.'

# Step 4: Wait for deployment
echo "Waiting for model deployment..."
for i in {1..30}; do
    sleep 5
    STATUS=$(curl -s -XGET "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/${MODEL_ID}" | jq -r '.model_state')
    echo "Model state: $STATUS"
    if [ "$STATUS" = "DEPLOYED" ]; then
        echo "Model successfully deployed!"
        break
    elif [ "$STATUS" = "DEPLOY_FAILED" ]; then
        echo "Model deployment failed!"
        exit 1
    fi
done

# Step 5: Test the deployed model
echo "Testing semantic highlighting model..."
TEST_RESPONSE=$(curl -s -XPOST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/_predict/QUESTION_ANSWERING/${MODEL_ID}" \
  -H "Content-Type: application/json" \
  -d '{
    "inputs": [
      {
        "context": "Alzheimers disease is a progressive neurodegenerative disorder characterized by accumulation of amyloid-beta plaques and neurofibrillary tangles in the brain. Early symptoms include short-term memory impairment, followed by language difficulties, disorientation, and behavioral changes. While traditional treatments such as cholinesterase inhibitors and memantine provide modest symptomatic relief, they do not alter disease progression. Recent clinical trials investigating monoclonal antibodies targeting amyloid-beta, including aducanumab, lecanemab, and donanemab, have shown promise in reducing plaque burden and slowing cognitive decline.",
        "question": "What are the recent treatments for Alzheimers disease?"
      }
    ],
    "parameters": {
      "top_k_passages": 3,
      "top_k_words": 10,
      "highlight_words": true
    }
  }')

echo "Test response:"
echo "$TEST_RESPONSE" | jq '.'

echo "Model ID: $MODEL_ID"
echo "Save this model ID for creating semantic field type!"