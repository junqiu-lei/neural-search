#!/bin/bash

# Script to create a fixed OpenSearch artifact with the patched neural-search plugin

set -e

echo "Creating fixed OpenSearch artifact with neural query streaming fix..."

# Set timestamp for the artifact name
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
WORK_DIR="/tmp/opensearch-fix-$TIMESTAMP"
ARTIFACT_NAME="opensearch-3.1.0-linux-arm64-fixed-neural-search.tar.gz"

# Create work directory
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "Extracting OpenSearch base artifact..."
tar -xzf /home/junqiu/neural-search/opensearch-3.1.0-linux-arm64-base.tar.gz

# Navigate to plugins directory
cd opensearch-3.1.0/plugins

# List current plugins
echo "Current plugins:"
ls -la

# Remove existing neural-search plugin
echo "Removing existing neural-search plugin..."
rm -rf opensearch-neural-search

# Install the fixed neural-search plugin
echo "Installing fixed neural-search plugin..."
cp /home/junqiu/neural-search/build/distributions/opensearch-neural-search-*.zip ./
unzip -q opensearch-neural-search-*.zip
rm opensearch-neural-search-*.zip

# List plugins after replacement
echo "Plugins after replacement:"
ls -la

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

# Generate README for the fixed artifact
cat > FIXED_ARTIFACT_README.md << EOF
# Fixed OpenSearch Artifact

## Artifact Details
- **File**: $ARTIFACT_NAME
- **Created**: $(date)
- **Base Version**: OpenSearch 3.1.0 (build 11179)
- **Architecture**: linux/arm64

## Fix Applied
This artifact contains a fix for the neural query streaming issue where queries with min_score or max_distance parameters fail with shard failures.

### The Issue
When using neural queries with radial search parameters (min_score or max_distance), the query fails with:
\`\`\`
"[knn] requires exactly one of k, distance or score to be set"
\`\`\`

### The Fix
Modified \`NeuralQueryBuilder.createKNNQueryBuilder()\` to only set the k parameter when not doing radial search:
- If maxDistance or minScore is present, k is not set
- This prevents the validation error when queries are streamed between nodes

### Debug Logging Added
The fix includes debug logging to track parameter handling:
- Logs initial parameters: k, maxDistance, minScore
- Logs whether radial search is detected
- Logs which parameters are being set

## Installation
1. Extract the tarball
2. Follow standard OpenSearch installation procedures
3. Monitor CloudWatch logs for debug messages prefixed with [DEBUG]

## Testing
Test neural queries with various parameter combinations:
- Traditional k-NN: \`"k": 5\`
- Radial search with min_score: \`"min_score": 0.4\`
- Radial search with max_distance: \`"max_distance": 20.0\`
EOF

echo "README created: FIXED_ARTIFACT_README.md"