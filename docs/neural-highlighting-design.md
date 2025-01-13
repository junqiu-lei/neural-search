# Neural Highlighting Design Document

## Introduction
This document outlines the design and implementation of neural highlighting feature in OpenSearch. Neural highlighting aims to enhance search result highlighting by leveraging machine learning models to identify semantically relevant text fragments, going beyond traditional lexical matching approaches. This document serves as a comprehensive guide for implementing and maintaining the neural highlighting feature.

## Problem Statement

### What is the problem being solved?
Traditional highlighting in OpenSearch relies on lexical matching, which fails to capture semantically relevant content when exact keywords aren't present. This leads to missed relevant highlights and suboptimal search experience.

### Why this needs to be solved?
- Improved search result relevance through semantic understanding
- Better user experience with contextually appropriate highlights
- Support for modern search use cases requiring semantic understanding
- Competitive advantage in search technology landscape

### Impact of not doing this project
- Limited highlighting capabilities compared to competitors
- Reduced search result quality for semantic search scenarios
- Missed opportunities in domains requiring semantic understanding
- Technical debt in maintaining only lexical-based highlighting

### Competitive Analysis

#### Elasticsearch
- Currently does not have native neural highlighting
- Offers traditional highlighting methods (unified, plain, fast vector highlighter)
- Community has developed custom solutions using scripts and plugins

#### Azure Cognitive Search
- Offers semantic search with semantic highlighting (preview)
- Uses deep learning models for semantic ranking and highlighting
- Limited to English language content
- Proprietary implementation

#### Google Cloud Search
- Enterprise search with ML-powered highlighting
- Uses BERT-based models for semantic understanding
- Closed source, proprietary implementation
- Limited customization options

#### Vespa.ai
- Open source search engine
- Supports neural ranking and highlighting
- Uses BERT embeddings for semantic matching
- Requires significant infrastructure setup

#### Amazon Kendra
- Enterprise search service with semantic capabilities
- Uses ML for intelligent highlighting
- Closed source, proprietary implementation
- Limited to enterprise use cases

This analysis shows that while some competitors offer neural/semantic highlighting capabilities, they are either:
1. Closed source and proprietary (Azure, Google, Amazon)
2. Require complex setup (Vespa.ai)
3. Limited in scope or language support
4. Not available in the open source search ecosystem

OpenSearch has the opportunity to become the first major open source search engine to offer native, easy-to-use neural highlighting capabilities.

### Primary users/clients
- OpenSearch users requiring semantic search capabilities
- Enterprise search applications
- Technical documentation platforms
- Research and academic search systems

### Timeline
Target for OpenSearch 3.0 release

## Use Cases

