#!/bin/bash
set -e

echo "=== Testing Neural Search with Radial Search Parameters Using Local Model ==="

# Configuration
OPENSEARCH_HOST="localhost"
OPENSEARCH_PORT="9200"
INDEX_NAME="neural-radial-test"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Wait for cluster to be ready
echo "Waiting for cluster to be green..."
until curl -s http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_cluster/health?wait_for_status=green &>/dev/null; do
    echo -n "."
    sleep 2
done
echo " Cluster is ready!"

# Check cluster health
echo -e "\n1. Cluster Health:"
curl -s http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_cluster/health | jq '.'

# Check installed plugins
echo -e "\n2. Checking neural-search plugin:"
curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_cat/plugins?v" | grep neural-search

# Configure cluster settings for ML
echo -e "\n3. Configuring cluster settings for ML:"
curl -s -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_cluster/settings" -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "plugins.ml_commons.allow_registering_model_via_url": "true",
    "plugins.ml_commons.only_run_on_ml_node": "false",
    "plugins.ml_commons.model_access_control_enabled": "true"
  }
}' | jq '.'

# Step 1: Register and deploy local text embedding model
echo -e "\n4. Registering and deploying local text embedding model..."
REGISTER_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/_register?deploy=true" -H 'Content-Type: application/json' -d'
{
  "name": "huggingface/sentence-transformers/all-MiniLM-L6-v2",
  "version": "1.0.2",
  "model_format": "TORCH_SCRIPT"
}')

echo "Register response: $REGISTER_RESPONSE"
TASK_ID=$(echo $REGISTER_RESPONSE | jq -r '.task_id')
echo "Task ID: $TASK_ID"

# Wait for model deployment
echo -n "Waiting for model deployment"
for i in {1..30}; do
    sleep 5
    TASK_STATUS=$(curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/tasks/${TASK_ID}")
    STATE=$(echo $TASK_STATUS | jq -r '.state')
    
    if [ "$STATE" = "COMPLETED" ]; then
        MODEL_ID=$(echo $TASK_STATUS | jq -r '.model_id')
        echo " Done!"
        echo -e "${GREEN}Model deployed successfully with ID: ${MODEL_ID}${NC}"
        break
    elif [ "$STATE" = "FAILED" ]; then
        echo -e "\n${RED}Model deployment failed!${NC}"
        echo "$TASK_STATUS" | jq '.'
        exit 1
    fi
    echo -n "."
done

# Wait for model to be fully deployed
echo -e "\n5. Waiting for model to be fully deployed..."
for i in {1..30}; do
    MODEL_STATUS=$(curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/${MODEL_ID}")
    MODEL_STATE=$(echo $MODEL_STATUS | jq -r '.model_state')
    
    if [ "$MODEL_STATE" = "DEPLOYED" ]; then
        echo -e "${GREEN}Model is fully deployed and ready!${NC}"
        break
    fi
    echo "Model state: $MODEL_STATE - waiting..."
    sleep 5
done

# Verify model is deployed
echo -e "\nVerifying final model status:"
curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/${MODEL_ID}" | jq '.model_state, .model_id'

# Create index with neural search mapping
echo -e "\n6. Creating index with neural search mapping:"
curl -X DELETE "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}" 2>/dev/null || true
curl -s -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}" -H 'Content-Type: application/json' -d'
{
  "settings": {
    "index.knn": true,
    "number_of_shards": 2,
    "number_of_replicas": 1
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
          "name": "hnsw",
          "space_type": "l2",
          "engine": "lucene"
        }
      }
    }
  }
}' | jq '.'

# Configure ingest pipeline
echo -e "\n7. Configuring ingest pipeline with model ID ${MODEL_ID}:"
curl -s -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_ingest/pipeline/neural-ingest-pipeline" -H 'Content-Type: application/json' -d"
{
  \"description\": \"A pipeline to generate text embeddings\",
  \"processors\": [
    {
      \"text_embedding\": {
        \"model_id\": \"${MODEL_ID}\",
        \"field_map\": {
          \"text\": \"text_embedding\"
        }
      }
    }
  ]
}" | jq '.'

