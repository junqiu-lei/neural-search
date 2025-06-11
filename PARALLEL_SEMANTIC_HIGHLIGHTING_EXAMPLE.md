# Parallel Semantic Highlighting Example

This example demonstrates how to use the parallel semantic highlighting feature in OpenSearch Neural Search.

## Prerequisites

1. OpenSearch cluster with Neural Search plugin installed
2. A deployed ML model for semantic highlighting
3. An index with documents to search

## Configuration

### 1. Set the Parallelism Level

Configure the parallelism level for semantic highlighting using the cluster settings API:

```json
PUT /_cluster/settings
{
  "persistent": {
    "plugins.neural_search.highlight.parallelism_level": 8
  }
}
```

The default value is the number of available processors. You can adjust this based on your cluster's resources and workload.

### 2. Create an Index with Sample Data

```json
PUT /my-documents
{
  "mappings": {
    "properties": {
      "title": {
        "type": "text"
      },
      "content": {
        "type": "text"
      }
    }
  }
}

POST /my-documents/_bulk
{ "index": {} }
{ "title": "Introduction to Machine Learning", "content": "Machine learning is a subset of artificial intelligence that enables systems to learn and improve from experience without being explicitly programmed. It focuses on developing computer programs that can access data and use it to learn for themselves." }
{ "index": {} }
{ "title": "Deep Learning Fundamentals", "content": "Deep learning is a subset of machine learning that uses neural networks with multiple layers. These neural networks attempt to simulate the behavior of the human brain, allowing it to learn from large amounts of data." }
{ "index": {} }
{ "title": "Natural Language Processing", "content": "Natural language processing (NLP) is a branch of artificial intelligence that helps computers understand, interpret and manipulate human language. NLP draws from many disciplines, including computer science and computational linguistics." }
```

## Using Semantic Highlighting

### Search with Semantic Highlighting

```json
POST /my-documents/_search
{
  "query": {
    "match": {
      "content": "artificial intelligence"
    }
  },
  "highlight": {
    "fields": {
      "content": {
        "type": "semantic",
        "pre_tags": ["<strong>"],
        "post_tags": ["</strong>"]
      }
    },
    "options": {
      "model_id": "your-semantic-highlighting-model-id"
    }
  }
}
```

### Expected Response

```json
{
  "took": 150,
  "timed_out": false,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 3,
      "relation": "eq"
    },
    "max_score": 0.8,
    "hits": [
      {
        "_index": "my-documents",
        "_id": "1",
        "_score": 0.8,
        "_source": {
          "title": "Introduction to Machine Learning",
          "content": "Machine learning is a subset of artificial intelligence that enables systems to learn and improve from experience without being explicitly programmed. It focuses on developing computer programs that can access data and use it to learn for themselves."
        },
        "highlight": {
          "content": [
            "Machine learning is a subset of <strong>artificial intelligence</strong> that enables systems to learn and improve from experience without being explicitly programmed. It focuses on developing computer programs that can access data and use it to learn for themselves."
          ]
        }
      },
      {
        "_index": "my-documents",
        "_id": "3",
        "_score": 0.75,
        "_source": {
          "title": "Natural Language Processing",
          "content": "Natural language processing (NLP) is a branch of artificial intelligence that helps computers understand, interpret and manipulate human language. NLP draws from many disciplines, including computer science and computational linguistics."
        },
        "highlight": {
          "content": [
            "Natural language processing (NLP) is a branch of <strong>artificial intelligence</strong> that helps computers understand, interpret and manipulate human language. NLP draws from many disciplines, including computer science and computational linguistics."
          ]
        }
      }
    ]
  }
}
```

## Performance Benefits

With parallel semantic highlighting:

1. **Improved Latency**: When searching returns multiple documents (e.g., 50 hits), the highlighting inference calls are executed in parallel rather than sequentially.
2. **Configurable Parallelism**: Administrators can tune the `parallelism_level` based on their cluster's capacity.
3. **Automatic Processing**: The parallel processing happens automatically when semantic highlighting is requested - no changes to queries are needed.

## Monitoring

You can monitor the performance of semantic highlighting using the Neural Search stats API:

```json
GET /_plugins/_neural/stats
```

This will show statistics including the number of semantic highlighting requests processed.

## Best Practices

1. **Set Appropriate Parallelism**: Start with the default (number of processors) and adjust based on monitoring.
2. **Monitor Resource Usage**: Higher parallelism levels consume more CPU and memory.
3. **Use with Large Result Sets**: The benefits are most noticeable when highlighting many documents.
4. **Model Performance**: Ensure your semantic highlighting model is optimized for inference speed.

## Troubleshooting

If highlighting is not working as expected:

1. Check that the model is deployed and accessible
2. Verify the parallelism level setting
3. Check the OpenSearch logs for any errors
4. Ensure the `semantic` highlighter type is specified in the query