#!/bin/bash
set -e

echo "Testing radial search fix..."
echo "This script will:"
echo "1. Extract the artifact"
echo "2. Start OpenSearch"
echo "3. Create a test index with neural search"
echo "4. Test radial search queries"
echo ""

# Find the latest artifact
ARTIFACT=$(ls -t opensearch-3.1.0-linux-arm64-radial-search-fix-*.tar.gz | head -1)
if [ -z "$ARTIFACT" ]; then
    echo "Error: No radial search fix artifact found"
    exit 1
fi

echo "Using artifact: $ARTIFACT"

# Create test directory
TEST_DIR="/tmp/opensearch-radial-test-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Extract artifact
echo "Extracting artifact..."
tar -xzf "/home/junqiu/neural-search/$ARTIFACT"

# Configure OpenSearch
cd opensearch-3.1.0
echo "Configuring OpenSearch..."
echo "plugins.security.disabled: true" >> config/opensearch.yml
echo "discovery.type: single-node" >> config/opensearch.yml
export OPENSEARCH_INITIAL_ADMIN_PASSWORD="TestPassword123!"

# Start OpenSearch
echo "Starting OpenSearch..."
./opensearch-tar-install.sh &
OPENSEARCH_PID=$!

# Wait for OpenSearch to start
echo "Waiting for OpenSearch to start..."
for i in {1..30}; do
    if curl -s http://localhost:9200 > /dev/null 2>&1; then
        echo "OpenSearch is ready!"
        break
    fi
    sleep 2
done

# Check cluster health
echo ""
echo "Cluster health:"
curl -s http://localhost:9200/_cluster/health | jq '.'

# Check installed plugins
echo ""
echo "Installed plugins:"
curl -s "http://localhost:9200/_cat/plugins?v" | grep neural

# Create a test index
echo ""
echo "Creating test index..."
curl -X PUT http://localhost:9200/test-neural -H 'Content-Type: application/json' -d '{
  "settings": {
    "index": {
      "knn": true,
      "knn.algo_param.ef_search": 100,
      "number_of_shards": 2,
      "number_of_replicas": 0
    }
  },
  "mappings": {
    "properties": {
      "embedding": {
        "type": "knn_vector",
        "dimension": 3,
        "method": {
          "name": "hnsw",
          "space_type": "l2",
          "engine": "nmslib",
          "parameters": {
            "ef_construction": 128,
            "m": 24
          }
        }
      }
    }
  }
}'

# Add test documents
echo ""
echo "Adding test documents..."
for i in {1..5}; do
    curl -X POST http://localhost:9200/test-neural/_doc/$i -H 'Content-Type: application/json' -d "{
        \"embedding\": [$i.0, $((i*2)).0, $((i*3)).0]
    }"
done

# Refresh the index
curl -X POST http://localhost:9200/test-neural/_refresh

# Test radial search with max_distance
echo ""
echo "Testing radial search with max_distance (should work correctly)..."
curl -X POST http://localhost:9200/test-neural/_search -H 'Content-Type: application/json' -d '{
  "query": {
    "knn": {
      "embedding": {
        "vector": [2.0, 4.0, 6.0],
        "max_distance": 5.0
      }
    }
  }
}' | jq '.hits.total.value'

# Test radial search with min_score
echo ""
echo "Testing radial search with min_score (should work correctly)..."
curl -X POST http://localhost:9200/test-neural/_search -H 'Content-Type: application/json' -d '{
  "query": {
    "knn": {
      "embedding": {
        "vector": [2.0, 4.0, 6.0],
        "min_score": 0.5
      }
    }
  }
}' | jq '.hits.total.value'

# Test regular k-NN search
echo ""
echo "Testing regular k-NN search (should still work)..."
curl -X POST http://localhost:9200/test-neural/_search -H 'Content-Type: application/json' -d '{
  "query": {
    "knn": {
      "embedding": {
        "vector": [2.0, 4.0, 6.0],
        "k": 3
      }
    }
  }
}' | jq '.hits.total.value'

# Check logs for our debug messages
echo ""
echo "Checking logs for radial search handling..."
grep -A5 -B5 "radial search" logs/opensearch.log | tail -20 || echo "No radial search logs found yet"

# Cleanup
echo ""
echo "Cleaning up..."
kill $OPENSEARCH_PID
cd /
rm -rf "$TEST_DIR"

echo ""
echo "Test complete!"