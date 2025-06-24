#!/bin/bash
set -e

echo "=== DEFINITIVE Multi-Node Neural Search Radial Query Test ==="
echo "This test will prove whether cross-node serialization is working"

# Wait for cluster
until curl -s http://localhost:9200/_cluster/health?wait_for_status=green &>/dev/null; do
    sleep 2
done

MODEL_ID="veKXhpcB_hM3Iv304qzf"

# Show cluster topology
echo -e "\n1. Cluster Topology:"
curl -s "http://localhost:9200/_cat/nodes?v"
echo -e "\n2. Shard Distribution for neural-radial-test:"
curl -s "http://localhost:9200/_cat/shards/neural-radial-test?v&h=index,shard,prirep,state,docs,store,ip,node"

# Clear logs first
echo -e "\n3. Clearing logs by restarting containers..."
docker-compose restart > /dev/null 2>&1
sleep 30

echo -e "\n4. Running Neural Query with Radial Search (min_score) across ALL shards"
echo "This will require cross-node communication"

# Run query that must hit all shards
RESULT=$(curl -s -X POST "http://localhost:9200/neural-radial-test/_search" -H 'Content-Type: application/json' -d"{
  \"size\": 10,
  \"explain\": true,
  \"query\": {
    \"neural\": {
      \"text_embedding\": {
        \"query_text\": \"machine learning algorithms\",
        \"model_id\": \"${MODEL_ID}\",
        \"min_score\": 0.3
      }
    }
  }
}")

# Check for errors
if echo "$RESULT" | grep -q "error"; then
    echo "❌ QUERY FAILED!"
    echo "$RESULT" | jq '.'
else
    echo "✅ QUERY SUCCEEDED!"
    # Show which shards responded
    echo "$RESULT" | jq '{
        total_hits: .hits.total.value,
        shards: ._shards,
        hits_from_shards: [.hits.hits[] | {id: ._id, shard: ._shard, node: ._node, score: ._score}]
    }'
fi

echo -e "\n5. Checking Logs for Cross-Node Communication:"
echo "=== Node 1 Logs (last 20 neural-related entries) ==="
docker logs opensearch-node1 2>&1 | grep -i "neural" | tail -20

echo -e "\n=== Node 2 Logs (last 20 neural-related entries) ==="
docker logs opensearch-node2 2>&1 | grep -i "neural" | tail -20

echo -e "\n6. Looking for any KNN errors in logs:"
docker logs opensearch-node1 2>&1 | grep -i "requires exactly one of k" || echo "✅ No KNN errors in node1"
docker logs opensearch-node2 2>&1 | grep -i "requires exactly one of k" || echo "✅ No KNN errors in node2"

echo -e "\n7. Final Verification - Running query with preference to force specific shard routing:"
# Force query to go through node2 (which would fail if serialization isn't working)
curl -s -X POST "http://localhost:9200/neural-radial-test/_search?preference=_node:opensearch-node2" -H 'Content-Type: application/json' -d"{
  \"size\": 1,
  \"query\": {
    \"neural\": {
      \"text_embedding\": {
        \"query_text\": \"machine learning\",
        \"model_id\": \"${MODEL_ID}\",
        \"max_distance\": 2.0
      }
    }
  }
}" | jq '{success: (.error == null), hits: .hits.total.value}'

echo -e "\n=== SUMMARY ==="
echo "If all queries succeeded without '[knn] requires exactly one of k' errors,"
echo "then the multi-node serialization fix is working correctly!"