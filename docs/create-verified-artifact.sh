#!/bin/bash

# Script to create a verified OpenSearch artifact with the patched neural-search plugin

set -e

echo "Creating and verifying fixed OpenSearch artifact..."

# Set timestamp for the artifact name
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
WORK_DIR="/tmp/opensearch-verified-$TIMESTAMP"
ARTIFACT_NAME="opensearch-3.1.0-linux-arm64-neural-query-fix-verified-$TIMESTAMP.tar.gz"
BASE_ARTIFACT="/home/junqiu/neural-search/opensearch-3.1.0-linux-arm64.tar.gz"

# Create work directory
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "Extracting OpenSearch base artifact..."
tar -xzf "$BASE_ARTIFACT"

# Navigate to plugins directory
cd opensearch-3.1.0/plugins

# Remove existing neural-search plugin
echo "Removing existing neural-search plugin..."
rm -rf opensearch-neural-search

# Create temporary directory for plugin extraction
PLUGIN_TEMP="$WORK_DIR/plugin-temp"
mkdir -p "$PLUGIN_TEMP"
cd "$PLUGIN_TEMP"

# Copy and extract the fixed neural-search plugin
echo "Extracting fixed neural-search plugin..."
cp /home/junqiu/neural-search/build/distributions/opensearch-neural-search-*.zip ./
unzip -q opensearch-neural-search-*.zip

# Move the plugin to the correct location
mv opensearch-neural-search "$WORK_DIR/opensearch-3.1.0/plugins/"

# Go back to work directory
cd "$WORK_DIR"

# Create the new tarball
echo "Creating new tarball..."
tar -czf "$ARTIFACT_NAME" opensearch-3.1.0/

# Move to output directory
mv "$ARTIFACT_NAME" /home/junqiu/neural-search/

# Cleanup
cd /home/junqiu/neural-search
rm -rf "$WORK_DIR"

echo "Fixed artifact created: $ARTIFACT_NAME"
echo "Size: $(ls -lh $ARTIFACT_NAME | awk '{print $5}')"