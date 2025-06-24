#!/bin/bash

# Script to fix the OpenSearch artifact structure

set -e

echo "Fixing OpenSearch artifact plugin structure..."

# Set variables
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
WORK_DIR="/tmp/opensearch-fix-structure-$TIMESTAMP"
INPUT_ARTIFACT="opensearch-3.1.0-linux-arm64-neural-query-fix-20250619-012859.tar.gz"
OUTPUT_ARTIFACT="opensearch-3.1.0-linux-arm64-neural-query-streaming-fix.tar.gz"

# Create work directory
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "Extracting artifact..."
tar -xzf /home/junqiu/neural-search/$INPUT_ARTIFACT

# Navigate to plugins directory
cd opensearch-3.1.0/plugins

# Create proper neural-search plugin directory
echo "Creating proper plugin directory structure..."
mkdir -p opensearch-neural-search

# Move neural-search plugin files to the proper directory
echo "Moving neural-search plugin files..."
mv *.jar opensearch-neural-search/ 2>/dev/null || true
mv *.txt opensearch-neural-search/ 2>/dev/null || true
mv *.policy opensearch-neural-search/ 2>/dev/null || true
mv plugin-descriptor.properties opensearch-neural-search/ 2>/dev/null || true

# List the plugin directory to verify
echo "Plugin directory after reorganization:"
ls -la
echo ""
echo "Neural search plugin contents:"
ls -la opensearch-neural-search/

# Go back to create the tarball
cd "$WORK_DIR"

# Create the fixed tarball
echo "Creating fixed tarball..."
tar -czf "$OUTPUT_ARTIFACT" opensearch-3.1.0/

# Move to output directory
mv "$OUTPUT_ARTIFACT" /home/junqiu/neural-search/

# Cleanup
cd /home/junqiu/neural-search
rm -rf "$WORK_DIR"

echo "Fixed artifact created: $OUTPUT_ARTIFACT"
echo "Size: $(ls -lh $OUTPUT_ARTIFACT | awk '{print $5}')"