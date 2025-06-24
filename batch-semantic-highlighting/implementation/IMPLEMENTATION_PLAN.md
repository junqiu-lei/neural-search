# Batch Semantic Highlighting Implementation Plan

## Current Status

### Completed in Neural Search Plugin
1. ✅ Created `BatchHighlightingRequest` class for batch requests
2. ✅ Added `inferenceBatchHighlighting` method to `MLCommonsClientAccessor` (placeholder implementation)
3. ✅ Updated `SemanticHighlighterEngine` with batch processing methods
4. ✅ Added `use_batch` configuration support in `SemanticHighlighter`
5. ✅ Created design document for batch highlighting

### Pending Tasks

#### Neural Search Plugin
1. **True Batch Collection**: Implement proper document collection for batch processing
2. **Batch Size Configuration**: Add configurable batch size limits
3. **Error Handling**: Implement partial failure handling for batch requests
4. **Performance Metrics**: Add metrics for batch processing performance

#### ML Commons Plugin
1. **Create BatchHighlightingInputDataSet**: New dataset type for batch highlighting
2. **Update MLInputDataType**: Add BATCH_HIGHLIGHTING enum value
3. **Fix Parameter Serialization**: Update RemoteConnectorExecutor to handle complex objects
4. **Response Parsing**: Implement batch response parsing

## Implementation Phases

### Phase 1: ML Commons Foundation (Week 1)
1. Implement `BatchHighlightingInputDataSet`
2. Update `MLInputDataType` enum
3. Register dataset in `MLInputDatasetHandler`
4. Create unit tests

### Phase 2: Remote Connector Support (Week 1-2)
1. Update `RemoteConnectorExecutor` for complex parameters
2. Implement proper JSON serialization for batch requests
3. Add response parsing for batch results
4. Test with SageMaker endpoints

### Phase 3: Neural Search Integration (Week 2)
1. Update `MLCommonsClientAccessor` to use `BatchHighlightingInputDataSet`
2. Implement document collection strategy
3. Add batch size limits and configuration
4. Integrate with highlighting flow

### Phase 4: Testing & Documentation (Week 3)
1. Comprehensive unit tests
2. Integration tests with local and remote models
3. Performance benchmarking
4. User documentation

## Technical Challenges

### 1. Highlighter Interface Limitation
**Problem**: The OpenSearch `Highlighter` interface processes one field at a time.

**Solution Options**:
- Option A: Implement a highlighting coordinator that collects documents before processing
- Option B: Create a custom search phase that handles batch highlighting
- Option C: Use a thread-local accumulator to collect documents

**Recommendation**: Option A with a configurable timeout/size threshold.

### 2. Parameter Format Mismatch
**Problem**: ML Commons sends JSON strings, SageMaker expects JSON objects.

**Solution**: Update `RemoteConnectorExecutor` to handle different parameter types based on the dataset type.

### 3. Response Correlation
**Problem**: Matching batch responses back to original documents.

**Solution**: Include document IDs in batch requests and use them to correlate responses.

## Configuration Example

```json
{
  "highlight": {
    "fields": {
      "content": {
        "type": "semantic",
        "pre_tags": ["<mark>"],
        "post_tags": ["</mark>"]
      }
    },
    "options": {
      "model_id": "highlighting-model-id",
      "use_batch": true,
      "batch_size": 10,
      "batch_timeout_ms": 100
    }
  }
}
```

## Performance Targets

| Metric | Single Processing | Batch Processing | Improvement |
|--------|------------------|------------------|-------------|
| Latency per document | 50-100ms | 5-10ms | 5-10x |
| Throughput | 10-20 docs/sec | 100-200 docs/sec | 10x |
| Memory usage | Baseline | +20% | Acceptable |

## Risk Mitigation

1. **Backward Compatibility**: Keep `use_batch` default to `false`
2. **Graceful Degradation**: Fall back to single processing on batch failure
3. **Resource Limits**: Implement configurable batch size limits
4. **Timeout Handling**: Add configurable timeouts for batch collection

## Success Criteria

1. ✅ Batch processing reduces latency by at least 5x
2. ✅ No regression in single document processing
3. ✅ Works with both local and remote models
4. ✅ Proper error handling and logging
5. ✅ Comprehensive test coverage
6. ✅ Clear documentation and examples

## Next Steps

1. Review and approve design with team
2. Start ML Commons implementation
3. Set up test environment with batch model
4. Begin implementation following the phases above