### Required Use Cases
1. **Semantic Search Result Highlighting**
   - Highlight semantically relevant passages even without exact keyword matches
   - Support concept-based search highlighting
   - [GitHub Issue #1234]

2. **Domain-Specific Search Highlighting**
   - Medical document search with domain-specific terminology
   - Technical documentation search with context awareness
   - [GitHub Issue #1235]

3. **Long Document Highlighting**
   - Identify relevant passages in long-form content
   - Support multi-paragraph context understanding
   - [GitHub Issue #1236]

### Nice to Have Use Cases
1. **Multi-language Support**
   - Highlight semantically relevant content across languages
   - [GitHub Issue #1237]

2. **Custom Model Integration**
   - Support for user-provided embedding models
   - [GitHub Issue #1238]

### Negative Use Cases
- No change in behavior for traditional keyword highlighting
- No impact on existing highlighter implementations
- No automatic model selection or training

## Requirements

### Functional Requirements
1. **Neural Highlighting Integration**
   - Implement new "neural" highlighter type
   - Support configuration through search request options
   - Enable model specification in highlight requests
   - Support multiple field types (text, keyword, nested fields)

2. **Model Integration**
   - Integration with ML Commons for model inference
   - Support for embedding model loading and management
   - Caching mechanism for computed embeddings
   - Field type-specific preprocessing for embeddings

3. **Fragment Management**
   - Configurable fragment size and count
   - Score-based fragment selection
   - Customizable highlighting tags
   - Type-specific fragment generation strategies

4. **Error Handling**
   - Graceful fallback to traditional highlighting
   - Clear error messages for debugging
   - Recovery mechanisms for model failures
   - Type-specific error handling and validation

### Non-Functional Requirements
1. **Performance**
   - Highlighting latency < 500ms for typical documents
   - Cache hit ratio > 80% for repeated queries
   - Memory usage < 1GB for embedding cache

2. **Scalability**
   - Support for concurrent highlighting requests
   - Efficient resource utilization
   - Linear scaling with document size

3. **Reliability**
   - 99.9% availability for highlighting requests
   - Zero data loss during highlighting
   - Consistent behavior across cluster nodes

4. **Maintainability**
   - Clear code organization and documentation
   - Comprehensive test coverage
   - Monitoring and debugging capabilities

## Out of Scope
1. Real-time model training or fine-tuning
2. Image or multi-modal highlighting
3. Automatic model selection or optimization
4. Custom model architecture development
5. Cross-cluster highlighting synchronization
6. Real-time model updates

## Current State
The current highlighting system in OpenSearch:
1. Supports multiple highlighter types (unified, plain, fvh)
2. Uses lexical matching for highlight selection
3. Lacks semantic understanding capabilities
4. Has no integration with ML models

## Solution Overview
The neural highlighting solution introduces semantic understanding to OpenSearch's highlighting capabilities through:

### Key Components
1. Neural Highlighter implementation
2. ML Commons integration for model inference
3. Embedding cache for performance optimization
4. Fragment selection based on semantic similarity

### Technologies Used
- OpenSearch ML Commons
- Sentence Transformer Models
- LRU Cache implementation
- Vector similarity calculations

## Solution HLD: Architectural and Component Design

### Proposed Solution
```
[Search Request]
      ↓
[Neural Highlighter]
      ↓
[Document Processing] → [Fragment Generation]
      ↓
[ML Commons] ← → [Model Inference] → [Embedding Cache]
      ↓
[Similarity Scoring]
      ↓
[Fragment Selection]
      ↓
[Highlight Generation]
      ↓
[Search Response]
```

#### Component Details

1. **Neural Highlighter**
   - Implements OpenSearch Highlighter interface
   - Manages highlighting workflow
   - Handles configuration and options

2. **ML Commons Integration**
   - Model management and inference
   - Embedding computation
   - Model lifecycle handling

3. **Embedding Cache**
   - LRU cache implementation
   - Time-based expiration
   - Thread-safe operations

4. **Fragment Manager**
   - Text chunking logic
   - Fragment scoring
   - Best fragment selection

### Alternatives Considered

#### Alternative 1: Client-Side Neural Highlighting
Pros:
- Reduced server load
- Client flexibility in model selection
- Easier scaling

Cons:
- Increased network traffic
- Inconsistent highlighting
- Complex client implementation
- Limited model availability

#### Alternative 2: Dedicated Highlighting Service
Pros:
- Better resource isolation
- Independent scaling
- Simplified maintenance

Cons:
- Additional infrastructure
- Increased operational complexity
- Higher latency
- More failure points

### Solution Comparison

| Aspect | Proposed Solution | Client-Side | Dedicated Service |
|--------|------------------|-------------|-------------------|
| Latency | Low | High | Medium |
| Resource Usage | Medium | Low | High |
| Maintainability | High | Low | Medium |
| Scalability | Good | Excellent | Excellent |
| Complexity | Medium | High | High |

### Key Design Decisions

1. **Embedding Cache Implementation**
   - Decision: Use time-based LRU cache
   - Rationale: Balance between memory usage and performance
   - Impact: Improved response times for repeated queries

2. **Model Integration**
   - Decision: Use ML Commons for model management
   - Rationale: Leverage existing infrastructure
   - Impact: Simplified deployment and maintenance

3. **Fragment Selection**
   - Decision: Score-based selection with configurable threshold
   - Rationale: Balance between relevance and performance
   - Impact: Better highlight quality

### Open Questions
1. How to handle very large documents efficiently?
2. What's the optimal cache size and expiration policy?
3. How to handle model version updates?

### Implementation Phases

#### Phase 1 (Short Term)
- Basic neural highlighting implementation
- ML Commons integration
- Simple caching mechanism

#### Phase 2 (Mid Term)
- Advanced caching strategies
- Performance optimizations
- Monitoring and metrics

#### Phase 3 (Long Term)
- Multi-model support
- Advanced configuration options
- Custom model integration

## Metrics

### Health Metrics
1. Highlighting latency (p50, p90, p99)
2. Cache hit ratio
3. Model inference time
4. Memory usage

### Failure Metrics
1. Model inference failures
2. Cache eviction rate
3. Highlighting timeout rate
4. Error response rate

### Count Metrics
1. Highlighting requests per second
2. Cache size
3. Average fragment count
4. Model usage statistics

## Solution LLD

### Core Classes

```java
public class NeuralHighlighter implements Highlighter {
    private static volatile MLCommonsClientAccessor mlCommonsClient;
    private final Cache<String, List<List<Float>>> embeddingCache;
    private final Map<String, FieldTypeProcessor> fieldTypeProcessors;
    
    // Core methods
    public HighlightField highlight(FieldHighlightContext context);
    private List<String> splitIntoChunks(String text, int fragmentSize);
    private List<Float> computeEmbeddings(String modelId, String text);
    private float computeSimilarity(List<Float> vec1, List<Float> vec2);
    
    // Field type support
    private interface FieldTypeProcessor {
        String preprocess(Object fieldValue);
        List<String> generateFragments(Object fieldValue, int fragmentSize);
        String formatHighlight(String fragment, String preTag, String postTag);
    }
    
    private class TextFieldProcessor implements FieldTypeProcessor {
        // Implementation for text fields
    }
    
    private class KeywordFieldProcessor implements FieldTypeProcessor {
        // Implementation for keyword fields
        // Treats entire field value as a single fragment
    }
    
    private class NestedFieldProcessor implements FieldTypeProcessor {
        // Implementation for nested fields
        // Handles nested document structure
    }
}

public class FragmentManager {
    private final Map<String, FragmentStrategy> fragmentStrategies;
    
    public interface FragmentStrategy {
        List<TextFragment> createFragments(Object fieldValue, int fragmentSize);
    }
    
    public List<TextFragment> createFragments(String fieldType, Object fieldValue, int fragmentSize) {
        return fragmentStrategies.get(fieldType).createFragments(fieldValue, fragmentSize);
    }
    
    public List<ScoredFragment> scoreFragments(
        List<TextFragment> fragments, 
        List<Float> queryEmbedding
    );
    
    public List<String> selectBestFragments(
        List<ScoredFragment> fragments, 
        float minScore
    );
}

public class EmbeddingCache {
    private final Cache<String, List<List<Float>>> cache;
    
    public List<List<Float>> getOrCompute(
        String key, 
        Supplier<List<List<Float>>> computer
    );
    public void invalidate(String key);
}
```

### API Schema

```json
{
  "highlight": {
    "fields": {
      "text_field": {
        "type": "neural",
        "options": {
          "model": "model_id",
          "min_score": 0.5,
          "fragment_size": 150,
          "number_of_fragments": 3
        }
      },
      "keyword_field": {
        "type": "neural",
        "options": {
          "model": "model_id",
          "min_score": 0.5,
          "whole_field_mode": true
        }
      },
      "nested_field": {
        "type": "neural",
        "options": {
          "model": "model_id",
          "min_score": 0.5,
          "fragment_size": 150,
          "number_of_fragments": 3,
          "nested_path": "path.to.nested"
        }
      }
    }
  }
}
```

### Supported Field Types

1. **Text Fields**
   - Standard text analysis and tokenization
   - Configurable fragment size and count
   - Full text preprocessing support

2. **Keyword Fields**
   - Whole field highlighting
   - No fragmentation
   - Exact value matching

3. **Nested Fields**
   - Support for nested document structures
   - Path-aware highlighting
   - Nested context preservation

4. **Future Extensions**
   - Geo fields for location-aware highlighting
   - Numeric fields with range-based highlighting
   - Custom field types through plugin system

## Backward Compatibility
1. New highlighting type doesn't affect existing highlighters
2. Optional parameters maintain backward compatibility
3. Default fallback to traditional highlighting on errors
4. No breaking changes to existing APIs
5. Existing highlighting configurations remain unchanged

## Security
1. Model access control through ML Commons
2. Resource limits for highlighting requests
3. Input validation for all parameters
4. Secure caching implementation

## Testability

### Unit Tests
1. Highlighter implementation tests
2. Fragment management tests
3. Cache behavior tests
4. Error handling tests
5. Field type processor tests
6. Type-specific highlighting tests

### Integration Tests
1. End-to-end highlighting workflow
2. Model integration tests
3. Performance tests
4. Concurrent request handling
5. Cross-field type highlighting tests
6. Nested document highlighting tests

### Performance Testing
1. Latency benchmarks
2. Memory usage monitoring
3. Cache effectiveness tests
4. Stress testing

## Benchmarking

### Test Scenarios
1. Document sizes: 1KB to 10MB
2. Concurrent requests: 1 to 100
3. Cache sizes: 100MB to 1GB
4. Various fragment configurations

### Metrics to Measure
1. Response time
2. Memory usage
3. CPU utilization
4. Cache hit rates

### Exit Criteria
1. P99 latency < 500ms
2. Memory usage < 1GB
3. Cache hit ratio > 80%
4. Error rate < 0.1%

### Benchmark Results
Will be published on GitHub as part of PR review process. 