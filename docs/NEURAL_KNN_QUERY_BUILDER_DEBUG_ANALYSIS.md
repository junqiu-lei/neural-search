# NeuralKNNQueryBuilder Debug Analysis

## Summary

This document captures the debug logging analysis of NeuralKNNQueryBuilder in a multi-node OpenSearch environment, focusing on how queries are serialized/deserialized across nodes and how the radial search fix works.

## Test Environment

- 2-node OpenSearch cluster (opensearch-fix-node1, opensearch-fix-node2)
- Neural search plugin with debug logging
- Model ID: B_wyipcB1J4KrYCjXcCQ

## Query Flow Analysis

### Test 1: Regular k-NN Neural Search (k=5)

**Query**: Neural search with k=5, routed to node2

**Flow on Node1 (Coordinating Node)**:
1. Neural query created with k=5
2. After model inference, builds NeuralKNNQueryBuilder:
   - No logs from Builder.build() on node1 (query created from NeuralQueryBuilder)
3. Serialization (doWriteTo):
   ```
   [DEBUG-NEURAL] doWriteTo called - k=5, maxDistance=null, minScore=null, originalQueryText=search technology
   [DEBUG-NEURAL] Writing originalQueryText='search technology'
   ```

**Flow on Node2 (Data Node)**:
1. Deserialization (StreamInput constructor):
   ```
   [DEBUG-NEURAL] StreamInput constructor called - starting deserialization
   [DEBUG-NEURAL] Read builder from stream
   [DEBUG-NEURAL] Built temporary KNN - k=5, maxDistance=null, minScore=null
   [DEBUG-NEURAL] Calling applySearchParameters from StreamInput constructor
   [DEBUG-NEURAL] applySearchParameters called - k=5, maxDistance=null, minScore=null
   [DEBUG-NEURAL] Setting k=5 (k is not null and > 0)
   [DEBUG-NEURAL] Building final KNN query from StreamInput
   [DEBUG-NEURAL] Final KNN built - k=5, maxDistance=null, minScore=null
   [DEBUG-NEURAL] Read originalQueryText='search technology'
   ```

### Test 2: Radial Search with min_score

**Query**: Neural search with min_score=0.3 (no k value), routed to node2

**Flow on Node1 (Coordinating Node)**:
1. Neural query created with min_score=0.3, k=null
2. After model inference, builds NeuralKNNQueryBuilder:
   ```
   [DEBUG-NEURAL] Builder.build() called - fieldName=embedding, k=null, maxDistance=null, minScore=0.3, expandNested=null, originalQueryText=search technology
   [DEBUG-NEURAL] Created knnBuilderInstance, calling applySearchParameters
   [DEBUG-NEURAL] applySearchParameters called - k=null, maxDistance=null, minScore=0.3
   [DEBUG-NEURAL] NOT setting k - k=null, condition: k != null && k > 0 = false
   [DEBUG-NEURAL] Setting minScore=0.3
   [DEBUG-NEURAL] Building final KNNQueryBuilder
   [DEBUG-NEURAL] Built KNNQueryBuilder - k=0, maxDistance=null, minScore=0.3
   [DEBUG-NEURAL] Private constructor called - k=0, maxDistance=null, minScore=0.3, originalQueryText=search technology
   ```
   Note: k=null becomes k=0 after KNNQueryBuilder.build()

3. Serialization would send k=0 to node2

**Flow on Node2 (Data Node)**:
1. Would receive k=0 from serialization
2. The fix in StreamInput constructor rebuilds the query:
   - Detects k=0 (which was null before serialization)
   - Uses applySearchParameters to handle k=0 correctly
   - Does NOT set k on the builder (leaves it null)
   - Sets only minScore=0.3
   - Results in correct radial search query

### Test 3: Radial Search with max_distance

**Query**: Neural search with max_distance=5.0 (no k value), routed to node2

**Flow on Node1**:
```
[DEBUG-NEURAL] Builder.build() called - fieldName=embedding, k=null, maxDistance=5.0, minScore=null, expandNested=null, originalQueryText=search technology
[DEBUG-NEURAL] applySearchParameters called - k=null, maxDistance=5.0, minScore=null
[DEBUG-NEURAL] NOT setting k - k=null, condition: k != null && k > 0 = false
[DEBUG-NEURAL] Setting maxDistance=5.0
[DEBUG-NEURAL] Built KNNQueryBuilder - k=0, maxDistance=5.0, minScore=null
[DEBUG-NEURAL] doWriteTo called - k=0, maxDistance=5.0, minScore=null, originalQueryText=search technology
```

## Key Insights

### 1. The Problem
- Radial search queries have k=null (they use min_score or max_distance)
- KNNQueryBuilder serializes null as 0
- Without the fix, node2 would interpret k=0 as a valid k value

### 2. The Solution
The StreamInput constructor implements a two-phase approach:
1. **Phase 1**: Build temporary KNN query to extract all parameters
2. **Phase 2**: Rebuild with applySearchParameters that handles k=0 correctly

### 3. applySearchParameters Logic
```java
if (k != null && k > SERIALIZED_NULL_K_VALUE) {  // SERIALIZED_NULL_K_VALUE = 0
    builder.k(k);  // Only set k if > 0
} else {
    // Don't set k, leave it null for radial search
}
```

### 4. Why Builder Pattern Change Was Necessary
- Direct building would preserve k=0 from deserialization
- Two-phase rebuild allows intercepting and correcting k=0 → null
- Ensures radial search queries work correctly in multi-node clusters

## Conclusion

The fix successfully handles the edge case where radial search queries (with null k) get serialized as k=0 across nodes. The two-phase rebuild pattern in the StreamInput constructor ensures that k=0 is correctly interpreted as a radial search query rather than a regular k-NN query with 0 results.
