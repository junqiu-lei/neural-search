# Response to Suggestion: Reverting PRs #1183 and #1272

## Understanding the Suggestion
heemin32 suggests reverting PRs #1183 and #1272 and going back to a simpler approach where NeuralQueryBuilder directly creates KNNQueryBuilder without the wrapper.

## Why This Won't Solve the Current Issue

### 1. The Root Cause Remains
The radial search serialization issue occurs at the KNNQueryBuilder level, not in our wrapper:
- When k=null for radial search, KNNQueryBuilder serializes it as 0
- Upon deserialization, the validation fails because k=0 doesn't satisfy "requires exactly one of k, distance or score"
- This happens regardless of whether we use NeuralKNNQueryBuilder or create KNNQueryBuilder directly

### 2. What PRs #1183 and #1272 Achieved
- **#1183**: Created NeuralKNNQueryBuilder to encapsulate KNN query creation and isolate k-NN plugin API changes
- **#1272**: Added proper serialization support for originalQueryText field across nodes

### 3. Problems with Reverting
If we revert to the old approach:
- We'd still face the same radial search serialization issue
- We'd lose the ability to preserve originalQueryText across nodes
- We'd be more tightly coupled to k-NN plugin internals
- Future k-NN API changes would require changes throughout neural-search code

### 4. The Current Fix is Minimal
The fix only adds the missing `expandNested` field and properly handles the k=0 case. This is a surgical fix that:
- Maintains backward compatibility
- Preserves all the benefits of the wrapper pattern
- Solves the immediate issue without major architectural changes

## Recommendation
Instead of reverting, we should:
1. Keep the current wrapper pattern for better encapsulation
2. Apply the minimal fix (adding expandNested field)
3. Add rolling upgrade tests as suggested
4. Consider working with the k-NN team to improve their serialization handling in future versions

The wrapper pattern provides value beyond just this issue - it gives us control over how we handle k-NN queries and insulates us from future k-NN plugin changes.
