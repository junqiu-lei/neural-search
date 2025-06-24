#!/bin/bash

MODEL_ID="B_wyipcB1J4KrYCjXcCQ"
echo "========================================="
echo "Testing Neural Search with Debug Logging"
echo "========================================="
echo

# Test 1: Regular k-NN neural search
echo "Test 1: Regular k-NN neural search (k=5)"
echo "------------------------------------------"
curl -s -X POST "http://localhost:9210/neural-radial-test/_search?preference=_prefer_nodes:opensearch-fix-node2" \
  -H "Content-Type: application/json" \
  -d "{
    \"query\": {
      \"neural\": {
        \"embedding\": {
          \"query_text\": \"search technology\",
          \"model_id\": \"$MODEL_ID\",
          \"k\": 5
        }
      }
    },
    \"size\": 3,
    \"_source\": [\"text\"]
  }" | jq '.hits.total.value' || echo "Failed"

echo
echo "Test 2: Radial search with min_score"  
echo "------------------------------------------"
curl -s -X POST "http://localhost:9210/neural-radial-test/_search?preference=_prefer_nodes:opensearch-fix-node2" \
  -H "Content-Type: application/json" \
  -d "{
    \"query\": {
      \"neural\": {
        \"embedding\": {
          \"query_text\": \"search technology\",
          \"model_id\": \"$MODEL_ID\",
          \"min_score\": 0.3
        }
      }
    },
    \"size\": 10,
    \"_source\": [\"text\"]
  }" | jq '.hits.total.value' || echo "Failed"

echo
echo "Test 3: Radial search with max_distance"
echo "------------------------------------------"
curl -s -X POST "http://localhost:9210/neural-radial-test/_search?preference=_prefer_nodes:opensearch-fix-node2" \
  -H "Content-Type: application/json" \
  -d "{
    \"query\": {
      \"neural\": {
        \"embedding\": {
          \"query_text\": \"search technology\",
          \"model_id\": \"$MODEL_ID\",
          \"max_distance\": 5.0
        }
      }
    },
    \"size\": 10,
    \"_source\": [\"text\"]
  }" | jq '.hits.total.value' || echo "Failed"

echo
echo "Now check the logs:"
echo "docker logs opensearch-fix-node1 2>&1 | grep DEBUG-NEURAL | tail -50"
echo "docker logs opensearch-fix-node2 2>&1 | grep DEBUG-NEURAL | tail -50"