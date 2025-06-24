#!/bin/bash

# Create fixed artifacts for the neural query streaming issue

echo "Creating fixed artifacts for neural query streaming issue..."

# Create a temporary directory for the artifacts
TEMP_DIR="/tmp/opensearch-fixed-artifacts"
rm -rf $TEMP_DIR
mkdir -p $TEMP_DIR

# Copy the built plugins
echo "Copying k-NN plugin..."
cp /home/junqiu/k-NN/build/distributions/opensearch-knn-*.zip $TEMP_DIR/

echo "Copying neural-search plugin..."
cp /home/junqiu/neural-search/build/distributions/opensearch-neural-search-*.zip $TEMP_DIR/

# Create a tarball with both plugins
echo "Creating tarball with fixed plugins..."
cd /home/junqiu/neural-search
tar -czf opensearch-3.1.0-linux-arm64-neural-query-streaming-fix.tar.gz -C $TEMP_DIR .

echo "Fixed artifacts created:"
ls -la opensearch-3.1.0-linux-arm64-neural-query-streaming-fix.tar.gz

echo "Contents:"
tar -tzf opensearch-3.1.0-linux-arm64-neural-query-streaming-fix.tar.gz

echo "Done!"