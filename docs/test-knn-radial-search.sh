#!/bin/bash

echo "========================================="
echo "Testing KNN Radial Search with Docker"
echo "========================================="
echo

# Create k-NN index with 2 shards
echo "Creating k-NN index..."
curl -s -X PUT "http://localhost:9210/knn-radial-test" \
  -H "Content-Type: application/json" \
  -d '{
    "settings": {
      "number_of_shards": 2,
      "number_of_replicas": 1,
      "index.knn": true
    },
    "mappings": {
      "properties": {
        "embedding": {
          "type": "knn_vector",
          "dimension": 4,
          "method": {
            "name": "hnsw",
            "space_type": "l2",
            "engine": "lucene"
          }
        },
        "text": {
          "type": "text"
        }
      }
    }
  }' | jq '.'

# Index some documents with embeddings
echo -e "\nIndexing documents..."
curl -s -X POST "http://localhost:9210/knn-radial-test/_doc/1" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Document 1",
    "embedding": [1.0, 0.0, 0.0, 0.0]
  }' | jq '.'

curl -s -X POST "http://localhost:9210/knn-radial-test/_doc/2" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Document 2", 
    "embedding": [0.9, 0.1, 0.0, 0.0]
  }' | jq '.'

curl -s -X POST "http://localhost:9210/knn-radial-test/_doc/3" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Document 3",
    "embedding": [0.5, 0.5, 0.0, 0.0]
  }' | jq '.'

curl -s -X POST "http://localhost:9210/knn-radial-test/_doc/4" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Document 4",
    "embedding": [0.0, 0.0, 1.0, 0.0]
  }' | jq '.'

# Refresh index
curl -s -X POST "http://localhost:9210/knn-radial-test/_refresh" | jq '.'

# Check shard distribution
echo -e "\nShard distribution:"
curl -s "http://localhost:9210/_cat/shards/knn-radial-test?v"

# Test normal k-NN query
echo -e "\n\nTesting normal k-NN query (k=2):"
curl -s -X POST "http://localhost:9210/knn-radial-test/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "knn": {
        "embedding": {
          "vector": [1.0, 0.0, 0.0, 0.0],
          "k": 2
        }
      }
    }
  }' | jq '.hits.hits[] | {id: ._id, score: ._score, text: ._source.text}'

# Test radial search with min_score (direct query to each node)
echo -e "\n\nTesting radial search with min_score on node1:"
curl -s -X POST "http://localhost:9210/knn-radial-test/_search?preference=_prefer_nodes:opensearch-fix-node1" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "knn": {
        "embedding": {
          "vector": [1.0, 0.0, 0.0, 0.0],
          "min_score": 0.7
        }
      }
    }
  }' | jq '.'

echo -e "\n\nTesting radial search with min_score on node2:"
curl -s -X POST "http://localhost:9210/knn-radial-test/_search?preference=_prefer_nodes:opensearch-fix-node2" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "knn": {
        "embedding": {
          "vector": [1.0, 0.0, 0.0, 0.0],
          "min_score": 0.7
        }
      }
    }
  }' | jq '.'

echo -e "\n========================================="