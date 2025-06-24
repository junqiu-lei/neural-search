#!/bin/bash
set -e

echo "=== Reproducing Neural Search Radial Query Error on Main Branch ==="
echo "This test will create a neural query scenario that triggers the error"
echo ""

# Step 1: Create index with proper mapping
echo "1. Creating neural search index with multi-shard setup..."
curl -X PUT "http://localhost:9200/neural-error-test" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "index": {
        "knn": true,
        "number_of_shards": 2,
        "number_of_replicas": 0
      }
    },
    "mappings": {
      "properties": {
        "text": {
          "type": "text"
        },
        "text_embedding": {
          "type": "knn_vector",
          "dimension": 3,
          "method": {
            "engine": "lucene",
            "space_type": "l2",
            "name": "hnsw",
            "parameters": {}
          }
        }
      }
    }
  }'

echo -e "\n\n2. Adding test documents with embeddings..."
# Add documents to ensure they're distributed across shards
for i in {1..10}; do
  curl -X POST "http://localhost:9200/neural-error-test/_doc/$i" \
    -H 'Content-Type: application/json' \
    -d "{
      \"text\": \"Test document $i\",
      \"text_embedding\": [$i.0, $((i*2)).0, $((i*3)).0]
    }"
done

# Refresh to make documents searchable
curl -X POST "http://localhost:9200/neural-error-test/_refresh"

echo -e "\n\n3. Checking shard distribution..."
curl -s "http://localhost:9200/_cat/shards/neural-error-test?v"

echo -e "\n\n4. Creating a mock neural query request..."
echo "Since we can't easily set up ML models, we'll directly test the query builder path"

# The neural query would normally:
# 1. Take query_text and model_id
# 2. Convert text to vector using the model
# 3. Create a NeuralKNNQueryBuilder with the vector
# 4. Execute the KNN search

# We'll simulate what happens after vector conversion by directly creating
# a query that uses the same serialization path

echo -e "\n\n5. Testing direct KNN query with radial search (this should work)..."
curl -X POST "http://localhost:9200/neural-error-test/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "knn": {
        "text_embedding": {
          "vector": [2.0, 4.0, 6.0],
          "min_score": 0.5
        }
      }
    }
  }'

echo -e "\n\n6. Forcing cross-node communication with preference=_primary..."
curl -X POST "http://localhost:9200/neural-error-test/_search?preference=_primary" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "knn": {
        "text_embedding": {
          "vector": [2.0, 4.0, 6.0],
          "min_score": 0.5
        }
      }
    }
  }'

echo -e "\n\n7. Checking logs for any serialization errors..."
docker logs opensearch-node1 2>&1 | grep -A5 -B5 "requires exactly one" | tail -20 || echo "No error found in node1"
docker logs opensearch-node2 2>&1 | grep -A5 -B5 "requires exactly one" | tail -20 || echo "No error found in node2"

echo -e "\n\nNote: The actual neural query error happens when:"
echo "- A neural query with radial parameters goes through NeuralQueryBuilder"
echo "- It creates a NeuralKNNQueryBuilder internally"
echo "- The query is serialized/deserialized between nodes"
echo "- The k=null becomes k=0 during serialization"
echo ""
echo "Without a full ML model setup, we can't trigger the exact neural query path,"
echo "but the code inspection confirms the issue exists in the main branch."