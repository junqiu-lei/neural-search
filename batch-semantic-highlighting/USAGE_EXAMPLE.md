# Batch Semantic Highlighting Usage Example

## Configuration

### 1. Enable Batch Processing in Search Request

```json
POST /medical-documents/_search
{
  "size": 10,
  "query": {
    "match": {
      "content": "What are the symptoms of COVID-19?"
    }
  },
  "highlight": {
    "fields": {
      "content": {
        "type": "semantic",
        "pre_tags": ["<mark>"],
        "post_tags": ["</mark>"],
        "number_of_fragments": 3,
        "fragment_size": 150
      }
    },
    "options": {
      "model_id": "your-highlighting-model-id",
      "use_batch": true,
      "batch_size": 10,
      "batch_timeout_ms": 100
    }
  }
}
```

### 2. Response Example

```json
{
  "took": 45,
  "hits": {
    "total": {
      "value": 3,
      "relation": "eq"
    },
    "hits": [
      {
        "_index": "medical-documents",
        "_id": "1",
        "_score": 0.95,
        "_source": {
          "title": "COVID-19 Overview",
          "content": "COVID-19 is a respiratory illness caused by the SARS-CoV-2 virus. Common symptoms include fever, cough, and shortness of breath. Some patients also experience fatigue, body aches, and loss of taste or smell."
        },
        "highlight": {
          "content": [
            "COVID-19 is a respiratory illness caused by the SARS-CoV-2 virus. <mark>Common symptoms include fever, cough, and shortness of breath.</mark>",
            "<mark>Some patients also experience fatigue, body aches, and loss of taste or smell.</mark>"
          ]
        }
      },
      {
        "_index": "medical-documents",
        "_id": "2",
        "_score": 0.87,
        "_source": {
          "title": "Symptoms and Diagnosis",
          "content": "The symptoms of COVID-19 can range from mild to severe. Most common symptoms are fever, dry cough, and tiredness. Less common symptoms include aches and pains, nasal congestion, headache, conjunctivitis, sore throat, diarrhea, loss of taste or smell."
        },
        "highlight": {
          "content": [
            "<mark>The symptoms of COVID-19 can range from mild to severe.</mark>",
            "<mark>Most common symptoms are fever, dry cough, and tiredness.</mark>"
          ]
        }
      }
    ]
  }
}
```

## Comparison: Batch vs Single Processing

### Single Processing (use_batch: false or not specified)
- Each document's highlighting is processed individually
- Higher latency: ~50-100ms per document
- Sequential processing
- Default behavior for backward compatibility

### Batch Processing (use_batch: true)
- Multiple documents processed in single ML inference call
- Lower latency: ~5-10ms per document
- Parallel processing by the model
- Requires batch-capable model

## Model Requirements

### Batch-Capable Model Input Format
```json
{
  "parameters": {
    "batch": [
      {
        "question": "What are the symptoms of COVID-19?",
        "context": "COVID-19 is a respiratory illness...",
        "documentId": "doc1"
      },
      {
        "question": "What are the symptoms of COVID-19?",
        "context": "The symptoms of COVID-19 can range...",
        "documentId": "doc2"
      }
    ]
  }
}
```

### Model Output Format
```json
{
  "results": [
    {
      "documentId": "doc1",
      "highlights": [
        {"start": 45, "end": 120},
        {"start": 122, "end": 195}
      ]
    },
    {
      "documentId": "doc2",
      "highlights": [
        {"start": 0, "end": 45},
        {"start": 47, "end": 95}
      ]
    }
  ]
}
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model_id` | string | required | The ML model ID for highlighting |
| `use_batch` | boolean | false | Enable batch processing |
| `batch_size` | integer | 10 | Maximum documents per batch |
| `batch_timeout_ms` | integer | 100 | Max wait time for batch collection |

## Performance Considerations

1. **Batch Size**: Larger batches improve throughput but increase latency
2. **Timeout**: Lower timeout reduces wait time but may result in smaller batches
3. **Model Capacity**: Ensure model can handle configured batch size
4. **Memory**: Batch processing uses more memory to collect documents

## Error Handling

### Batch Processing Failures
If batch processing fails, the system will:
1. Log the error with details
2. Fall back to single document processing (if configured)
3. Return partial results if possible

### Partial Failures
When some documents in a batch fail:
1. Successfully processed documents return with highlights
2. Failed documents return without highlights
3. Error details available in logs

## Best Practices

1. **Start Small**: Begin with small batch sizes (5-10) and increase gradually
2. **Monitor Performance**: Track batch processing metrics
3. **Model Testing**: Ensure your model supports batch processing before enabling
4. **Timeout Tuning**: Adjust timeout based on query patterns
5. **Error Monitoring**: Set up alerts for batch processing failures

## Troubleshooting

### Common Issues

1. **No Performance Improvement**
   - Check if model actually supports batch processing
   - Verify batch_size is appropriate
   - Check network latency to model endpoint

2. **Timeouts**
   - Increase batch_timeout_ms
   - Reduce batch_size
   - Check model response time

3. **Memory Issues**
   - Reduce batch_size
   - Monitor heap usage
   - Consider increasing JVM heap size

### Debug Logging

Enable debug logging for batch highlighting:
```
PUT /_cluster/settings
{
  "transient": {
    "logger.org.opensearch.neuralsearch.highlight": "DEBUG"
  }
}
```