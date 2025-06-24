#!/bin/bash

# Create final fixed artifact for neural query streaming issue

echo "Creating final fixed artifact..."

# Copy just the neural-search plugin since k-NN doesn't need changes
cp build/distributions/opensearch-neural-search-*.zip opensearch-neural-search-3.1.0-FIXED.zip

echo "Fixed artifact created:"
ls -la opensearch-neural-search-3.1.0-FIXED.zip

echo "Done! The fix is in NeuralQueryBuilder.createKNNQueryBuilder() which now:"
echo "- Only sets k when not doing radial search (maxDistance or minScore)"
echo "- Prevents k=0 from being passed with radial search parameters"
echo "- Avoids the validation error in KNNQueryBuilder"