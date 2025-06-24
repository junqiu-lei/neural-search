# Batch Semantic Highlighting Design Document

## 1. Overview

This document outlines the design for implementing batch semantic highlighting in OpenSearch, which allows processing multiple documents in a single ML model inference call for improved performance.

### 1.1 Document Structure
- **Section 1-3**: Background and current state
- **Section 4-6**: Proposed architecture and implementation
- **Section 7-9**: API design and error handling
- **Section 10-12**: Testing, migration, and security
- **Section 13-15**: Future work and appendices

## 2. Goals

1. **Performance**: Reduce latency by processing multiple documents in a single model inference call
2. **Compatibility**: Support both batch and single-document processing with backward compatibility
3. **Flexibility**: Support both remote (SageMaker) and local ML models
4. **Clean Architecture**: Remove parallel processing complexity in favor of true batch processing
5. **Scalability**: Support configurable batch sizes (1-128+ documents)

## 3. Current State Analysis

### 3.1 Existing Implementation Issues
- Current implementation uses parallel processing as a fallback when batch fails
- ML Commons sends parameters as JSON strings, but SageMaker expects JSON objects
- Parameter format mismatch: `{"batch": "[{...}]"}` vs `{"parameters": {"batch": [{...}]}}`

### 3.2 Performance Benchmarks  
- Single document processing: ~50-100ms per document
- Batch processing (verified with production models): ~8ms per document
- Actual improvement: 6-12x faster with batch processing

### 3.3 Production Models

#### Deployed Models
| Model Type | Model ID | Max Batch Size | Performance |
|------------|----------|----------------|-------------|
| Single Document | `c7DtopcBzGk_n9nPCKO9` | 1 | ~50-100ms |
| Batch Processing | `5KHtopcBJ3g2K0lQM9Nx` | 128 (configurable) | ~8ms per doc |

#### Model Capabilities
- **Architecture**: BERT-based (`bert-base-uncased`)
- **Dynamic Batching**: Supports 1-128 documents without recompilation
- **Batch Size**: Configurable limit (default 128, can be increased)
- **Location**: `/home/junqiu/tracing_gpu/batch_model/FINAL/`
- **Deployment**: SageMaker endpoint (ml.g4dn.xlarge)

## 4. Proposed Architecture

### 4.1 High-Level Flow

```mermaid
flowchart TD
    A[Search Request with Semantic Highlighting] --> B{Check Highlight Type}
    B -->|type=semantic| C[SemanticHighlighter]
    B -->|other| D[Standard Highlighter]
    
    C --> E{Check use_batch flag}
    E -->|false<br/>default| F[Single Document Processing]
    E -->|true| G[Batch Document Collection]
    
    F --> H[SentenceHighlightingRequest]
    G --> I[BatchHighlightingRequest]
    
    H --> J[MLCommonsClientAccessor<br/>inferenceSentenceHighlighting]
    I --> K[MLCommonsClientAccessor<br/>inferenceBatchHighlighting]
    
    J --> L{Model Type}
    K --> L
    
    L -->|Local| M[Local Model Inference]
    L -->|Remote| N[Remote Model Inference<br/>via Connector]
    
    M --> O[Process Results]
    N --> O
    
    O --> P[Apply Highlighting Tags]
    P --> Q[Return Highlighted Results]
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

### 5.1 Class Hierarchy (Neural Search 3.0.0+)

```mermaid
classDiagram
    class InferenceRequest {
        <<abstract>>
        -String modelId
        -List~String~ targetResponseFilters
    }
    
    class SentenceHighlightingRequest {
        -String question
        -String context
    }
    
    class BatchHighlightingRequest {
        -List~HighlightingItem~ items
    }
    
    class HighlightingItem {
        -String documentId
        -String question  
        -String context
    }
    
    class TextInferenceRequest {
        -List~String~ inputTexts
    }
    
    class MapInferenceRequest {
        -Map~String,String~ inputObjects
    }
    
    InferenceRequest <|-- SentenceHighlightingRequest
    InferenceRequest <|-- BatchHighlightingRequest
    InferenceRequest <|-- TextInferenceRequest
    InferenceRequest <|-- MapInferenceRequest
    
    BatchHighlightingRequest *-- HighlightingItem
```

### 5.2 Batch Request Format

```java
@SuperBuilder
@NoArgsConstructor
@Getter
@Setter
public class BatchHighlightingRequest extends InferenceRequest {
    private List<HighlightingItem> items;
    
    @Builder
    @AllArgsConstructor
    @NoArgsConstructor
    @Getter
    @Setter
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

### 5.3 Batch Processing Sequence

```mermaid
sequenceDiagram
    participant Client
    participant OpenSearch
    participant SemanticHighlighter
    participant MLCommonsClient
    participant Model
    
    Client->>OpenSearch: Search Request<br/>with use_batch=true
    OpenSearch->>SemanticHighlighter: Process highlights<br/>for N documents
    
    Note over SemanticHighlighter: Collect documents<br/>into batches
    
    SemanticHighlighter->>MLCommonsClient: BatchHighlightingRequest<br/>(items: [{q1,c1}, {q2,c2}, ...])
    
    MLCommonsClient->>Model: Batch Inference<br/>(up to 128 docs)
    
    Model-->>MLCommonsClient: Batch Results<br/>[{highlights1}, {highlights2}, ...]
    
    MLCommonsClient-->>SemanticHighlighter: Map<docId, highlights>
    
    SemanticHighlighter-->>OpenSearch: Highlighted documents
    OpenSearch-->>Client: Search response<br/>with highlights
```

### 5.4 Configuration

```json
{
  "highlight": {
    "fields": {
      "content": {
        "type": "semantic"
      }
    },
    "options": {
      "model_id": "5KHtopcBJ3g2K0lQM9Nx",  // Batch model ID
      "use_batch": true,
      "batch_size": 50,      // optional, default 10, max 128
      "batch_timeout_ms": 100 // optional, collection timeout
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

## 7. Batch Collection Strategy

```mermaid
stateDiagram-v2
    [*] --> Idle
    
