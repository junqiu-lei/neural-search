#!/bin/bash

echo "Testing Neural Radial Search with Debug Logging..."

# Ensure model is deployed (using the model we deployed earlier)
MODEL_ID="P_BxipcB55oPuVKLXQq1"

# Delete index if exists
curl -X DELETE "http://localhost:9200/test-neural-radial" 2>/dev/null

# Create index with neural search field
echo -e "\n1. Creating index with neural search field..."
curl -X PUT "http://localhost:9200/test-neural-radial" \
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
        "title": {
          "type": "text"
        },
        "embedding": {
          "type": "knn_vector",
          "dimension": 384,
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

# Create neural ingestion pipeline
echo -e "\n\n2. Creating neural ingestion pipeline..."
curl -X PUT "http://localhost:9200/_ingest/pipeline/neural-pipeline" \
  -H 'Content-Type: application/json' \
  -d "{
    \"description\": \"Neural search pipeline\",
    \"processors\": [
      {
        \"text_embedding\": {
          \"model_id\": \"$MODEL_ID\",
          \"field_map\": {
            \"title\": \"embedding\"
          }
        }
      }
    ]
  }"

# Add documents using the pipeline
echo -e "\n\n3. Adding documents with neural pipeline..."
curl -X POST "http://localhost:9200/test-neural-radial/_doc/1?pipeline=neural-pipeline" \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Machine learning fundamentals"
  }'

curl -X POST "http://localhost:9200/test-neural-radial/_doc/2?pipeline=neural-pipeline" \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Deep learning and neural networks"
  }'

curl -X POST "http://localhost:9200/test-neural-radial/_doc/3?pipeline=neural-pipeline" \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Natural language processing"
  }'

curl -X POST "http://localhost:9200/test-neural-radial/_doc/4?pipeline=neural-pipeline" \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Computer vision applications"
  }'

curl -X POST "http://localhost:9200/test-neural-radial/_doc/5?pipeline=neural-pipeline" \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Data science best practices"
  }'

# Refresh index
sleep 2
curl -X POST "http://localhost:9200/test-neural-radial/_refresh"

# Clear logs before tests
echo -e "\n\n4. Clearing previous logs..."
docker exec opensearch-debug-node1 bash -c "echo '' > /usr/share/opensearch/logs/opensearch-cluster.log"
docker exec opensearch-debug-node2 bash -c "echo '' > /usr/share/opensearch/logs/opensearch-cluster.log"

echo -e "\n\n5. Testing regular neural search (k=3) on node2..."
curl -X GET "http://localhost:9200/test-neural-radial/_search?preference=_only_nodes:opensearch-node2" \
  -H 'Content-Type: application/json' \
  -d "{
    \"size\": 5,
    \"query\": {
      \"neural\": {
        \"embedding\": {
          \"query_text\": \"machine learning algorithms\",
          \"model_id\": \"$MODEL_ID\",
          \"k\": 3
        }
      }
    }
  }" | jq '.'

# Wait for logs
sleep 1

echo -e "\n\n6. Testing neural radial search with min_score=0.7 on node2..."
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

# Wait for logs
sleep 1

echo -e "\n\n7. Testing neural radial search with max_distance=0.3 on node2..."
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

echo -e "\n\nDone! Now let's collect the logs..."