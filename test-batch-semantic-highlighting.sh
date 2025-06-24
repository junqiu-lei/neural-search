#!/bin/bash
# Script to test batch semantic highlighting with keywords query

OPENSEARCH_HOST="localhost"
OPENSEARCH_PORT="9200"

# Read the model ID from file
if [ -f "model_id.txt" ]; then
    MODEL_ID=$(cat model_id.txt)
else
    echo "Error: model_id.txt not found. Please run create-working-batch-connector.sh first."
    exit 1
fi

echo "Using model ID: $MODEL_ID"
echo ""

# First, create a test index with semantic highlighting enabled
echo "Creating test index with semantic highlighting..."

INDEX_RESPONSE=$(curl -s -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/semantic-highlight-test" \
  -H 'Content-Type: application/json' \
  -d '{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0
  },
  "mappings": {
    "properties": {
      "title": {"type": "text"},
      "content": {"type": "text"}
    }
  }
}')

echo "Index creation response: $INDEX_RESPONSE"
echo ""

# Index some test documents
echo "Indexing test documents..."

curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/semantic-highlight-test/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{
  "title": "Introduction to Machine Learning",
  "content": "Machine learning is a type of artificial intelligence that enables computers to learn from data and make predictions without being explicitly programmed. It involves training models on large datasets to identify patterns and make decisions."
}' > /dev/null

curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/semantic-highlight-test/_doc/2" \
  -H 'Content-Type: application/json' \
  -d '{
  "title": "Deep Learning Fundamentals",
  "content": "Deep learning is a subset of machine learning that uses neural networks with multiple layers. These networks can automatically learn hierarchical representations of data, making them powerful for tasks like image recognition and natural language processing."
}' > /dev/null

curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/semantic-highlight-test/_doc/3" \
  -H 'Content-Type: application/json' \
  -d '{
  "title": "Natural Language Processing",
  "content": "Natural language processing (NLP) is a branch of AI that helps computers understand, interpret, and generate human language. NLP combines computational linguistics with machine learning to process and analyze large amounts of natural language data."
}' > /dev/null

# Refresh the index
curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/semantic-highlight-test/_refresh" > /dev/null

echo "Documents indexed successfully"
echo ""

# Test semantic highlighting with keywords query and batch model
echo "Testing semantic highlighting with batch processing..."
echo ""

SEARCH_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/semantic-highlight-test/_search" \
  -H 'Content-Type: application/json' \
  -d "{
  \"query\": {
    \"match\": {
      \"content\": {
        \"query\": \"What is machine learning?\"
      }
    }
  },
  \"highlight\": {
    \"fields\": {
      \"content\": {
        \"type\": \"semantic\",
        \"model_id\": \"${MODEL_ID}\",
        \"use_batch\": true
      }
    }
  },
  \"size\": 3
}")

echo "Search response:"
echo $SEARCH_RESPONSE | jq '.'

echo ""
echo "Testing completed!"
echo ""

# Clean up
echo "Cleaning up test index..."
curl -s -X DELETE "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/semantic-highlight-test" > /dev/null

echo "Done!"