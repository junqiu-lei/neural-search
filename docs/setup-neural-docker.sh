#!/bin/bash
set -e

echo "=== Setting up Neural Search with Local Models in Docker ==="
echo "This will configure ML Commons and deploy a local text embedding model"
echo ""

OPENSEARCH_HOST="localhost"
OPENSEARCH_PORT="9200"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Step 1: Configure ML Commons settings
echo -e "${GREEN}Step 1: Configuring ML Commons settings${NC}"
curl -s -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "persistent": {
      "plugins.ml_commons.only_run_on_ml_node": false,
      "plugins.ml_commons.native_memory_threshold": 99,
      "plugins.ml_commons.model_access_control_enabled": false,
      "plugins.ml_commons.allow_registering_model_via_url": true
    }
  }' | jq '.'

# Step 2: Create model group
echo -e "\n${GREEN}Step 2: Creating model group${NC}"
MODEL_GROUP_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/model_groups/_register" \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "neural_search_model_group",
    "description": "Model group for neural search testing"
  }')

MODEL_GROUP_ID=$(echo "$MODEL_GROUP_RESPONSE" | jq -r '.model_group_id')
echo "Model Group ID: $MODEL_GROUP_ID"

# Step 3: Register and deploy text embedding model
echo -e "\n${GREEN}Step 3: Registering text embedding model${NC}"
REGISTER_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/_register" \
  -H 'Content-Type: application/json' \
  -d "{
    \"name\": \"huggingface/sentence-transformers/all-MiniLM-L6-v2\",
    \"version\": \"1.0.1\",
    \"model_group_id\": \"$MODEL_GROUP_ID\",
    \"model_format\": \"TORCH_SCRIPT\"
  }")

TASK_ID=$(echo "$REGISTER_RESPONSE" | jq -r '.task_id')
echo "Registration Task ID: $TASK_ID"

# Wait for model registration
echo -n "Waiting for model registration"
for i in {1..60}; do
  TASK_STATUS=$(curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/tasks/$TASK_ID")
  STATE=$(echo "$TASK_STATUS" | jq -r '.state')
  
  if [ "$STATE" = "COMPLETED" ]; then
    MODEL_ID=$(echo "$TASK_STATUS" | jq -r '.model_id')
    echo -e "\n${GREEN}Model registered successfully! Model ID: $MODEL_ID${NC}"
    break
  elif [ "$STATE" = "FAILED" ]; then
    echo -e "\n${RED}Model registration failed!${NC}"
    echo "$TASK_STATUS" | jq '.'
    exit 1
  fi
  
  echo -n "."
  sleep 2
done

# Step 4: Deploy the model
echo -e "\n${GREEN}Step 4: Deploying model${NC}"
DEPLOY_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/$MODEL_ID/_deploy")
echo "$DEPLOY_RESPONSE" | jq '.'

# Wait for deployment
echo -n "Waiting for model deployment"
for i in {1..60}; do
  MODEL_STATUS=$(curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/$MODEL_ID")
  MODEL_STATE=$(echo "$MODEL_STATUS" | jq -r '.model_state')
  
  if [ "$MODEL_STATE" = "DEPLOYED" ]; then
    echo -e "\n${GREEN}Model deployed successfully!${NC}"
    break
  elif [ "$MODEL_STATE" = "DEPLOY_FAILED" ]; then
    echo -e "\n${RED}Model deployment failed!${NC}"
    echo "$MODEL_STATUS" | jq '.'
    exit 1
  fi
  
  echo -n "."
  sleep 2
done

# Step 5: Create neural search index
echo -e "\n${GREEN}Step 5: Creating neural search index${NC}"
curl -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/neural-test" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "index": {
        "knn": true,
        "number_of_shards": 2,
        "number_of_replicas": 0
      }
    },
    "mappings": {
      "properties": {
        "text": {
          "type": "text"
        },
        "text_embedding": {
          "type": "knn_vector",
          "dimension": 384,
          "method": {
            "engine": "lucene",
            "space_type": "l2",
            "name": "hnsw",
            "parameters": {
              "ef_construction": 128,
              "m": 24
            }
          }
        }
      }
    }
  }' | jq '.'

# Step 6: Create ingest pipeline
echo -e "\n${GREEN}Step 6: Creating ingest pipeline${NC}"
curl -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_ingest/pipeline/text-embedding-pipeline" \
  -H 'Content-Type: application/json' \
  -d "{
    \"description\": \"Text embedding pipeline\",
    \"processors\": [
      {
        \"text_embedding\": {
          \"model_id\": \"$MODEL_ID\",
          \"field_map\": {
            \"text\": \"text_embedding\"
          }
        }
      }
    ]
  }" | jq '.'

# Step 7: Index test documents
echo -e "\n${GREEN}Step 7: Indexing test documents${NC}"
for i in {1..5}; do
  curl -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/neural-test/_doc/$i?pipeline=text-embedding-pipeline" \
    -H 'Content-Type: application/json' \
    -d "{
      \"text\": \"Machine learning document $i about neural networks and AI\"
    }"
done

# Refresh index
curl -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/neural-test/_refresh"

# Step 8: Check shard distribution
echo -e "\n${GREEN}Step 8: Checking shard distribution${NC}"
curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_cat/shards/neural-test?v"

# Save model ID for testing
echo -e "\n${GREEN}Setup complete!${NC}"
echo "Model ID: $MODEL_ID"
echo ""
echo "To test neural search with radial parameters, run:"
echo "export NEURAL_MODEL_ID=$MODEL_ID"
echo "./test-neural-radial-error.sh"