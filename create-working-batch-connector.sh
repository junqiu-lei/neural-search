#!/bin/bash
# Script to create a working test remote connector for batch highlighting model

OPENSEARCH_HOST="localhost"
OPENSEARCH_PORT="9200"

# Create a test connector with credentials
echo "Creating test batch highlighting connector..."

CONNECTOR_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/connectors/_create" \
  -H 'Content-Type: application/json' \
  -d '{
  "name": "Test Batch Highlighting Connector",
  "description": "Test connector for batch sentence highlighting",
  "version": "1",
  "protocol": "http",
  "parameters": {
    "endpoint": "https://httpbin.org/post"
  },
  "credential": {
    "key": "test-key"
  },
  "actions": [
    {
      "action_type": "predict",
      "method": "POST",
      "url": "${parameters.endpoint}",
      "headers": {
        "Content-Type": "application/json"
      },
      "request_body": "{ \"inputs\": \"test\" }",
      "post_process_function": "def result = [\"highlights\": [[\"start\": 10, \"end\": 25], [\"start\": 40, \"end\": 60]]]; return result;"
    }
  ]
}')

# Extract connector ID
CONNECTOR_ID=$(echo $CONNECTOR_RESPONSE | grep -o '"connector_id":"[^"]*' | cut -d'"' -f4)

if [ -z "$CONNECTOR_ID" ]; then
  echo "Failed to create connector. Response:"
  echo $CONNECTOR_RESPONSE | jq '.'
  exit 1
fi

echo "Connector created successfully with ID: $CONNECTOR_ID"
echo $CONNECTOR_ID > connector_id.txt
echo ""

# Now register a model using this connector
echo "Registering and deploying test batch highlighting model..."

MODEL_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/_register?deploy=true" \
  -H 'Content-Type: application/json' \
  -d "{
  \"name\": \"Test Batch Highlighting Model\",
  \"function_name\": \"remote\",
  \"connector_id\": \"${CONNECTOR_ID}\"
}")

TASK_ID=$(echo $MODEL_RESPONSE | grep -o '"task_id":"[^"]*' | cut -d'"' -f4)

if [ -z "$TASK_ID" ]; then
  echo "Failed to register model. Response:"
  echo $MODEL_RESPONSE | jq '.'
  exit 1
fi

echo "Model registration and deployment task ID: $TASK_ID"
echo ""

# Wait for model registration and deployment
echo "Waiting for model to be ready..."
for i in {1..30}; do
  sleep 2
  TASK_RESPONSE=$(curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/tasks/${TASK_ID}")
  TASK_STATE=$(echo $TASK_RESPONSE | grep -o '"state":"[^"]*' | cut -d'"' -f4)
  
  if [ "$TASK_STATE" = "COMPLETED" ]; then
    MODEL_ID=$(echo $TASK_RESPONSE | grep -o '"model_id":"[^"]*' | cut -d'"' -f4)
    echo "Model deployed successfully with ID: $MODEL_ID"
    echo $MODEL_ID > model_id.txt
    break
  elif [ "$TASK_STATE" = "FAILED" ]; then
    echo "Model deployment failed. Task response:"
    echo $TASK_RESPONSE | jq '.'
    exit 1
  fi
  
  if [ $i -eq 30 ]; then
    echo "Timeout waiting for model deployment. Last state: $TASK_STATE"
    echo $TASK_RESPONSE | jq '.'
    exit 1
  fi
done

echo ""
echo "Testing the model with _predict API..."
echo ""

# Test the model
TEST_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/${MODEL_ID}/_predict" \
  -H 'Content-Type: application/json' \
  -d '{
  "parameters": {
    "question": "What is machine learning?",
    "context": "Machine learning is a type of artificial intelligence that enables computers to learn from data and make predictions without being explicitly programmed."
  }
}')

echo "Test response:"
echo $TEST_RESPONSE | jq '.'

echo ""
echo "Summary:"
echo "--------"
echo "Connector ID: $CONNECTOR_ID"
echo "Model ID: $MODEL_ID"
echo ""
echo "Use this model ID for testing semantic highlighting with use_batch=true"