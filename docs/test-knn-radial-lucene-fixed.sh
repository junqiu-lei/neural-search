#!/bin/bash

echo "Testing k-NN radial search with Lucene engine..."

# Delete index if exists
curl -X DELETE "http://localhost:9200/test-knn-lucene" 2>/dev/null

# Create index with Lucene engine k-NN field and proper knn setting
echo -e "\n1. Creating index with Lucene k-NN field..."
curl -X PUT "http://localhost:9200/test-knn-lucene" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "index": {
        "number_of_shards": 2,
        "number_of_replicas": 1,
        "knn": true
      }
    },
    "mappings": {
      "properties": {
        "my_vector": {
          "type": "knn_vector",
          "dimension": 4,
          "space_type": "cosinesimil",
          "method": {
            "name": "hnsw",
            "engine": "lucene"
          }
        }
      }
    }
  }'

# Wait for index to be ready
sleep 2

# Add documents
echo -e "\n\n2. Adding documents..."
for i in {1..5}; do
  curl -X POST "http://localhost:9200/test-knn-lucene/_doc/$i" \
    -H 'Content-Type: application/json' \
    -d "{
      \"my_vector\": [$(shuf -i 1-10 -n 1).0, $(shuf -i 1-10 -n 1).0, $(shuf -i 1-10 -n 1).0, $(shuf -i 1-10 -n 1).0]
    }"
done

# Refresh index
sleep 2
curl -X POST "http://localhost:9200/test-knn-lucene/_refresh"

echo -e "\n\n3. Testing regular k-NN search (k=3) on node2..."
curl -X GET "http://localhost:9200/test-knn-lucene/_search?preference=_only_nodes:opensearch-node2" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 5,
    "query": {
      "knn": {
        "my_vector": {
          "vector": [5.0, 5.0, 5.0, 5.0],
          "k": 3
        }
      }
    }
  }' | jq '.'

echo -e "\n\n4. Testing radial search with min_score=0.8 on node2..."
curl -X GET "http://localhost:9200/test-knn-lucene/_search?preference=_only_nodes:opensearch-node2" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 5,
    "query": {
      "knn": {
        "my_vector": {
          "vector": [5.0, 5.0, 5.0, 5.0],
          "min_score": 0.8
        }
      }
    }
  }' | jq '.'

echo -e "\n\n5. Testing radial search with max_distance=0.5 on node2..."
curl -X GET "http://localhost:9200/test-knn-lucene/_search?preference=_only_nodes:opensearch-node2" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 5,
    "query": {
      "knn": {
        "my_vector": {
          "vector": [5.0, 5.0, 5.0, 5.0],
          "max_distance": 0.5
        }
      }
    }
  }' | jq '.'

echo -e "\n\nDone!"