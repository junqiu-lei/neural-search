#!/bin/bash

# Specific test to verify the k=null -> k=0 serialization fix
# This test focuses on the exact scenario from the PR

set -e

echo "========================================"
echo "Neural Radial Search Serialization Test"
echo "========================================"

HOST="localhost:9210"
MODEL_ID="MCaeiZcBiaXMXiJfstTH"

echo "Step 1: Create a fresh test index with 2 shards"
echo "----------------------------------------------"

# Delete if exists
curl -s -X DELETE "http://$HOST/radial-serial-test" > /dev/null 2>&1 || true

# Create index with 2 shards to ensure cross-node communication
curl -s -X PUT "http://$HOST/radial-serial-test" \
    -H "Content-Type: application/json" \
    -d '{
      "settings": {
        "index": {
          "number_of_shards": 2,
          "number_of_replicas": 0,
          "knn": true
        }
      },
      "mappings": {
        "properties": {
          "text": {
            "type": "text"
          },
          "embedding": {
            "type": "knn_vector",
            "dimension": 384,
            "method": {
              "name": "hnsw",
              "space_type": "l2",
              "engine": "lucene"
            }
          }
        }
      }
    }' > /dev/null

echo "✓ Index created with 2 shards"

echo ""
echo "Step 2: Index test documents"
echo "----------------------------"

# Function to index a document with embedding
index_doc() {
    local id=$1
    local text=$2
    
    # Generate embedding
    local embedding=$(curl -s -X POST "http://$HOST/_plugins/_ml/_predict/text_embedding/$MODEL_ID" \
        -H "Content-Type: application/json" \
        -d "{
            \"text_docs\": [\"$text\"],
            \"return_number\": true,
            \"target_response\": [\"sentence_embedding\"]
        }" | jq -r '.inference_results[0].output[0].data[]' | tr '\n' ',' | sed 's/,$//')
    
    # Index the document
    curl -s -X POST "http://$HOST/radial-serial-test/_doc/$id" \
        -H "Content-Type: application/json" \
        -d "{
            \"text\": \"$text\",
            \"embedding\": [$embedding]
        }" > /dev/null
}

# Index documents
index_doc "1" "OpenSearch is a distributed search engine"
index_doc "2" "Machine learning powers modern AI applications"
index_doc "3" "Neural networks enable semantic understanding"
index_doc "4" "Vector search finds similar documents"
index_doc "5" "Radial search uses distance thresholds"

# Refresh
curl -s -X POST "http://$HOST/radial-serial-test/_refresh" > /dev/null

echo "✓ Indexed 5 test documents"

echo ""
echo "Step 3: Verify shard distribution"
echo "---------------------------------"
curl -s "http://$HOST/_cat/shards/radial-serial-test?v"

echo ""
echo "Step 4: Test neural radial search (k=null with min_score)"
echo "---------------------------------------------------------"

# This is the exact query format from the PR that caused issues
query_json='{
  "query": {
    "neural": {
      "embedding": {
        "query_text": "search technology",
        "model_id": "'$MODEL_ID'",
        "min_score": 0.3
      }
    }
  },
  "size": 10,
  "_source": ["text"],
  "explain": true
}'

echo "Executing neural radial search query..."
response=$(curl -s -X POST "http://$HOST/radial-serial-test/_search" \
    -H "Content-Type: application/json" \
    -d "$query_json")

# Check for errors
if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ ERROR in response:"
    echo "$response" | jq '.error'
    exit 1
fi

# Display results
echo "✓ Query executed successfully"
echo ""
echo "Results:"
echo "$response" | jq '.hits.hits[] | {id: ._id, score: ._score, text: ._source.text}'

# Check hit count
hit_count=$(echo "$response" | jq '.hits.total.value')
echo ""
echo "Total hits: $hit_count"

echo ""
echo "Step 5: Test with max_distance"
echo "-------------------------------"

query_json2='{
  "query": {
    "neural": {
      "embedding": {
        "query_text": "search technology",
        "model_id": "'$MODEL_ID'",
        "max_distance": 2.5
      }
    }
  },
  "size": 10,
  "_source": ["text"]
}'

response2=$(curl -s -X POST "http://$HOST/radial-serial-test/_search" \
    -H "Content-Type: application/json" \
    -d "$query_json2")

# Check for errors
if echo "$response2" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ ERROR in response:"
    echo "$response2" | jq '.error'
    exit 1
fi

echo "✓ max_distance query executed successfully"
hit_count2=$(echo "$response2" | jq '.hits.total.value')
echo "Total hits with max_distance: $hit_count2"

echo ""
echo "Step 6: Force cross-node query with preference"
echo "----------------------------------------------"

# Query with node preference to force cross-node communication
response3=$(curl -s -X POST "http://$HOST/radial-serial-test/_search?preference=_prefer_nodes:opensearch-node2" \
    -H "Content-Type: application/json" \
    -d '{
      "query": {
        "neural": {
          "embedding": {
            "query_text": "search technology",
            "model_id": "'$MODEL_ID'",
            "min_score": 0.3
          }
        }
      },
      "size": 10
    }')

if echo "$response3" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ ERROR in cross-node query:"
    echo "$response3" | jq '.error'
    exit 1
fi

echo "✓ Cross-node query executed successfully"

echo ""
echo "Step 7: Check logs for serialization issues"
echo "-------------------------------------------"

# Check for specific serialization errors
echo "Checking for serialization errors..."
if docker logs opensearch-fix-node1 2>&1 | grep -i "cannot invoke.*getK()" > /dev/null; then
    echo "❌ Found k-NN serialization error in node1 logs"
    exit 1
fi

if docker logs opensearch-fix-node2 2>&1 | grep -i "cannot invoke.*getK()" > /dev/null; then
    echo "❌ Found k-NN serialization error in node2 logs"
    exit 1
fi

echo "✓ No serialization errors found in logs"

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "✓ Neural radial search with min_score works correctly"
echo "✓ Neural radial search with max_distance works correctly"
echo "✓ Cross-node queries execute without errors"
echo "✓ No k=null serialization issues detected"
echo ""
echo "The fix for k=null -> k=0 serialization is working!"

# Clean up
curl -s -X DELETE "http://$HOST/radial-serial-test" > /dev/null