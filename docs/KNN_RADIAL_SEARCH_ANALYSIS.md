# k-NN Plugin Radial Search Analysis

## Summary

The k-NN plugin handles radial search correctly in multi-node clusters despite using a different version check key than neural-search plugin.

## Version Check Differences

### Neural Search Plugin
- Uses actual field names as version check keys: "max_distance", "min_score"
- MinClusterVersionUtil checks these specific fields

### k-NN Plugin
- Uses a generic key: "radial_search"
- IndexUtil checks for this single key to determine if radial search is supported

## Why Both Work

Both approaches work because:

1. **Version checking is context-aware**: Each plugin checks versions within its own context
2. **OpenSearch version mapping**: The cluster version system maps feature support correctly
3. **Independent serialization**: Each plugin handles its own query serialization/deserialization

## Debug Log Analysis

### Successful Radial Search Flow

1. **Serialization on Node1**:
   ```
   [DEBUG-KNN] streamOutput called - k=0, maxDistance=0.5, minScore=null
   [DEBUG-KNN] Version check for RADIAL_SEARCH_KEY='radial_search' = true
   [DEBUG-KNN] Writing maxDistance=0.5
   ```

2. **Deserialization on Node2**:
   ```
   [DEBUG-KNN] streamInput called - starting deserialization
   [DEBUG-KNN] Read from stream - fieldName=my_vector, k=0
   [DEBUG-KNN] Version check for RADIAL_SEARCH_KEY='radial_search' = true
   [DEBUG-KNN] Read maxDistance=0.5
   [DEBUG-KNN] Read minScore=null
   ```

3. **Query Execution**:
   ```
   [DEBUG-KNN] doToQuery called - k=0, maxDistance=0.5, minScore=null
   [DEBUG-KNN] VectorQueryType determined: MAX_DISTANCE
   ```

## Key Insights

1. **k=0 Handling**: The k-NN plugin receives k=0 for radial searches but correctly identifies them by the presence of radial parameters

2. **No Builder Pattern Fix Needed**: Unlike neural-search, k-NN doesn't need the builder pattern fix because:
   - It reads k directly as an int (not Integer)
   - The validation in Builder.validate() checks for null k, maxDistance, or minScore
   - k=0 with radial parameters passes validation

3. **Version Check Success**: The generic "radial_search" key works because:
   - It's a boolean check for feature support
   - The actual parameters are always serialized/deserialized when the check passes
   - No parameter-specific version checking is needed

## Conclusion

The concern about k-NN plugin not supporting radial search due to different version check keys is unfounded. The plugin correctly:
- Performs version checks using its own key
- Serializes/deserializes radial parameters
- Executes radial searches with proper query types
- Handles k=0 appropriately for radial searches

Both plugins work correctly in multi-node environments, just with different implementation approaches for version checking.
