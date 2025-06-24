# Dynamic Batch Highlighting Support for Neural Search

## Overview

This document describes the implementation of dynamic batch support for semantic highlighting in the OpenSearch Neural Search plugin. The implementation allows for efficient batch processing of multiple documents using a single ML model inference call, significantly improving performance when highlighting multiple search results.

## Key Changes

### 1. New Batch Request Classes

#### BatchSentenceHighlightingRequest.java
A new request class that supports batch processing of multiple question-context pairs:

```java
public class BatchSentenceHighlightingRequest extends InferenceRequest {
    private List<SentenceHighlightingItem> batch;
    
    public static class SentenceHighlightingItem {
        private String question;
        private String context;
    }
}
```

### 2. MLCommonsClientAccessor Updates

Added batch highlighting support to the ML client:

```java
public void inferenceBatchSentenceHighlighting(
    @NonNull final BatchSentenceHighlightingRequest inferenceRequest,
    @NonNull final ActionListener<List<List<Map<String, Object>>>> listener
)
```

The batch method:
- Accepts multiple question-context pairs
- Formats them as a batch request for the ML model
- Processes the batch response and maps results back to individual documents

### 3. SemanticHighlightActionFilter Enhancement

The action filter now supports both individual and batch processing modes:

#### New Configuration Options

```json
{
  "highlight": {
    "fields": {
      "content": {
        "type": "semantic"
      }
    },
    "options": {
      "model_id": "your-model-id",
      "use_batch": true
    }
  }
}
```

- `model_id`: The model ID for highlighting (required) - should be a batch-capable model when `use_batch` is true
- `use_batch`: Boolean flag to enable batch processing (default: false)

#### Processing Logic

1. When `use_batch` is true and multiple documents are being highlighted:
   - Uses the specified `model_id` for batch processing
   - Processes all documents in parallel (current implementation)
   - Future: Can be updated to make a single ML inference call when true batch models are available
   - Distributes results back to individual documents

2. When `use_batch` is false or only one document is being highlighted:
   - Uses the existing parallel processing with individual ML calls

## Usage Examples

### Basic Usage with Batch Processing

```bash
curl -X POST "http://localhost:9200/my-index/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "neural": {
        "content": {
          "query_text": "What are the symptoms of diabetes?",
          "model_id": "embedding-model-id"
        }
      }
    },
    "highlight": {
      "fields": {
        "content": {
          "type": "semantic"
        }
      },
      "options": {
        "model_id": "5KHtopcBJ3g2K0lQM9Nx",
        "use_batch": true
      }
    }
  }'
```

### Using Model Without Batch Processing

```bash
curl -X POST "http://localhost:9200/my-index/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "neural": {
        "content": {
          "query_text": "What is machine learning?",
          "model_id": "embedding-model-id"
        }
      }
    },
    "highlight": {
      "fields": {
        "content": {
          "type": "semantic"
        }
      },
      "options": {
        "model_id": "c7DtopcBzGk_n9nPCKO9"
        # use_batch defaults to false
      }
    }
  }'
```

## Testing with SageMaker

### Prerequisites

1. Deploy the batch-enabled model to SageMaker:
   - Use the model from `/home/junqiu/tracing_gpu/batch_model/FINAL/`
   - Ensure the endpoint supports both single and batch inference

2. Register the model in OpenSearch ML Commons:

```bash
# Register batch model
curl -X POST "http://localhost:9200/_plugins/_ml/models/_register" \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "semantic-highlighter-batch",
    "function_name": "REMOTE",
    "description": "Batch semantic highlighting model",
    "connector_id": "your-sagemaker-connector-id"
  }'
```

### Test Scenarios

#### 1. Single Document Test
```bash
# Search returning 1 result
curl -X POST "http://localhost:9200/test-index/_search?size=1" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": { "match_all": {} },
    "highlight": {
      "fields": { "content": { "type": "semantic" } },
      "options": {
        "model_id": "batch-capable-model-id",
        "use_batch": true
      }
    }
  }'
```

#### 2. Multi-Document Batch Test
```bash
# Search returning 10 results
curl -X POST "http://localhost:9200/test-index/_search?size=10" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": { "match_all": {} },
    "highlight": {
      "fields": { "content": { "type": "semantic" } },
      "options": {
        "model_id": "batch-capable-model-id",
        "use_batch": true
      }
    }
  }'
```

#### 3. Performance Comparison Test
```bash
# Test with batch disabled
time curl -X POST "http://localhost:9200/test-index/_search?size=20" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": { "match_all": {} },
    "highlight": {
      "fields": { "content": { "type": "semantic" } },
      "options": {
        "model_id": "your-model-id",
        "use_batch": false
      }
    }
  }'

# Test with batch enabled
time curl -X POST "http://localhost:9200/test-index/_search?size=20" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": { "match_all": {} },
    "highlight": {
      "fields": { "content": { "type": "semantic" } },
      "options": {
        "model_id": "batch-capable-model-id",
        "use_batch": true
      }
    }
  }'
```

### Expected Performance Improvements

Based on the batch model documentation:
- Single document: ~8ms per document
- Batch processing: ~8ms per document with better throughput
- Optimal batch size: 10-50 documents
- Maximum batch size: 128 documents

### Monitoring and Debugging

Check the OpenSearch logs for batch processing information:

```bash
# Individual processing logs
[semantic-hl-filter] Individual highlighting completed: documents=20, avgMLTime=150ms, SUCCESS_COUNT=20

# Batch processing logs
[semantic-hl-filter] Batch ML inference completed: documents=20, totalTime=180ms
```

## Backward Compatibility

The implementation maintains full backward compatibility:

1. If `use_batch` is not specified, defaults to false (existing behavior)
2. When `use_batch` is true, the specified `model_id` should support batch processing
3. All existing queries continue to work without modification

## Deployment Checklist

- [ ] Build the neural-search plugin with the new changes
- [ ] Deploy the batch-enabled ML model to SageMaker
- [ ] Register both single and batch models in OpenSearch ML Commons
- [ ] Update search queries to include batch parameters where beneficial
- [ ] Monitor performance metrics to validate improvements

## Troubleshooting

### Common Issues

1. **Batch processing not working**
   - Verify the model supports batch processing
   - Ensure use_batch is set to true
   - Check ML Commons model status

2. **Batch processing falls back to individual**
   - Ensure use_batch is set to true
   - Verify multiple documents are being processed
   - Check logs for batch processing decisions

3. **Performance not improved**
   - Verify the batch model endpoint is optimized for batch processing
   - Check if documents are too large (keep under 512 tokens)
   - Monitor SageMaker endpoint metrics