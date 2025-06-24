#!/bin/bash

echo "Testing Neural Radial Search ONLY..."

MODEL_ID="P_BxipcB55oPuVKLXQq1"

echo -e "\n1. Testing neural radial search with min_score=0.7..."
curl -X GET "http://localhost:9200/test-neural-radial/_search?preference=_only_nodes:opensearch-node2" \
  -H 'Content-Type: application/json' \
  -d "{
    \"size\": 5,
    \"query\": {
      \"neural\": {
        \"embedding\": {
          \"query_text\": \"machine learning algorithms\",
          \"model_id\": \"$MODEL_ID\",
          \"min_score\": 0.7
        }
      }
    }
  }" | jq '.'

echo -e "\n\n2. Testing neural radial search with max_distance=0.3..."
curl -X GET "http://localhost:9200/test-neural-radial/_search?preference=_only_nodes:opensearch-node2" \
  -H 'Content-Type: application/json' \
  -d "{
    \"size\": 5,
    \"query\": {
      \"neural\": {
        \"embedding\": {
          \"query_text\": \"machine learning algorithms\",
          \"model_id\": \"$MODEL_ID\",
          \"max_distance\": 0.3
        }
      }
    }
  }" | jq '.'