    Idle --> Collecting: First document arrives<br/>with use_batch=true
    
    Collecting --> Collecting: Add document<br/>(size < batch_size)
    
    Collecting --> ProcessBatch: Batch full<br/>(size = batch_size)
    Collecting --> ProcessBatch: Timeout reached<br/>(batch_timeout_ms)
    Collecting --> ProcessBatch: Last document<br/>in search results
    
    ProcessBatch --> SendToModel: Create BatchHighlightingRequest
    
    SendToModel --> Success: Model returns results
    SendToModel --> Failure: Model error
    
    Success --> ApplyHighlights: Map results to documents
    Failure --> FallbackSingle: Process individually
    
    ApplyHighlights --> Idle: Complete
    FallbackSingle --> Idle: Complete
```

## 8. Error Handling

1. **Batch Size Limits**: Automatically split large batches based on model limits (max 128)
2. **Model Compatibility**: Gracefully fall back to single processing if model doesn't support batch
3. **Partial Failures**: Return results for successful items, log failures
4. **Timeout Handling**: Process partial batch if timeout is reached

## 9. Testing Strategy

### 9.1 Unit Tests
- Test batch request creation
- Test batch response parsing
- Test error scenarios

### 9.2 Integration Tests
- Test with local models
- Test with remote models (including deployed models)
- Test batch size limits (1-128 documents)
- Test mixed batch/single requests

### 9.3 Performance Tests
- Benchmark batch vs single processing
- Test various batch sizes (1, 10, 50, 100, 128)
- Measure memory usage
- Validate ~8ms per document performance

## 10. Migration Path

1. **Phase 1**: Implement batch support with use_batch flag (default: false)
2. **Phase 2**: Test with production models (`5KHtopcBJ3g2K0lQM9Nx`)
3. **Phase 3**: Optimize batch sizes based on workload
4. **Phase 4**: Consider making batch default for compatible models

## 11. Security Considerations

- Batch size limits to prevent DoS (configurable, default 128)
- Authentication/authorization applies to entire batch
- Input validation for all batch items
- Memory limits for batch collection

## 12. Future Enhancements

1. **Dynamic Batching**: Automatically batch requests within a time window
2. **Model-Specific Optimization**: Different batch sizes for different models
3. **Caching**: Cache highlighting results for frequently accessed content
4. **Streaming**: Support streaming batch responses for large result sets
5. **Adaptive Batch Sizing**: Adjust batch size based on system load

## 13. Success Metrics

1. **Performance**: 6-12x improvement in highlighting latency (verified: ~8ms per document)
2. **Reliability**: No increase in error rates
3. **Adoption**: Smooth migration with backward compatibility
4. **Resource Usage**: Reduced CPU/memory usage per document
5. **Scalability**: Support for configurable batch sizes up to 128+ documents

## 14. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Model doesn't support batch | High | Implement model capability detection |
| Large batch causes OOM | High | Implement batch size limits |
| Network timeout for large batches | Medium | Implement request timeout configuration |
| Backward compatibility | High | use_batch flag with default false |

## 15. Timeline

1. **Week 1**: Neural Search plugin changes
2. **Week 2**: ML Commons plugin changes (if needed)
3. **Week 3**: Integration and testing with production models
4. **Week 4**: Documentation and rollout

## 16. Open Questions

1. Should we implement automatic batch size optimization?
2. How to handle very large documents that exceed model context?
3. Should batch processing be configurable per index?
4. Should the 128 document limit be user-configurable?

## 17. Appendix: Production Model Details

### Model Endpoints
- **Base URL**: `http://opense-clust-nIQATX97fqm6-8bdfbdc697bcfcd5.elb.us-east-2.amazonaws.com`
- **Single API**: `/_plugins/_ml/models/c7DtopcBzGk_n9nPCKO9/_predict`
- **Batch API**: `/_plugins/_ml/models/5KHtopcBJ3g2K0lQM9Nx/_predict`

### Model Performance Characteristics
```mermaid
graph LR
    subgraph "Single Document Model"
        A[1 doc] -->|50-100ms| B[Result]
    end
    
    subgraph "Batch Model (Dynamic)"
        C[1 doc] -->|~8ms| D[Result]
        E[10 docs] -->|~80ms| F[Results]
        G[50 docs] -->|~400ms| H[Results]
        I[128 docs] -->|~1024ms| J[Results]
    end
```

### Configuration Options
| Parameter | Default | Min | Max | Description |
|-----------|---------|-----|-----|-------------|
| `use_batch` | false | - | - | Enable batch processing |
| `batch_size` | 10 | 1 | 128* | Documents per batch |
| `batch_timeout_ms` | 100 | 10 | 5000 | Collection timeout |

*Note: 128 is the current model limit but is configurable in the model deployment