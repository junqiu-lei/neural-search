# Alternative Approach for PR #1393

If rebuilding is considered too complex, here's a simpler alternative that avoids the build() validation error:

```java
public NeuralKNNQueryBuilder(StreamInput in) throws IOException {
    super(in);

    // Try to read as KNNQueryBuilder directly using NamedWriteable
    // This would require the k-NN plugin to register KNNQueryBuilder properly
    try {
        this.knnQueryBuilder = (KNNQueryBuilder) in.readNamedWriteable(QueryBuilder.class);
    } catch (Exception e) {
        // Fallback to current approach if direct reading fails
        KNNQueryBuilder.Builder builder = KNNQueryBuilderParser.streamInput(in, MinClusterVersionUtil::isClusterOnOrAfterMinReqVersion);

        // Handle k=0 case by catching and working around the validation error
        try {
            this.knnQueryBuilder = builder.build();
        } catch (IllegalArgumentException ex) {
            if (ex.getMessage().contains("requires exactly one of k, distance or score")) {
                // This is a radial search query with k=0
                // Set a dummy k value to pass validation, then rebuild properly
                builder.k(1);
                KNNQueryBuilder temp = builder.build();

                // Now rebuild without k
                this.knnQueryBuilder = KNNQueryBuilder.builder()
                    .fieldName(temp.fieldName())
                    .vector((float[]) temp.vector())
                    .filter(temp.getFilter())
                    .expandNested(temp.getExpandNested())
                    .maxDistance(temp.getMaxDistance())
                    .minScore(temp.getMinScore())
                    .methodParameters(temp.getMethodParameters())
                    .rescoreContext(temp.getRescoreContext())
                    .build();
            } else {
                throw ex;
            }
        }
    }

    if (MinClusterVersionUtil.isVersionOnOrAfterMinReqVersionForNeuralKNNQueryText(in.getVersion())) {
        this.originalQueryText = in.readOptionalString();
    } else {
        this.originalQueryText = null;
    }
}
```

However, this approach has drawbacks:
1. It relies on exception handling for control flow
2. It's more complex than the current rebuilding approach
3. The NamedWriteable approach would require changes in the k-NN plugin

The current rebuilding approach is cleaner and more explicit about handling the k=0 case.
