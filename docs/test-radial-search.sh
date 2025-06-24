#!/bin/bash
set -e

echo "=== Testing Neural Search with Radial Search Parameters ==="

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

# Check installed plugins
echo -e "\n2. Installed Plugins:"
curl -s "http://localhost:9200/_cat/plugins?v"

# Create index with 2 shards to test multi-node behavior
echo -e "\n3. Creating test index with 2 shards:"
curl -X PUT "localhost:9200/test-radial-index" -H 'Content-Type: application/json' -d'{
  "settings": {
    "number_of_shards": 2,
    "number_of_replicas": 1,
    "index": {
      "knn": true,
      "knn.algo_param.ef_search": 100
    }
  },
  "mappings": {
    "properties": {
      "vector_field": {
        "type": "knn_vector",
        "dimension": 3,
        "method": {
          "name": "hnsw",
          "space_type": "l2",
          "engine": "lucene",
          "parameters": {
            "ef_construction": 128,
            "m": 24
          }
        }
      },
      "description": {
        "type": "text"
      }
    }
  }
}'

# Wait for index to be ready
sleep 2

# Index some documents
echo -e "\n\n4. Indexing test documents:"
for i in {1..5}; do
  curl -X POST "localhost:9200/test-radial-index/_doc/$i" -H 'Content-Type: application/json' -d"
  {
    \"vector_field\": [$(echo $i | awk '{print $1*0.1}'), $(echo $i | awk '{print $1*0.2}'), $(echo $i | awk '{print $1*0.3}')],
    \"description\": \"Document $i\"
  }"
  echo
done

# Refresh index
curl -X POST "localhost:9200/test-radial-index/_refresh"
echo -e "\n"

# Test radial search with min_score
echo -e "\n5. Testing radial search with min_score (should work without errors):"
curl -X POST "localhost:9200/test-radial-index/_search" -H 'Content-Type: application/json' -d'{
  "size": 10,
  "query": {
    "neural": {
      "vector_field": {
        "query_text": "test query",
        "model_id": "test-model",
        "min_score": 0.5
      }
    }
  }
}' | jq '.'

# Test radial search with max_distance
echo -e "\n6. Testing radial search with max_distance:"
curl -X POST "localhost:9200/test-radial-index/_search" -H 'Content-Type: application/json' -d'{
  "size": 10,
  "query": {
    "neural": {
      "vector_field": {
        "query_text": "test query",
        "model_id": "test-model",
        "max_distance": 1.0
      }
    }
  }
}' | jq '.'

# Check logs for debug information
echo -e "\n7. Checking logs for debug info (last 20 lines from each node):"
echo -e "\n--- Node 1 logs ---"
docker logs opensearch-node1 2>&1 | grep -i "neural" | tail -20 || echo "No neural-related logs found"

echo -e "\n--- Node 2 logs ---"
docker logs opensearch-node2 2>&1 | grep -i "neural" | tail -20 || echo "No neural-related logs found"

echo -e "\n=== Test Complete ==="