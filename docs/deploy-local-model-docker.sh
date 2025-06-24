#!/bin/bash

# Configuration
OPENSEARCH_HOST="localhost"
OPENSEARCH_PORT="9210"
INDEX_NAME="neural-radial-test"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Deploying Text Embedding Model for Neural Search"
echo "=========================================="

# Configure cluster settings
echo -e "\n${GREEN}Configuring cluster settings${NC}"
curl -s -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_cluster/settings" -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "plugins.ml_commons.allow_registering_model_via_url": "true",
    "plugins.ml_commons.only_run_on_ml_node": "false",
    "plugins.ml_commons.model_access_control_enabled": "true"
  }
}' | jq '.'

# Function to get model ID from task ID
get_model_id_from_task() {
    local task_id=$1
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local response=$(curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/tasks/${task_id}")
        local state=$(echo $response | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
        
        if [ "$state" = "COMPLETED" ]; then
            local model_id=$(echo $response | grep -o '"model_id":"[^"]*"' | cut -d'"' -f4 | tr -d '.')
            echo $model_id
            return 0
        elif [ "$state" = "FAILED" ]; then
            echo "Task failed: $response" >&2
            return 1
        fi
        
        echo -n "."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    echo -e "\nTask timed out after $max_attempts attempts" >&2
    return 1
}

# Register and deploy the text embedding model
echo -e "\n${GREEN}Registering and deploying text embedding model${NC}"
TEXT_EMBEDDING_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/_register?deploy=true" -H 'Content-Type: application/json' -d'
{
  "name": "huggingface/sentence-transformers/all-MiniLM-L6-v2",
  "version": "1.0.2",
  "model_format": "TORCH_SCRIPT"
}')

echo "Response: $TEXT_EMBEDDING_RESPONSE" | jq '.'

TEXT_EMBEDDING_TASK_ID=$(echo $TEXT_EMBEDDING_RESPONSE | grep -o '"task_id":"[^"]*"' | cut -d'"' -f4)
echo -e "${GREEN}Task ID: ${TEXT_EMBEDDING_TASK_ID}${NC}"

echo -n "Waiting for text embedding model deployment"
TEXT_EMBEDDING_MODEL_ID=$(get_model_id_from_task $TEXT_EMBEDDING_TASK_ID)
if [ $? -ne 0 ]; then
    echo -e "\n${RED}Failed to get text embedding model ID${NC}"
    exit 1
fi
echo " Done"

# Clean up the model ID by removing dots
TEXT_EMBEDDING_MODEL_ID=$(echo $TEXT_EMBEDDING_MODEL_ID | tr -d '.')
echo -e "${GREEN}Text Embedding Model ID: ${TEXT_EMBEDDING_MODEL_ID}${NC}"

# Wait for model to be fully ready
echo "Waiting for model to be fully deployed..."
sleep 15

# Check model status
echo -e "\n${GREEN}Checking model status${NC}"
curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/${TEXT_EMBEDDING_MODEL_ID}" | jq '.'

# Create test index with neural search
echo -e "\n${GREEN}Deleting existing test index if present${NC}"
curl -s -X DELETE "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}" | jq '.'

echo -e "\n${GREEN}Creating test index with neural search${NC}"
curl -s -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}" -H 'Content-Type: application/json' -d'
{
  "settings": {
    "number_of_shards": 2,
    "number_of_replicas": 1,
    "index.knn": true
  },
  "mappings": {
    "properties": {
      "text": {
        "type": "text"
      },
      "embedding": {
        "type": "knn_vector",
        "dimension": 384,
        "method": {
          "name": "hnsw",
          "space_type": "l2",
          "engine": "lucene"
        }
      }
    }
  }
}' | jq '.'

# Create ingest pipeline
echo -e "\n${GREEN}Creating ingest pipeline${NC}"
curl -s -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_ingest/pipeline/text-embedding-pipeline" -H 'Content-Type: application/json' -d"{
  \"description\": \"A pipeline to generate text embeddings\",
  \"processors\": [
    {
      \"text_embedding\": {
        \"model_id\": \"${TEXT_EMBEDDING_MODEL_ID}\",
        \"field_map\": {
          \"text\": \"embedding\"
        }
      }
    }
  ]
}" | jq '.'

# Index some test documents
echo -e "\n${GREEN}Indexing test documents${NC}"
docs=(
  "The quick brown fox jumps over the lazy dog"
  "Machine learning is transforming the world"
  "OpenSearch is a powerful search engine"
  "Neural networks enable semantic search capabilities"
  "Vector databases are essential for AI applications"
  "Natural language processing helps understand text"
  "Deep learning models require significant computing power"
  "Elasticsearch fork became OpenSearch"
  "Radial search finds all vectors within a distance"
  "K-NN search finds the nearest neighbors"
)

for i in "${!docs[@]}"; do
  echo "Indexing document $((i+1)): ${docs[$i]}"
  curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_doc/$((i+1))?pipeline=text-embedding-pipeline" \
    -H 'Content-Type: application/json' \
    -d"{\"text\": \"${docs[$i]}\"}" | jq '.result'
done

# Refresh index
echo -e "\n${GREEN}Refreshing index${NC}"
curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_refresh" | jq '.'

# Check shard distribution
echo -e "\n${GREEN}Checking shard distribution${NC}"
curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_cat/shards/${INDEX_NAME}?v"

echo -e "\n${GREEN}Model deployment completed!${NC}"
echo -e "Model ID: ${TEXT_EMBEDDING_MODEL_ID}"
echo -e "\nYou can now test neural search with:"
echo -e "export MODEL_ID=${TEXT_EMBEDDING_MODEL_ID}"