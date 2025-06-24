#!/bin/bash
set -e

echo "=== Reproducing Cross-Node Neural Query Issue ==="

# Wait for cluster
echo "Waiting for cluster..."
until curl -s http://localhost:9200/_cluster/health?wait_for_status=green &>/dev/null; do
    sleep 2
done

# Get the model ID from before (or deploy new one)
MODEL_ID="veKXhpcB_hM3Iv304qzf"

# Verify model exists
if ! curl -s "http://localhost:9200/_plugins/_ml/models/${MODEL_ID}" | grep -q "DEPLOYED"; then
    echo "Model not found or not deployed. Deploying new model..."
    # Deploy model logic here if needed
fi

echo -e "\nUsing model ID: $MODEL_ID"

# Check shard distribution
echo -e "\nShard distribution:"
curl -s "http://localhost:9200/_cat/shards/neural-radial-test?v"

echo -e "\n\n=== TEST 1: Query that hits only node1 (shard 0) ==="
echo "This should work because it doesn't require cross-node communication"
curl -s -X POST "http://localhost:9200/neural-radial-test/_search?preference=_shards:0" -H 'Content-Type: application/json' -d"{
  \"size\": 10,
  \"query\": {
    \"neural\": {
      \"text_embedding\": {
        \"query_text\": \"machine learning\",
        \"model_id\": \"${MODEL_ID}\",
        \"max_distance\": 2.0
      }
    }
  }
}" | jq '{status: "success", total_hits: .hits.total.value, shards_queried: ._shards}'

echo -e "\n\n=== TEST 2: Query that forces cross-node communication ==="
echo "This query will hit both shards, requiring serialization between nodes"
echo "If the fix isn't working, shard 1 (on node2) will fail"

RESPONSE=$(curl -s -X POST "http://localhost:9200/neural-radial-test/_search?preference=_primary" -H 'Content-Type: application/json' -d"{
  \"size\": 10,
  \"query\": {
    \"neural\": {
      \"text_embedding\": {
        \"query_text\": \"machine learning\",
        \"model_id\": \"${MODEL_ID}\",
        \"max_distance\": 2.0
      }
    }
  }
}")

# Check if there were shard failures
if echo "$RESPONSE" | jq -e '._shards.failures' > /dev/null 2>&1; then
    echo -e "\n❌ SHARD FAILURE DETECTED - Cross-node serialization issue!"
    echo "$RESPONSE" | jq '._shards'
    echo -e "\nError details:"
    echo "$RESPONSE" | jq '._shards.failures[]'
else
    echo -e "\n✅ SUCCESS - All shards responded correctly!"
    echo "$RESPONSE" | jq '{total_hits: .hits.total.value, successful_shards: ._shards.successful}'
fi

echo -e "\n\n=== Checking debug logs for serialization details ==="
echo "Node 1 (sender) logs:"
docker logs opensearch-node1 2>&1 | grep -i "NeuralKNNQueryBuilder.*doWriteTo\|KNN Query:" | tail -5

echo -e "\nNode 2 (receiver) logs:"
docker logs opensearch-node2 2>&1 | grep -i "NeuralKNNQueryBuilder.*StreamInput\|Final KNN Query:" | tail -5