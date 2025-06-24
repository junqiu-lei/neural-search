#!/bin/bash
set -e

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
WORK_DIR="/tmp/opensearch-artifact-$TIMESTAMP"
ARTIFACT_NAME="opensearch-3.1.0-linux-arm64-radial-search-fix-$TIMESTAMP.tar.gz"

echo "Creating artifact with radial search serialization fix..."

# Create work directory
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Extract base artifact
echo "Extracting base OpenSearch artifact..."
tar -xzf /home/junqiu/neural-search/opensearch-3.1.0-linux-arm64.tar.gz

# Remove existing neural-search plugin
echo "Removing existing neural-search plugin..."
rm -rf opensearch-3.1.0/plugins/opensearch-neural-search

# Create temp directory for plugin extraction
PLUGIN_TEMP="$WORK_DIR/plugin-temp"
mkdir -p "$PLUGIN_TEMP"
cd "$PLUGIN_TEMP"

# Extract the built plugin directly into plugins directory
echo "Installing fixed neural-search plugin..."
PLUGIN_DIR="$WORK_DIR/opensearch-3.1.0/plugins/opensearch-neural-search"
mkdir -p "$PLUGIN_DIR"
cd "$PLUGIN_DIR"
unzip -q /home/junqiu/neural-search/build/distributions/opensearch-neural-search-3.1.0.0-SNAPSHOT.zip

# Create tarball
cd "$WORK_DIR"
echo "Creating tarball..."
tar -czf "$ARTIFACT_NAME" opensearch-3.1.0/

# Move to output location
mv "$ARTIFACT_NAME" /home/junqiu/neural-search/

# Cleanup
rm -rf "$WORK_DIR"

echo "Artifact created: $ARTIFACT_NAME"
echo ""
echo "This artifact includes the fix for radial search parameter serialization:"
echo "- Properly handles k=0 case for radial search queries"
echo "- Rebuilds KNNQueryBuilder without k when k=0 is detected"
echo "- Ensures consistent behavior across cluster nodes"