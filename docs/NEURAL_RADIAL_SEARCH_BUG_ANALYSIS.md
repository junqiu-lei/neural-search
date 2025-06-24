# Neural Radial Search Bug Analysis

## Summary

Neural radial search is failing in multi-node clusters because radial search parameters (min_score, max_distance) are not being serialized across nodes.

## Root Cause

The issue occurs in the serialization process when KNNQueryBuilderParser checks version support for radial search:

1. **KNNQueryBuilderParser.streamOutput()** uses:
   ```java
   boolean radialSearchSupported = minClusterVersionCheck.apply(KNNConstants.RADIAL_SEARCH_KEY);
   ```
   Where `RADIAL_SEARCH_KEY = "radial_search"`

2. **MinClusterVersionUtil.isClusterOnOrAfterMinReqVersion()** checks:
   - First looks in MINIMAL_VERSION_NEURAL map for the key
   - If not found, falls back to IndexUtil.minimalRequiredVersionMap
   - The key "radial_search" is not in MINIMAL_VERSION_NEURAL map
   - The fallback to IndexUtil likely returns false or doesn't contain the key

3. **Result**: radialSearchSupported = false, so min_score and max_distance are NOT written to the stream

## Evidence from Logs

### Node1 (Coordinating Node):
```
[DEBUG-NEURAL] Built KNNQueryBuilder - k=0, maxDistance=null, minScore=0.7
[DEBUG-NEURAL] doWriteTo called - k=0, maxDistance=null, minScore=0.7, originalQueryText=machine learning algorithms
```

### Node2 (Data Node):
```
[DEBUG-NEURAL] StreamInput constructor called - starting deserialization
[DEBUG-NEURAL] Read builder from stream
```
Then fails with: "[knn] requires exactly one of k, distance or score to be set"

The deserialization fails because:
- k=0 is read from stream
- min_score and max_distance are NOT in the stream (not serialized)
- KNNQueryBuilder.Builder.build() validation fails because it has k=0 but no radial parameters

## The Fix

The issue is that MinClusterVersionUtil needs to handle "radial_search" key properly. Options:

1. **Add "radial_search" to MINIMAL_VERSION_NEURAL map**:
   ```java
   private static final Map<String, Version> MINIMAL_VERSION_NEURAL = ImmutableMap.<String, Version>builder()
       .put(MODEL_ID_FIELD.getPreferredName(), MINIMAL_SUPPORTED_VERSION_DEFAULT_DENSE_MODEL_ID)
       .put(MAX_DISTANCE_FIELD.getPreferredName(), MINIMAL_SUPPORTED_VERSION_RADIAL_SEARCH)
       .put(MIN_SCORE_FIELD.getPreferredName(), MINIMAL_SUPPORTED_VERSION_RADIAL_SEARCH)
       .put("radial_search", MINIMAL_SUPPORTED_VERSION_RADIAL_SEARCH)  // Add this
       .put(QUERY_IMAGE_FIELD.getPreferredName(), MINIMAL_SUPPORTED_VERSION_QUERY_IMAGE_FIX)
       .build();
   ```

2. **Or modify isClusterOnOrAfterMinReqVersion() to handle radial_search specially**:
   ```java
   public static boolean isClusterOnOrAfterMinReqVersion(String key) {
       // Special handling for radial_search key
       if ("radial_search".equals(key)) {
           return isClusterOnOrAfterMinReqVersionForRadialSearch();
       }

       Version version;
       if (MINIMAL_VERSION_NEURAL.containsKey(key)) {
           version = MINIMAL_VERSION_NEURAL.get(key);
       } else {
           version = IndexUtil.minimalRequiredVersionMap.get(key);
       }
       return NeuralSearchClusterUtil.instance().getClusterMinVersion().onOrAfter(version);
   }
   ```

## Why It Works With Direct k-NN Queries

Direct k-NN queries work because they check their own version keys and handle serialization correctly. The issue only affects neural search because it relies on k-NN's serialization logic but uses a different version checking mechanism.
