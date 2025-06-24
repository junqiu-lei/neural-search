# Debug Analysis: Neural Query Streaming Issue

## Root Cause Identification

Through extensive logging and testing, I've identified the exact cause of the neural query streaming failures when using `min_score` or `max_distance` parameters.

## The Issue Flow

### 1. Query Creation
When a neural query is created with `min_score`:
```json
{
  "neural": {
    "text_embedding": {
      "query_text": "What are the main treatments for type 2 diabetes?",
      "model_id": "HB-ghZcBNFpY2An76khT",
      "min_score": 0.4
    }
  }
}
```

### 2. Local Node Processing
The coordinating node creates a `NeuralKNNQueryBuilder` with these parameters:
```
[DEBUG] KNN Query: k=0, maxDistance=null, minScore=0.4
```

### 3. Serialization
The query is serialized for streaming to other shards:
```
[DEBUG] NeuralKNNQueryBuilder.doWriteTo() - Starting parameter streaming
[DEBUG] Version: 3.1.0
[DEBUG] KNN Query: k=0, maxDistance=null, minScore=0.4
```

### 4. Remote Node Deserialization
The receiving node attempts to deserialize:
```
[DEBUG] NeuralKNNQueryBuilder(StreamInput) - Starting parameter deserialization
[DEBUG] Input Version: 3.1.0
[DEBUG] Using MinClusterVersionUtil for version checking on input stream
```

### 5. Validation Failure
The KNNQueryBuilder validation fails because both `k` (=0) and `minScore` (=0.4) are set:
```
"reason": "[knn] requires exactly one of k, distance or score to be set"
```

## Why This Happens

The issue stems from how `NeuralKNNQueryBuilder` (introduced in 3.0) wraps `KNNQueryBuilder`:

1. In `KNNQueryBuilder.Builder.build()` (k-NN plugin), when k is null, it's converted to 0:
   ```java
   int k = this.k == null ? 0 : this.k;
   ```

2. The validation in `KNNQueryBuilder` checks that exactly ONE of k, maxDistance, or minScore is set:
   ```java
   if ((k != null && maxDistance != null) || (maxDistance != null && minScore != null) || (k != null && minScore != null)) {
       throw new IllegalArgumentException("[knn] requires exactly one of k, distance or score to be set");
   }
   ```

3. Since k is stored as a primitive `int` in KNNQueryBuilder, it can't be null, so k=0 is always present.

4. When both k=0 and minScore=0.4 are present, the validation fails.

## Test Results

Testing various parameter combinations confirmed the issue:

| Test Case | Parameters | Result | Logs |
|-----------|------------|--------|------|
| Traditional k-NN | k=5 only | ✅ Success | `k=5, maxDistance=null, minScore=null` |
| Radial Search | min_score=0.4 only | ❌ Shard failures | `k=0, maxDistance=null, minScore=0.4` |
| Radial Search | max_distance=20.0 only | ❌ Shard failures | `k=0, maxDistance=20.0, minScore=null` |
| No parameters | none | ✅ Success (k=10 default) | `k=10, maxDistance=null, minScore=null` |

## Why It Started in 3.0

- `NeuralKNNQueryBuilder` was introduced in 3.0 as a wrapper around `KNNQueryBuilder`
- This exposed the existing issue in `KNNQueryBuilder` where k=0 isn't properly handled for radial search
- Prior to 3.0, neural queries didn't use this wrapping mechanism

## The Fix

The issue can be fixed in `NeuralQueryBuilder.createKNNQueryBuilder()` by only setting k when not doing radial search:

```java
// Only set k if we're not doing radial search
if (maxDistance() == null && minScore() == null) {
    builder.k(k());
}

// Set radial search parameters
if (maxDistance() != null) {
    builder.maxDistance(maxDistance());
}
if (minScore() != null) {
    builder.minScore(minScore());
}
```

This prevents k=0 from being set when using radial search parameters, avoiding the validation error entirely.

## Code References

- Issue occurs at: `org.opensearch.knn.index.query.KNNQueryBuilder.Builder.build()` - line 253
- Fix location: `org.opensearch.neuralsearch.query.NeuralQueryBuilder.createKNNQueryBuilder()` - line 842
