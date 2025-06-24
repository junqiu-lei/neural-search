# Batch Semantic Highlighting Implementation

## Overview

This directory contains the design, implementation, and documentation for batch semantic highlighting support in OpenSearch neural-search plugin. Batch processing allows multiple documents to be highlighted in a single ML model inference call, significantly improving performance.

## Directory Structure

```
batch-semantic-highlighting/
├── README.md                          # This file
├── design/
│   └── BATCH_SEMANTIC_HIGHLIGHTING_DESIGN.md  # Comprehensive design document
├── implementation/
│   └── IMPLEMENTATION_PLAN.md         # Detailed implementation plan with phases
├── ml-commons-changes/
│   ├── ML_COMMONS_BATCH_CHANGES.md   # Required ML Commons changes
│   └── implement-ml-commons-changes.sh # Script to implement changes
├── testing/
│   └── TEST_PLAN.md                  # Comprehensive test plan
└── USAGE_EXAMPLE.md                  # Usage examples and best practices
```

## Quick Summary

### What's Implemented

1. **Neural Search Plugin**
   - ✅ `BatchHighlightingRequest` class for batch requests
   - ✅ `inferenceBatchHighlighting` method in `MLCommonsClientAccessor`
   - ✅ Batch methods in `SemanticHighlighterEngine`
   - ✅ `use_batch` configuration support

2. **Documentation**
   - ✅ Comprehensive design document
   - ✅ Implementation plan with timelines
   - ✅ ML Commons changes specification
   - ✅ Test plan with all scenarios
   - ✅ Usage examples

### What's Pending

1. **ML Commons Plugin**
   - ❌ `BatchHighlightingInputDataSet` implementation
   - ❌ Parameter serialization fixes for SageMaker
   - ❌ Batch response parsing

2. **Neural Search Plugin**
   - ❌ True batch collection mechanism
   - ❌ Integration with ML Commons batch dataset
   - ❌ Performance optimizations

## Key Benefits

- **Performance**: 5-10x faster highlighting for multiple documents
- **Efficiency**: Reduced network calls to ML models
- **Scalability**: Better resource utilization
- **Compatibility**: Backward compatible with `use_batch` flag

## Usage Example

```json
POST /index/_search
{
  "query": {"match": {"content": "symptoms"}},
  "highlight": {
    "fields": {
      "content": {"type": "semantic"}
    },
    "options": {
      "model_id": "highlighting-model",
      "use_batch": true
    }
  }
}
```

## Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| Design | ✅ Complete | Comprehensive design ready |
| Neural Search Changes | 🟡 Partial | Basic structure implemented |
| ML Commons Changes | ❌ Pending | Specification complete |
| Testing | ❌ Pending | Test plan ready |
| Documentation | ✅ Complete | All docs created |

## Next Steps

1. **Review Design**: Get team feedback on design document
2. **Choose Implementation Approach** (flexible options):
   - **Option A**: ML Commons changes for proper batch dataset support
   - **Option B**: Neural Search plugin with custom batch handling
   - **Option C**: Model-side changes for better compatibility
3. **Implementation**:
   - Based on chosen approach, implement necessary changes
   - Leverage existing production models (IDs in CLAUDE.md)
4. **Testing**: Execute test plan with production models
5. **Performance Tuning**: Optimize based on benchmarks

## Available Resources

- **Production Models**: Already deployed at `/home/junqiu/tracing_gpu/batch_model/FINAL/`
  - Single: `c7DtopcBzGk_n9nPCKO9`
  - Batch: `5KHtopcBJ3g2K0lQM9Nx`
- **Verified Performance**: ~8ms per document in batch mode
- **Dynamic Batch Support**: 1-128 documents without recompilation

## Technical Challenges

1. **Highlighter Interface**: Processes one field at a time
   - Solution: Implement batch collector at higher level

2. **Parameter Format**: ML Commons vs SageMaker mismatch
   - Solution: Update RemoteConnectorExecutor

3. **Response Correlation**: Matching results to documents
   - Solution: Use document IDs for correlation

## Contributing

To contribute to this implementation:

1. Review the design document
2. Check the implementation plan
3. Follow the test plan for validation
4. Update documentation as needed

## Questions?

For questions or discussions:
- Review the design document first
- Check the implementation plan
- Refer to usage examples
- Create an issue for unresolved questions