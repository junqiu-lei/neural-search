#\!/bin/bash

# Script to test the fixed OpenSearch artifact locally

set -e

echo "Testing fixed OpenSearch artifact..."

# Set variables
TEST_DIR="/tmp/opensearch-test-$(date +%Y%m%d-%H%M%S)"
ARTIFACT="opensearch-3.1.0-linux-arm64-neural-query-streaming-fix.tar.gz"

# Create test directory
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "Extracting artifact..."
tar -xzf /home/junqiu/neural-search/$ARTIFACT

cd opensearch-3.1.0

# Disable security plugin
echo "Configuring OpenSearch..."
echo "plugins.security.disabled: true" >> config/opensearch.yml

# Set OPENSEARCH_INITIAL_ADMIN_PASSWORD to bypass security setup
export OPENSEARCH_INITIAL_ADMIN_PASSWORD="TestPassword123\!"

echo "Starting OpenSearch..."
bash opensearch-tar-install.sh &

# Store the PID
OS_PID=$\!

# Wait for OpenSearch to start
echo "Waiting for OpenSearch to start..."
sleep 30

# Check if OpenSearch is running
if ps -p $OS_PID > /dev/null; then
    echo "OpenSearch is running with PID: $OS_PID"
    
    # Check cluster health
    echo "Checking cluster health..."
    curl -s http://localhost:9200/_cluster/health | jq '.'
    
    # Check installed plugins
    echo "Checking installed plugins..."
    curl -s http://localhost:9200/_cat/plugins?v
    
    # Kill OpenSearch
    echo "Stopping OpenSearch..."
    kill $OS_PID
    wait $OS_PID 2>/dev/null || true
else
    echo "ERROR: OpenSearch failed to start"
    echo "Checking logs..."
    tail -50 logs/opensearch.log
    exit 1
fi

# Cleanup
cd /home/junqiu/neural-search
rm -rf "$TEST_DIR"

echo "Test completed successfully\!"
EOF < /dev/null