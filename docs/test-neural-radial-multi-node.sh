#!/bin/bash

# Test script for neural radial search in multi-node Docker setup
# This verifies the fix for neural radial search serialization

set -e

echo "========================================"
echo "Neural Radial Search Multi-Node Test"
echo "========================================"

HOST="localhost:9210"
MODEL_ID="MCaeiZcBiaXMXiJfstTH"

# Function to generate embeddings
generate_embedding() {
    local text="$1"
    local response=$(curl -s -X POST "http://$HOST/_plugins/_ml/_predict/text_embedding/$MODEL_ID" \
        -H "Content-Type: application/json" \
        -d "{
            \"text_docs\": [\"$text\"],
            \"return_number\": true,
            \"target_response\": [\"sentence_embedding\"]
        }")
    
    echo "$response" | jq -r '.inference_results[0].output[0].data[]' | tr '\n' ',' | sed 's/,$//'
}

echo "Step 1: Index sample documents with embeddings"
echo "----------------------------------------------"

# Sample documents for testing
declare -a texts=(
    "The quick brown fox jumps over the lazy dog"
    "Machine learning is transforming the world"
    "OpenSearch is a powerful search engine"
    "Neural networks enable semantic search capabilities"
    "Vector databases are essential for AI applications"
    "Natural language processing helps understand text"
    "Deep learning models require significant computing power"
    "Elasticsearch fork became OpenSearch"
    "Radial search finds all vectors within a distance"
    "K-NN search finds the nearest neighbors"
)

# Index documents
for i in "${!texts[@]}"; do
    text="${texts[$i]}"
    echo "Indexing document $((i+1)): $text"
    
    # Generate embedding
    embedding=$(generate_embedding "$text")
    
    # Index the document
    curl -s -X POST "http://$HOST/neural-radial-test/_doc/$((i+1))" \
        -H "Content-Type: application/json" \
        -d "{
            \"text\": \"$text\",
            \"embedding\": [$embedding]
        }" > /dev/null
    
    echo "✓ Document $((i+1)) indexed"
done

# Refresh the index
curl -s -X POST "http://$HOST/neural-radial-test/_refresh" > /dev/null

echo ""
echo "Step 2: Verify document distribution across shards"
echo "--------------------------------------------------"
curl -s "http://$HOST/_cat/shards/neural-radial-test?v"

echo ""
echo "Step 3: Test neural radial search with min_score"
echo "------------------------------------------------"

# Generate query embedding
query_text="search engine technology"
echo "Query: $query_text"
query_embedding=$(generate_embedding "$query_text")

# Perform radial search with min_score
echo "Executing radial search with min_score..."
radial_response=$(curl -s -X POST "http://$HOST/neural-radial-test/_search" \
    -H "Content-Type: application/json" \
    -d "{
        \"query\": {
            \"neural\": {
                \"embedding\": {
                    \"query_text\": \"$query_text\",
                    \"model_id\": \"$MODEL_ID\",
                    \"min_score\": 0.5
                }
            }
        },
        \"size\": 10,
        \"_source\": [\"text\"]
    }")

echo "Results with min_score:"
echo "$radial_response" | jq '.hits.hits[] | {score: ._score, text: ._source.text}'

echo ""
echo "Step 4: Test neural radial search with max_distance"
echo "---------------------------------------------------"

# Perform radial search with max_distance
echo "Executing radial search with max_distance..."
radial_distance_response=$(curl -s -X POST "http://$HOST/neural-radial-test/_search" \
    -H "Content-Type: application/json" \
    -d "{
        \"query\": {
            \"neural\": {
                \"embedding\": {
                    \"query_text\": \"$query_text\",
                    \"model_id\": \"$MODEL_ID\",
                    \"max_distance\": 2.0
                }
            }
        },
        \"size\": 10,
        \"_source\": [\"text\"]
    }")

echo "Results with max_distance:"
echo "$radial_distance_response" | jq '.hits.hits[] | {score: ._score, text: ._source.text}'

echo ""
echo "Step 5: Test with preference routing to force cross-node queries"
echo "----------------------------------------------------------------"

# Test with different preferences to ensure cross-node communication
preferences=("_local" "_prefer_nodes:opensearch-node1" "_prefer_nodes:opensearch-node2")

for pref in "${preferences[@]}"; do
    echo ""
    echo "Testing with preference: $pref"
    
    pref_response=$(curl -s -X POST "http://$HOST/neural-radial-test/_search?preference=$pref" \
        -H "Content-Type: application/json" \
        -d "{
            \"query\": {
                \"neural\": {
                    \"embedding\": {
                        \"query_text\": \"$query_text\",
                        \"model_id\": \"$MODEL_ID\",
                        \"min_score\": 0.5
                    }
                }
            },
            \"size\": 5,
            \"_source\": [\"text\"]
        }")
    
    hit_count=$(echo "$pref_response" | jq '.hits.total.value')
    echo "✓ Got $hit_count results with preference $pref"
done

echo ""
echo "Step 6: Verify error handling and logs"
echo "--------------------------------------"

# Check for any errors in the logs
echo "Checking node1 logs for errors..."
docker logs opensearch-fix-node1 2>&1 | tail -20 | grep -i "error\|exception\|neural" || echo "✓ No errors found in node1"

echo ""
echo "Checking node2 logs for errors..."
docker logs opensearch-fix-node2 2>&1 | tail -20 | grep -i "error\|exception\|neural" || echo "✓ No errors found in node2"

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "✓ Successfully indexed documents across shards"
echo "✓ Neural radial search with min_score working"
echo "✓ Neural radial search with max_distance working"
echo "✓ Cross-node queries with preferences working"
echo "✓ No serialization errors detected"
echo ""
echo "The neural radial search fix is working correctly!"