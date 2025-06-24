#!/bin/bash

MODEL_ID="B_wyipcB1J4KrYCjXcCQ"
echo "========================================="
echo "Testing Neural Radial Search with Docker"
echo "========================================="
echo "Model ID: $MODEL_ID"
echo

# Test normal neural query first
echo "1. Testing normal neural query (k=5):"
curl -s -X POST "http://localhost:9210/neural-radial-test/_search" \
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
    \"size\": 10,
    \"_source\": [\"text\"]
  }" | jq '.hits.hits[] | {score: ._score, text: ._source.text}' 2>/dev/null || echo "Query failed"

echo
echo "----------------------------------------"
echo "2. Testing radial search with min_score on node1:"
curl -s -X POST "http://localhost:9210/neural-radial-test/_search?preference=_prefer_nodes:opensearch-fix-node1" \
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
  }" | jq '.'

echo
echo "----------------------------------------"
echo "3. Testing radial search with min_score on node2:"
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
  }" | jq '.'

echo
echo "========================================="