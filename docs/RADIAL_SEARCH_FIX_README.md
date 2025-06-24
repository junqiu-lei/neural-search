# Radial Search Serialization Fix for Neural Search Plugin

## Issue Description

The neural search plugin was experiencing issues with radial search queries (using `max_distance` or `min_score` instead of `k`) in multi-node/multi-shard deployments. The root cause was improper handling of the `k` parameter during cross-node serialization.

### Problem Details

1. **Serialization Issue**: The k-NN plugin always serializes the `k` parameter as an integer, even for radial search queries where `k` should not be set
2. **Default Value**: When `k` is null (for radial search), the KNNQueryBuilder.Builder converts it to 0 during build
3. **Cross-Node Failure**: This 0 value causes validation errors when the query is deserialized on other nodes

## Solution

The fix implements proper handling of the k=0 case in the NeuralKNNQueryBuilder's StreamInput constructor:

1. **Detection**: When deserializing, we detect if k=0 (which indicates radial search)
2. **Rebuilding**: We rebuild the KNNQueryBuilder without setting k when k=0 is detected
3. **Preservation**: All other parameters (maxDistance, minScore, etc.) are preserved correctly

### Code Changes

In `NeuralKNNQueryBuilder.java` StreamInput constructor:

```java
// Build temporary KNN to extract values
KNNQueryBuilder tempKnn = knnBuilder.build();

// Rebuild properly handling k=0 case for radial search
KNNQueryBuilder.Builder finalBuilder = KNNQueryBuilder.builder()
    .fieldName(tempKnn.fieldName())
    .vector((float[]) tempKnn.vector());

// Only set k if it's greater than 0 (k=0 means radial search)
if (tempKnn.getK() > 0) {
    finalBuilder.k(tempKnn.getK());
}

// Copy all other parameters...
```

## Testing

### Test Scenarios

1. **Radial Search with max_distance**: Query should execute successfully across all nodes
2. **Radial Search with min_score**: Query should execute successfully across all nodes
3. **Regular k-NN Search**: Should continue to work as expected
4. **Multi-shard Index**: Radial search should work with indices having multiple shards

### Verification Steps

1. Create a multi-shard index with KNN enabled
2. Index sample documents with vectors
3. Execute radial search queries with max_distance or min_score
4. Verify results are returned without errors
5. Check logs for proper handling of k=0 case

## Artifact Details

The fixed artifact includes:
- OpenSearch 3.1.0 base distribution
- Neural Search plugin with radial search serialization fix
- All required dependencies

### Installation

1. Extract the artifact
2. Configure OpenSearch (disable security for testing)
3. Start OpenSearch
4. Verify plugin is loaded: `curl http://localhost:9200/_cat/plugins?v`

## Debug Logging

The fix includes debug logging to trace the serialization/deserialization process:

- `[DEBUG] Temp KNN Query from stream: k=0, maxDistance=X, minScore=null`
- `[DEBUG] Not setting k (k=0 indicates radial search)`
- `[DEBUG] Final KNN Query: k=0, maxDistance=X, minScore=null`

These logs help verify the fix is working correctly in production environments.

## Compatibility

This fix maintains backward compatibility:
- Regular k-NN queries (with k > 0) work unchanged
- Radial search queries now work correctly in distributed environments
- No changes to query syntax or API

## Known Limitations

- The k-NN plugin still serializes k as 0 for radial search (we can't change this)
- The fix works around this limitation by detecting and handling the k=0 case
- Future versions of the k-NN plugin should properly handle optional k parameter
