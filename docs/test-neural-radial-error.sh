#!/bin/bash
set -e

echo "=== Testing Neural Search Radial Query Error ==="
echo ""

OPENSEARCH_HOST="localhost"
OPENSEARCH_PORT="9200"

# Check if model ID is set
if [ -z "$NEURAL_MODEL_ID" ]; then
  echo "ERROR: NEURAL_MODEL_ID is not set. Run setup-neural-docker.sh first."
  exit 1
fi

echo "Using Neural Model ID: $NEURAL_MODEL_ID"
echo ""

# Test 1: Regular neural search (should work)
echo "1. Testing regular neural search with k parameter (should work)..."
curl -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/neural-test/_search" \
  -H 'Content-Type: application/json' \
  -d "{
    \"query\": {
      \"neural\": {
        \"text_embedding\": {
          \"query_text\": \"machine learning algorithms\",
          \"model_id\": \"$NEURAL_MODEL_ID\",
          \"k\": 3
        }
      }
    }
  }" | jq '.hits.total.value'

echo -e "\n2. Testing neural search with min_score (radial search)..."
echo "This creates a NeuralKNNQueryBuilder with k=null and min_score=0.5"
curl -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/neural-test/_search" \
  -H 'Content-Type: application/json' \
  -d "{
    \"query\": {
      \"neural\": {
        \"text_embedding\": {
          \"query_text\": \"machine learning algorithms\",
          \"model_id\": \"$NEURAL_MODEL_ID\",
          \"min_score\": 0.5
        }
      }
    }
  }" | jq '.'

echo -e "\n3. Testing neural search with max_distance (radial search)..."
echo "This creates a NeuralKNNQueryBuilder with k=null and max_distance=5.0"
curl -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/neural-test/_search" \
  -H 'Content-Type: application/json' \
  -d "{
    \"query\": {
      \"neural\": {
        \"text_embedding\": {
          \"query_text\": \"machine learning algorithms\",
          \"model_id\": \"$NEURAL_MODEL_ID\",
          \"max_distance\": 5.0
        }
      }
    }
  }" | jq '.'

echo -e "\n4. CRITICAL TEST: Forcing cross-node communication with preference=_primary..."
echo "This should trigger the serialization error on main branch!"
curl -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/neural-test/_search?preference=_primary" \
  -H 'Content-Type: application/json' \
  -d "{
    \"query\": {
      \"neural\": {
        \"text_embedding\": {
          \"query_text\": \"machine learning algorithms\",
          \"model_id\": \"$NEURAL_MODEL_ID\",
          \"min_score\": 0.3
        }
      }
    }
  }"

echo -e "\n\n5. Checking logs for the error..."
docker logs opensearch-node1 2>&1 | grep -A10 -B10 "requires exactly one" | tail -30 || echo "No error found in node1"
docker logs opensearch-node2 2>&1 | grep -A10 -B10 "requires exactly one" | tail -30 || echo "No error found in node2"

echo -e "\nDone! If on main branch, you should see the error:"
echo "[knn] requires exactly one of k, distance or score to be set"