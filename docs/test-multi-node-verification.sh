#!/bin/bash
set -e

echo "=== Verifying Multi-Node Query Distribution for Neural Search ==="

# Configuration
OPENSEARCH_HOST="localhost"
OPENSEARCH_PORT="9200"
INDEX_NAME="neural-radial-test"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "\n${GREEN}1. Cluster Information:${NC}"
echo "Nodes in cluster:"
curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_cat/nodes?v"

echo -e "\n${GREEN}2. Shard Distribution:${NC}"
echo "Shards for index ${INDEX_NAME}:"
curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_cat/shards/${INDEX_NAME}?v"

echo -e "\n${GREEN}3. Forcing Query on Specific Shards:${NC}"
echo "This test will query specific shards to ensure cross-node communication"

# Get the model ID from the previous test
MODEL_ID=$(curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/_search" | jq -r '.hits.hits[0]._id')
echo "Using model ID: $MODEL_ID"

echo -e "\n${YELLOW}Test 1: Query with preference to force shard 0 (primary on node1)${NC}"
RESPONSE1=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_search?preference=_shards:0" -H 'Content-Type: application/json' -d"
{
  \"size\": 10,
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

if echo "$RESPONSE1" | grep -q "error"; then
    echo -e "${RED}ERROR on shard 0 query:${NC}"
    echo "$RESPONSE1" | jq '.'
else
    echo -e "${GREEN}SUCCESS - Results from shard 0:${NC}"
    echo "$RESPONSE1" | jq '.hits.total.value'
fi

echo -e "\n${YELLOW}Test 2: Query with preference to force shard 1 (primary on node2)${NC}"
RESPONSE2=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_search?preference=_shards:1" -H 'Content-Type: application/json' -d"
{
  \"size\": 10,
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

if echo "$RESPONSE2" | grep -q "error"; then
    echo -e "${RED}ERROR on shard 1 query:${NC}"
    echo "$RESPONSE2" | jq '.'
else
    echo -e "${GREEN}SUCCESS - Results from shard 1:${NC}"
    echo "$RESPONSE2" | jq '.hits.total.value'
fi

echo -e "\n${GREEN}4. Checking Query Execution Logs:${NC}"
echo "Looking for query execution across nodes..."

# Check recent logs for cross-node communication
echo -e "\n${YELLOW}Node 1 recent neural query logs:${NC}"
docker logs opensearch-node1 2>&1 | grep -i "neural" | tail -5

echo -e "\n${YELLOW}Node 2 recent neural query logs:${NC}"
docker logs opensearch-node2 2>&1 | grep -i "neural" | tail -5

echo -e "\n${GREEN}5. Testing Query with explain=true to see shard routing:${NC}"
curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_search?explain=true" -H 'Content-Type: application/json' -d"
{
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
}" | jq '.hits.hits[0]._shard, .hits.hits[0]._node'

echo -e "\n${GREEN}Summary:${NC}"
echo "- If both shard queries succeeded, the fix is working across nodes"
echo "- If you see errors on specific shards, it indicates the cross-node serialization issue"
echo "- The logs show which nodes are processing the queries"