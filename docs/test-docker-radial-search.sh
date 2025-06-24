#!/bin/bash

echo "========================================="
echo "Testing Radial Search with Docker Cluster"
echo "========================================="
echo

# Wait for model to be deployed if needed
sleep 5

# Test basic neural query first
echo "Testing basic neural query:"
curl -s -X POST "http://localhost:9210/neural-radial-test/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "neural": {
        "embedding": {
          "query_text": "search technology",
          "model_id": "MCaeiZcBiaXMXiJfstTH",
          "k": 5
        }
      }
    },
    "size": 10,
    "_source": ["text"]
  }' | jq '.hits.hits[] | {score: ._score, text: ._source.text}' || echo "Failed"

echo
echo "----------------------------------------"
echo "Testing radial search (min_score) on node1:"
curl -s -X POST "http://localhost:9210/neural-radial-test/_search?preference=_prefer_nodes:opensearch-fix-node1" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "neural": {
        "embedding": {
          "query_text": "search technology",
          "model_id": "MCaeiZcBiaXMXiJfstTH",
          "min_score": 0.3
        }
      }
    },
    "size": 10,
    "_source": ["text"]
  }' | jq '.' || echo "Failed"

echo
echo "----------------------------------------"
echo "Testing radial search (min_score) on node2:"
curl -s -X POST "http://localhost:9210/neural-radial-test/_search?preference=_prefer_nodes:opensearch-fix-node2" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "neural": {
        "embedding": {
          "query_text": "search technology",
          "model_id": "MCaeiZcBiaXMXiJfstTH",
          "min_score": 0.3
        }
      }
    },
    "size": 10,
    "_source": ["text"]
  }' | jq '.' || echo "Failed"

echo
echo "========================================="
echo "Test completed"
echo "========================================="