# Set default pipeline for the index
curl -s -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_settings" -H 'Content-Type: application/json' -d'
{
  "index.default_pipeline": "neural-ingest-pipeline"
}' | jq '.'

# Index test documents
echo -e "\n8. Indexing test documents:"
curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_doc/1" -H 'Content-Type: application/json' -d'
{
  "text": "Machine learning is a subset of artificial intelligence that enables systems to learn from data."
}'

curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_doc/2" -H 'Content-Type: application/json' -d'
{
  "text": "Deep learning uses neural networks with multiple layers to process complex patterns."
}'

curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_doc/3" -H 'Content-Type: application/json' -d'
{
  "text": "Natural language processing helps computers understand and generate human language."
}'

curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_doc/4" -H 'Content-Type: application/json' -d'
{
  "text": "The weather forecast predicts sunny skies and warm temperatures for the weekend."
}'

# Refresh index
echo -e "\n"
curl -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_refresh"

# Test standard neural search with k parameter (should work)
echo -e "\n9. Testing standard neural search with k=2:"
curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_search" -H 'Content-Type: application/json' -d"
{
  \"size\": 10,
  \"query\": {
    \"neural\": {
      \"text_embedding\": {
        \"query_text\": \"artificial intelligence and machine learning\",
        \"model_id\": \"${MODEL_ID}\",
        \"k\": 2
      }
    }
  }
}" | jq '.hits.hits[] | {id: ._id, score: ._score, text: ._source.text}'

# Test radial search with min_score (THIS IS WHAT WE'RE FIXING)
echo -e "\n10. Testing radial search with min_score (SHOULD WORK WITHOUT ERRORS):"
curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_search" -H 'Content-Type: application/json' -d"
{
  \"size\": 10,
  \"query\": {
    \"neural\": {
      \"text_embedding\": {
        \"query_text\": \"artificial intelligence and machine learning\",
        \"model_id\": \"${MODEL_ID}\",
        \"min_score\": 0.5
      }
    }
  }
}" | jq '.hits.hits[] | {id: ._id, score: ._score, text: ._source.text}' || echo "Query failed - check error above"

# Test radial search with max_distance
echo -e "\n11. Testing radial search with max_distance:"
curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_search" -H 'Content-Type: application/json' -d"
{
  \"size\": 10,
  \"query\": {
    \"neural\": {
      \"text_embedding\": {
        \"query_text\": \"artificial intelligence and machine learning\",
        \"model_id\": \"${MODEL_ID}\",
        \"max_distance\": 1.0
      }
    }
  }
}" | jq '.hits.hits[] | {id: ._id, score: ._score, text: ._source.text}' || echo "Query failed - check error above"

# Check logs for the critical error
echo -e "\n12. Checking for '[knn] requires exactly one of k' errors in logs:"
echo "--- Node 1 ---"
docker logs opensearch-node1 2>&1 | grep -i "requires exactly one of k" | tail -5 || echo "No 'requires exactly one of k' errors found in node1!"
echo "--- Node 2 ---"
docker logs opensearch-node2 2>&1 | grep -i "requires exactly one of k" | tail -5 || echo "No 'requires exactly one of k' errors found in node2!"

# Check for debug logs from our fix
echo -e "\n13. Checking for debug logs from NeuralKNNQueryBuilder fix:"
echo "--- Node 1 ---"
docker logs opensearch-node1 2>&1 | grep -i "NeuralKNNQueryBuilder" | tail -10
echo "--- Node 2 ---"  
docker logs opensearch-node2 2>&1 | grep -i "NeuralKNNQueryBuilder" | tail -10

echo -e "\n=== Test Complete ==="
echo -e "\nSummary:"
echo "- If you see search results above without errors, the fix is working!"
echo "- If you see '[knn] requires exactly one of k' errors, the issue persists"
echo "- Check the debug logs to trace the parameter flow"