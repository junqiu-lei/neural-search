#!/bin/bash
set -e

echo "=== Testing KNN with Radial Search Parameters ==="

# Wait for cluster to be ready
echo "Waiting for cluster to be green..."
until curl -s http://localhost:9200/_cluster/health?wait_for_status=green &>/dev/null; do
    echo -n "."
    sleep 2
done
echo " Cluster is ready!"

# Check cluster health
echo -e "\n1. Cluster Health:"
curl -s http://localhost:9200/_cluster/health | jq '.'

# Create index with knn enabled
echo -e "\n2. Creating test index with KNN enabled:"
curl -X PUT "localhost:9200/test-knn-radial" -H 'Content-Type: application/json' -d'{
  "settings": {
    "number_of_shards": 2,
    "number_of_replicas": 1,
    "index": {
      "knn": true
    }
  },
  "mappings": {
    "properties": {
      "my_vector": {
        "type": "knn_vector",
        "dimension": 3,
        "method": {
          "name": "hnsw",
          "space_type": "l2",
          "engine": "lucene"
        }
      },
      "title": {
        "type": "text"
      }
    }
  }
}'

# Wait for index to be ready
sleep 2

# Index some documents with vectors
echo -e "\n\n3. Indexing test documents with vectors:"
curl -X POST "localhost:9200/test-knn-radial/_doc/1" -H 'Content-Type: application/json' -d'{
  "my_vector": [0.1, 0.2, 0.3],
  "title": "Document 1"
}'

curl -X POST "localhost:9200/test-knn-radial/_doc/2" -H 'Content-Type: application/json' -d'{
  "my_vector": [0.2, 0.3, 0.4],
  "title": "Document 2"
}'

curl -X POST "localhost:9200/test-knn-radial/_doc/3" -H 'Content-Type: application/json' -d'{
  "my_vector": [0.3, 0.4, 0.5],
  "title": "Document 3"
}'

curl -X POST "localhost:9200/test-knn-radial/_doc/4" -H 'Content-Type: application/json' -d'{
  "my_vector": [0.9, 0.9, 0.9],
  "title": "Document 4 - Far away"
}'

# Refresh index
curl -X POST "localhost:9200/test-knn-radial/_refresh"
echo -e "\n"

# Test standard KNN search (with k parameter) - should work
echo -e "\n4. Testing standard KNN search with k=2:"
curl -X POST "localhost:9200/test-knn-radial/_search" -H 'Content-Type: application/json' -d'{
  "size": 10,
  "query": {
    "knn": {
      "my_vector": {
        "vector": [0.1, 0.2, 0.3],
        "k": 2
      }
    }
  }
}' | jq '.'

# Test radial search with min_score
echo -e "\n5. Testing radial search with min_score (THIS SHOULD WORK WITHOUT ERRORS):"
curl -X POST "localhost:9200/test-knn-radial/_search" -H 'Content-Type: application/json' -d'{
  "size": 10,
  "query": {
    "knn": {
      "my_vector": {
        "vector": [0.1, 0.2, 0.3],
        "min_score": 0.5
      }
    }
  }
}' | jq '.'

# Test radial search with max_distance
echo -e "\n6. Testing radial search with max_distance:"
curl -X POST "localhost:9200/test-knn-radial/_search" -H 'Content-Type: application/json' -d'{
  "size": 10,
  "query": {
    "knn": {
      "my_vector": {
        "vector": [0.1, 0.2, 0.3],
        "max_distance": 1.0
      }
    }
  }
}' | jq '.'

# Check logs for any errors
echo -e "\n7. Checking for any '[knn] requires exactly one of k' errors in logs:"
docker logs opensearch-node1 2>&1 | grep -i "requires exactly one of k" || echo "No 'requires exactly one of k' errors found in node1!"
docker logs opensearch-node2 2>&1 | grep -i "requires exactly one of k" || echo "No 'requires exactly one of k' errors found in node2!"

echo -e "\n=== Test Complete ==="