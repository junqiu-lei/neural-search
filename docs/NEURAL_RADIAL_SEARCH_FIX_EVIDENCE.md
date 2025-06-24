# Neural Radial Search Fix Evidence Report

## Executive Summary

This report demonstrates that the neural radial search bug has been successfully fixed in the multi-node environment while maintaining full functionality of neural search features.

## Fix Overview

**Issue**: Neural radial search queries (using `min_score` or `max_distance` parameters) were failing in multi-node clusters due to serialization issues during query distribution across nodes.

**Root Cause**: The `NeuralKNNQueryBuilder` was using manual field parsing in its `StreamInput` constructor instead of delegating to the underlying `KNNQueryBuilder`, causing deserialization failures.

**Solution**: Modified the `StreamInput` constructor to use delegation pattern:
```java
public NeuralKNNQueryBuilder(StreamInput in) throws IOException {
    super(in);
    this.knnQueryBuilder = new KNNQueryBuilder(in);
    // ... rest of initialization
}
```

## Testing Environment

- **Cluster Configuration**: 2-node OpenSearch cluster (Docker)
- **OpenSearch Version**: 3.1.0 (staging)
- **Neural Search Plugin**: 3.1.0.0-SNAPSHOT (with fix applied)
- **Test Model**: huggingface/sentence-transformers/all-MiniLM-L6-v2

## Test Results

### 1. Neural Radial Search with min_score

**Test Query**:
```json
{
  "query": {
    "neural": {
      "embedding": {
        "query_text": "artificial intelligence and deep learning",
        "model_id": "85ZOi5cBor0noQeRBty6",
        "min_score": 0.3
      }
    }
  }
}
```

**Result**: SUCCESS - Query executed without shard failures
- Retrieved 5 documents with scores above 0.3
- No serialization errors
- Cross-node query distribution worked correctly

### 2. Neural Radial Search with max_distance

**Test Query**:
```json
{
  "query": {
    "neural": {
      "embedding": {
        "query_text": "neural network architectures",
        "model_id": "85ZOi5cBor0noQeRBty6",
        "max_distance": 5.0
      }
    }
  }
}
```

**Result**: SUCCESS - Query executed without shard failures
- Retrieved documents within distance threshold
- No serialization errors
- Multi-shard queries worked correctly

### 3. Regular Neural Search with k

**Test Query**:
```json
{
  "query": {
    "neural": {
      "embedding": {
        "query_text": "machine learning algorithms",
        "model_id": "85ZOi5cBor0noQeRBty6",
        "k": 3
      }
    }
  }
}
```

**Result**: SUCCESS - Standard k-NN search continues to work
- Retrieved top 3 documents
- No regression in existing functionality

### 4. Semantic Search Test

**Test Query**:
```json
{
  "query": {
    "neural": {
      "embedding": {
        "query_text": "treatments for neurodegenerative diseases",
        "model_id": "85ZOi5cBor0noQeRBty6",
        "k": 2
      }
    }
  }
}
```

**Result**: SUCCESS - Semantic search functionality preserved
- Successfully retrieved relevant medical documents
- Document ranking based on semantic similarity worked correctly

## Backward Compatibility

The fix includes backward compatibility measures for rolling upgrades:

1. **Version Detection**: Added version checking to determine cluster capability:
   ```java
   if (MinClusterVersionUtil.isClusterOnOrAfterMinReqVersionForNeuralKNNQueryBuilder()) {
       // Use NeuralKNNQueryBuilder for version 3.0.0+
   } else {
       // Fall back to NeuralQueryBuilder for older versions
   }
   ```

2. **BWC Test**: Added `NeuralKNNQueryBWCIT` test to verify compatibility during rolling upgrades from 2.19.0

3. **Constants**: Defined `NEURAL_KNN_QUERY` constant for consistent version checking

## Unit Test Coverage

Added comprehensive unit tests:
- Serialization tests for radial search parameters
- Version-based query builder selection tests
- Parameter validation tests

All tests passing: `./gradlew test` BUILD SUCCESSFUL

## Conclusion

The neural radial search functionality has been successfully fixed and verified in a multi-node environment. The fix:

1. Resolves the serialization issue that caused shard failures
2. Maintains backward compatibility for rolling upgrades
3. Preserves all existing neural search functionality
4. Includes comprehensive test coverage

The implementation is ready for production deployment.
