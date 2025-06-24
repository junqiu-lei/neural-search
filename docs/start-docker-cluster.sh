#!/bin/bash
set -e

echo "=== Starting OpenSearch Multi-Node Cluster with Neural Search Plugin ==="

# Stop any existing containers
echo "Stopping any existing containers..."
docker-compose down -v || true

# Start the cluster
echo "Starting cluster..."
docker-compose up -d

echo -e "\nCluster is starting up. You can:"
echo "1. Check logs: docker-compose logs -f"
echo "2. Run tests: ./test-radial-search.sh"
echo "3. Stop cluster: docker-compose down -v"