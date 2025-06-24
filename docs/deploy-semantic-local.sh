#!/bin/bash

OPENSEARCH_HOST="localhost"
OPENSEARCH_PORT="9200"

echo "=== Deploying Local Semantic Highlighting Model ==="

# Register and deploy the local semantic highlighting model
echo "Registering and deploying local semantic highlighting model..."
RESPONSE=$(curl -s -XPOST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/_register?deploy=true" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "amazon/sentence-highlighting/opensearch-semantic-highlighter-v1",
    "version": "1.0.0",
    "model_format": "TORCH_SCRIPT",
    "function_name": "QUESTION_ANSWERING",
    "model_content_hash_value": "0fe5b96517b87ff7e9c4ba3cf925ab19ff8db2bb23e0c993f50f5e09c8affa3c",
    "url": "https://artifacts.opensearch.org/models/ml-models/amazon/sentence-highlighting/opensearch-semantic-highlighter-v1/1.0.0/torch_script/opensearch-semantic-highlighter-v1-1.0.0-torch_script.zip"
  }')

echo "Response: $RESPONSE"

# Extract task ID
TASK_ID=$(echo "$RESPONSE" | jq -r '.task_id')
if [ -z "$TASK_ID" ] || [ "$TASK_ID" = "null" ]; then
    echo "Failed to register model"
    exit 1
fi

echo "Task ID: $TASK_ID"

# Wait for deployment
echo "Waiting for model deployment..."
for i in {1..60}; do
    sleep 5
    TASK_STATUS=$(curl -s -XGET "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/tasks/${TASK_ID}")
    STATE=$(echo "$TASK_STATUS" | jq -r '.state')
    echo "Task state: $STATE"
    
    if [ "$STATE" = "COMPLETED" ]; then
        MODEL_ID=$(echo "$TASK_STATUS" | jq -r '.model_id')
        echo "Model successfully deployed!"
        echo "Model ID: $MODEL_ID"
        break
    elif [ "$STATE" = "FAILED" ]; then
        echo "Model deployment failed!"
        echo "$TASK_STATUS" | jq '.'
        exit 1
    fi
done

echo "Model ID: $MODEL_ID"