# Neural Radial Search Multi-Node Verification Report

## Summary

Successfully verified the neural radial search functionality in a multi-node Docker cluster setup with the latest changes from the neural-search plugin.

## Test Environment

- **OpenSearch Version**: 3.1.0 (staging)
- **Cluster Configuration**: 2 nodes (opensearch-node1, opensearch-node2)
- **Plugin Version**: 3.1.0.0-SNAPSHOT (built from latest source)
- **Test Date**: 2025-06-19

## Changes Verified

The following changes from PR #1393 have been tested:

1. **NeuralKNNQueryBuilder**: Proper handling of k=null to k=0 serialization for radial search
2. **Cross-node query serialization**: Verified that radial search queries (with min_score/max_distance) work correctly across nodes
3. **No NPE errors**: Confirmed that the "Cannot invoke getK()" error no longer occurs

## Test Results

### 1. Basic Neural Radial Search
- ✅ Neural radial search with `min_score` parameter works correctly
- ✅ Neural radial search with `max_distance` parameter works correctly
- ✅ Documents are properly distributed across shards (verified 2-shard distribution)

### 2. Cross-Node Communication
- ✅ Queries with `preference=_prefer_nodes` execute successfully
- ✅ No serialization errors when queries are coordinated by different nodes
- ✅ Results are consistent across different node preferences

### 3. Error Verification
- ✅ No "Cannot invoke getK()" errors in logs
- ✅ No NPE (NullPointerException) errors during query execution
- ✅ No serialization/deserialization errors in multi-node setup

## Test Scripts Created

1. **test-neural-radial-multi-node.sh**: Comprehensive test covering:
   - Document indexing with embeddings
   - Neural radial search with min_score
   - Neural radial search with max_distance
   - Cross-node query execution with preferences
   - Log verification

2. **verify-radial-serialization.sh**: Focused test for serialization:
   - Specific verification of k=null -> k=0 handling
   - Cross-node query serialization
   - Error detection in logs

## Key Code Changes Verified

The fix in `NeuralKNNQueryBuilder.java` properly handles the radial search case:

```java
private static void applySearchParameters(KNNQueryBuilder.Builder builder, Integer k, Float maxDistance, Float minScore) {
    // Only set k if it's not null and greater than 0
    // k=0 indicates radial search after deserialization
    if (k != null && k > SERIALIZED_NULL_K_VALUE) {
        builder.k(k);
    }

    // Set radial search parameters if provided
    if (maxDistance != null) {
        builder.maxDistance(maxDistance);
    }
    if (minScore != null) {
        builder.minScore(minScore);
    }
}
```

## Conclusion

The neural radial search functionality is working correctly in multi-node clusters. The serialization issue where k=null was causing NPE errors has been successfully resolved. The fix ensures that radial search queries (those using min_score or max_distance without k) are properly serialized and deserialized across nodes.
