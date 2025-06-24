# Fixed OpenSearch Artifact

## Artifact Details
- **File**: opensearch-3.1.0-linux-arm64-fixed-neural-search.tar.gz
- **Created**: Thu Jun 19 01:28:41 UTC 2025
- **Base Version**: OpenSearch 3.1.0 (build 11179)
- **Architecture**: linux/arm64

## Fix Applied
This artifact contains a fix for the neural query streaming issue where queries with min_score or max_distance parameters fail with shard failures.

### The Issue
When using neural queries with radial search parameters (min_score or max_distance), the query fails with:
```
"[knn] requires exactly one of k, distance or score to be set"
```

### The Fix
Modified `NeuralQueryBuilder.createKNNQueryBuilder()` to only set the k parameter when not doing radial search:
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
- Traditional k-NN: `"k": 5`
- Radial search with min_score: `"min_score": 0.4`
- Radial search with max_distance: `"max_distance": 20.0`
