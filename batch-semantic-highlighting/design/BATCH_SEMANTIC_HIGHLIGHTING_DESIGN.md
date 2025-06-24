# Batch Semantic Highlighting Design Document

## 1. Overview

This document outlines the design for implementing batch semantic highlighting in OpenSearch, which allows processing multiple documents in a single ML model inference call for improved performance.

## 2. Goals

1. **Performance**: Reduce latency by processing multiple documents in a single model inference call
2. **Compatibility**: Support both batch and single-document processing with backward compatibility
3. **Flexibility**: Support both remote (SageMaker) and local ML models
4. **Clean Architecture**: Remove parallel processing complexity in favor of true batch processing

## 3. Current State Analysis

### 3.1 Existing Implementation Issues
- Current implementation uses parallel processing as a fallback when batch fails
- ML Commons sends parameters as JSON strings, but SageMaker expects JSON objects
- Parameter format mismatch: `{"batch": "[{...}]"}` vs `{"parameters": {"batch": [{...}]}}`

### 3.2 Performance Benchmarks  
- Single document processing: ~50-100ms per document
- Batch processing (verified with production models): ~8ms per document
- Actual improvement: 6-12x faster with batch processing
- Production models deployed and ready:
  - Single: `c7DtopcBzGk_n9nPCKO9`
  - Batch: `5KHtopcBJ3g2K0lQM9Nx`
  - Location: `/home/junqiu/tracing_gpu/batch_model/FINAL/`

## 4. Proposed Architecture

### 4.1 High-Level Flow
```
Search Request with Semantic Highlighting
    ↓
SemanticHighlightActionFilter (intercepts request)
    ↓
Check use_batch flag (default: false)
    ↓
If use_batch=true:
    ↓
Collect all documents needing highlighting
    ↓
Create BatchHighlightingRequest
    ↓
MLCommonsClientAccessor.inferenceBatchHighlighting()
    ↓
ML Commons processes batch request
    ↓
Return highlighted results
```

### 4.2 Component Changes

#### 4.2.1 Neural Search Plugin Changes

**SemanticHighlightActionFilter.java**
- Remove parallel processing logic
- Implement clean batch collection
- Handle batch/single mode based on use_batch flag

**MLCommonsClientAccessor.java**
- Remove parallel processing fallback
- Implement proper batch inference method
- Support both local and remote models

**BatchHighlightingRequest.java** (new)
- Clean request structure for batch highlighting
- Support variable batch sizes

#### 4.2.2 ML Commons Plugin Changes

**RemoteConnectorExecutor.java**
- Add support for complex parameter types (not just strings)
- Handle batch parameter formatting correctly

**MLInput/MLInputDataSet**
- Create new BatchHighlightingInputDataSet for batch requests
- Support proper serialization of batch data

**Pre/Post Processing Functions**
- Create batch-specific processing functions
- Handle response parsing for batch results

## 5. Implementation Details

### 5.1 Batch Request Format

```java
public class BatchHighlightingRequest {
    private String modelId;
    private List<HighlightingItem> items;
    
    public static class HighlightingItem {
        private String documentId;  // for result correlation
        private String question;
        private String context;
    }
}
```

### 5.2 ML Commons Batch Input Dataset

```java
public class BatchHighlightingInputDataSet extends MLInputDataset {
    private List<Map<String, String>> batch;
    
    @Override
    public void writeTo(StreamOutput out) throws IOException {
        // Serialize as proper JSON array, not string
    }
}
```

### 5.3 Configuration

```json
{
  "highlight": {
    "fields": {
      "content": {
        "type": "semantic"
      }
    },
    "options": {
      "model_id": "model-id-here",
      "use_batch": true,
      "batch_size": 10  // optional, default based on model
    }
  }
}
```

## 6. API Design

### 6.1 Search Request with Batch Highlighting

```json
POST /index/_search
{
  "query": {
    "match": {"content": "symptoms"}
  },
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
      "use_batch": true
    }
  }
}
```

### 6.2 Response Format (unchanged)

```json
{
  "hits": {
    "hits": [{
      "_source": {...},
      "highlight": {
        "content": [
          "The <mark>symptoms include fever</mark> and cough."
        ]
      }
    }]
  }
}
```

## 7. Error Handling

1. **Batch Size Limits**: Automatically split large batches based on model limits
2. **Model Compatibility**: Gracefully fall back to single processing if model doesn't support batch
3. **Partial Failures**: Return results for successful items, log failures

## 8. Testing Strategy

### 8.1 Unit Tests
- Test batch request creation
- Test batch response parsing
- Test error scenarios

### 8.2 Integration Tests
- Test with local models
- Test with remote models
- Test batch size limits
- Test mixed batch/single requests

### 8.3 Performance Tests
- Benchmark batch vs single processing
- Test various batch sizes
- Measure memory usage

## 9. Migration Path

1. **Phase 1**: Implement batch support with use_batch flag (default: false)
2. **Phase 2**: Test and optimize batch processing
3. **Phase 3**: Consider making batch default for compatible models

## 10. Security Considerations

- Batch size limits to prevent DoS
- Authentication/authorization applies to entire batch
- Input validation for all batch items

## 11. Future Enhancements

1. **Dynamic Batching**: Automatically batch requests within a time window
2. **Model-Specific Optimization**: Different batch sizes for different models
3. **Caching**: Cache highlighting results for frequently accessed content
4. **Streaming**: Support streaming batch responses for large result sets

## 12. Success Metrics

1. **Performance**: 5-10x improvement in highlighting latency
2. **Reliability**: No increase in error rates
3. **Adoption**: Smooth migration with backward compatibility
4. **Resource Usage**: Reduced CPU/memory usage per document

## 13. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Model doesn't support batch | High | Implement model capability detection |
| Large batch causes OOM | High | Implement batch size limits |
| Network timeout for large batches | Medium | Implement request timeout configuration |
| Backward compatibility | High | use_batch flag with default false |

## 14. Timeline

1. **Week 1**: Neural Search plugin changes
2. **Week 2**: ML Commons plugin changes
3. **Week 3**: Integration and testing
4. **Week 4**: Documentation and rollout

## 15. Open Questions

1. Should we implement automatic batch size optimization?
2. How to handle very large documents that exceed model context?
3. Should batch processing be configurable per index?