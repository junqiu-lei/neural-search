# Neural Search 3.0.0+ Compatibility Guide

## Overview

This document outlines important compatibility considerations for developing features in Neural Search 3.0.0 and later versions, particularly relevant for the batch semantic highlighting implementation.

## Unified ML Client API (Since 3.0.0)

As of Neural Search 3.0.0, the `MLCommonsClientAccessor` provides a **unified API** for both local and remote model inference. This is a significant architectural change that affects how we implement new ML-based features.

### Key Changes

#### 1. Inheritance-based Request Pattern

All inference requests now extend from the `InferenceRequest` base class:

```java
@SuperBuilder
@NoArgsConstructor
@Getter
@Setter
public abstract class InferenceRequest {
    @NonNull
    private String modelId;
    
    @Builder.Default
    private List<String> targetResponseFilters = List.of("sentence_embedding");
}
```

Current implementations include:
- `TextInferenceRequest` - for text embeddings
- `MapInferenceRequest` - for multimodal inputs  
- `SimilarityInferenceRequest` - for text similarity
- `SentenceHighlightingRequest` - for semantic highlighting
- `BatchHighlightingRequest` - for batch highlighting (our new addition)

#### 2. Unified Model ID

The `modelId` field now works seamlessly for:
- **Local models** - Models deployed within the OpenSearch cluster
- **Remote models** - Models accessed via connectors (e.g., SageMaker)

No separate handling is required - the ML Commons framework determines the model type internally.

#### 3. Consistent API Surface

All inference methods in `MLCommonsClientAccessor` follow a consistent pattern:
```java
public void inferenceXXX(
    @NonNull final XXXRequest inferenceRequest,
    @NonNull final ActionListener<Response> listener
)
```

## Implementation Guidelines for Batch Highlighting

### 1. Request Class Structure

Our `BatchHighlightingRequest` correctly extends `InferenceRequest`:
```java
@SuperBuilder
@NoArgsConstructor
@Getter
@Setter
public class BatchHighlightingRequest extends InferenceRequest {
    private List<HighlightingItem> items;
    // ... nested classes
}
```

### 2. MLCommonsClientAccessor Integration

The batch highlighting method should follow the established pattern:
```java
public void inferenceBatchHighlighting(
    @NonNull final BatchHighlightingRequest batchRequest,
    @NonNull final ActionListener<Map<String, List<Map<String, Object>>>> listener
) {
    // Implementation that works with both local and remote models
}
```

### 3. Testing Requirements

Must test with both:
- **Local models**: Deploy model directly in OpenSearch
- **Remote models**: Use connector to SageMaker/other services

## Development Environment Requirements

### JDK Version
- **Baseline**: JDK-21 (required for Neural Search 3.0.0+)
- Previous versions used JDK-11/17

### OpenSearch Compatibility
- Neural Search 3.0.0 → OpenSearch 3.0.0
- Neural Search 3.1.0 → OpenSearch 3.1.0

### Key Features Introduced in 3.0.0
1. **Semantic sentence highlighter** - Base feature we're extending
2. **Unified ML client** - Single API for all model types
3. **Semantic field mapper** - New field type for semantic search
4. **Stats API** - Monitoring and metrics
5. **Z-Score normalization** - Additional scoring option
6. **Filter support** - For hybrid and neural queries

## Backward Compatibility Considerations

1. **API Compatibility**: New features should not break existing APIs
2. **Model Compatibility**: Support both pre-3.0.0 and 3.0.0+ model formats
3. **Configuration**: Default values should maintain existing behavior

## Code Refactoring Context

The unified API was introduced via:
- **Commit**: `ebfb058` - "code refactoring on MLCommonsClientAccessor request"
- **Impact**: All processor and query builder classes updated
- **Pattern**: Inheritance-based request objects replacing individual parameters

## Best Practices

1. **Always extend InferenceRequest** for new ML request types
2. **Use @SuperBuilder** for constructor flexibility
3. **Include @NonNull validation** where appropriate
4. **Follow existing naming conventions** (e.g., `inferenceXXX` methods)
5. **Implement retry logic** using `RetryUtil.handleRetryOrFailure`
6. **Support both sync and async patterns** via ActionListener

## Migration Path for Batch Highlighting

Given the 3.0.0 architecture:

1. ✅ **Request Class**: Already follows the pattern
2. ⚠️ **ML Commons Integration**: Need to ensure BatchHighlightingInputDataSet works with unified client
3. ⚠️ **Testing**: Must validate with both local and remote models
4. ✅ **API Design**: Follows established conventions

## References

- Release Notes: `/release-notes/opensearch-neural-search.release-notes-3.0.0.0.md`
- Refactoring Commit: `ebfb058387e6e901355aef4106f358fcae77e961`
- JDK-21 Baseline: Issue #838

---

This compatibility guide should be considered when implementing any new ML-based features in Neural Search 3.0.0+.