# Docker Neural Radial Search Testing Guide

This guide provides step-by-step instructions for testing neural radial search functionality in a multi-node OpenSearch Docker environment.

## Prerequisites

1. Docker and Docker Compose installed
2. Access to neural-search plugin source code
3. Sufficient disk space (~5GB)
4. Port 9210 available (or modify docker-compose.yml)

## Step-by-Step Guide

### Step 1: Build the Neural Search Plugin

Navigate to the neural-search directory and build the plugin:

```bash
cd /home/junqiu/neural-search

# Clean previous builds
./gradlew clean

# Build plugin (skip tests for faster build)
./gradlew build -x test -x integTest
```

### Step 2: Prepare Plugin for Docker

Create the plugin directory structure:

```bash
# Remove old plugin files
rm -rf docker-plugins

# Create plugin directory
mkdir -p docker-plugins/opensearch-neural-search

# Extract the built plugin
cd docker-plugins/opensearch-neural-search
unzip /home/junqiu/neural-search/build/distributions/opensearch-neural-search-*.zip
cd ../..
```

### Step 3: Create docker-compose.yml

Create a `docker-compose.yml` file with the following content:

```yaml
version: '3'
services:
  opensearch-fix-node1:
    image: opensearchstaging/opensearch:3.1.0
    container_name: opensearch-fix-node1
    environment:
      - cluster.name=opensearch-cluster
      - node.name=opensearch-fix-node1
      - discovery.seed_hosts=opensearch-fix-node1,opensearch-fix-node2
      - cluster.initial_cluster_manager_nodes=opensearch-fix-node1,opensearch-fix-node2
      - OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m
      - OPENSEARCH_INITIAL_ADMIN_PASSWORD=MyStrongPassword123!
      - plugins.security.disabled=true
      - bootstrap.memory_lock=false
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    volumes:
      - opensearch-data1:/usr/share/opensearch/data
      - ./docker-plugins/opensearch-neural-search:/usr/share/opensearch/plugins/opensearch-neural-search
    ports:
      - 9210:9200
      - 9610:9600
    networks:
      - opensearch-net

  opensearch-fix-node2:
    image: opensearchstaging/opensearch:3.1.0
    container_name: opensearch-fix-node2
    environment:
      - cluster.name=opensearch-cluster
      - node.name=opensearch-fix-node2
      - discovery.seed_hosts=opensearch-fix-node1,opensearch-fix-node2
      - cluster.initial_cluster_manager_nodes=opensearch-fix-node1,opensearch-fix-node2
      - OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m
      - OPENSEARCH_INITIAL_ADMIN_PASSWORD=MyStrongPassword123!
      - plugins.security.disabled=true
      - bootstrap.memory_lock=false
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    volumes:
      - opensearch-data2:/usr/share/opensearch/data
      - ./docker-plugins/opensearch-neural-search:/usr/share/opensearch/plugins/opensearch-neural-search
    networks:
      - opensearch-net

volumes:
  opensearch-data1:
  opensearch-data2:

networks:
  opensearch-net:
```

### Step 4: Start the Docker Cluster

```bash
# Stop any existing containers and remove volumes
docker-compose down -v

# Start the cluster
docker-compose up -d

# Wait for cluster to be ready (about 60 seconds)
sleep 60

# Verify cluster health
curl -s http://localhost:9210/_cluster/health | jq '.'
```

Expected output should show `"status": "green"` and `"number_of_nodes": 2`.

### Step 5: Verify Plugin Installation

```bash
# Check installed plugins
curl -s "http://localhost:9210/_cat/plugins?v" | grep neural
```

You should see both nodes have the neural-search plugin installed.

### Step 6: Configure ML Commons

Disable the ML node requirement to run models on data nodes:

```bash
curl -X PUT "http://localhost:9210/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "persistent": {
      "plugins.ml_commons.only_run_on_ml_node": false
    }
  }' | jq '.'
```

### Step 7: Register an Embedding Model

```bash
# Register the model
curl -X POST "http://localhost:9210/_plugins/_ml/models/_register" \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "huggingface/sentence-transformers/all-MiniLM-L6-v2",
    "version": "1.0.1",
    "model_format": "TORCH_SCRIPT"
  }' | jq '.'
```

Save the `task_id` from the response, then check the task status:

```bash
# Replace TASK_ID with the actual task ID
curl -X GET "http://localhost:9210/_plugins/_ml/tasks/TASK_ID" | jq '.'
```

Save the `model_id` from the response.

### Step 8: Deploy the Model

```bash
# Replace MODEL_ID with the actual model ID
curl -X POST "http://localhost:9210/_plugins/_ml/models/MODEL_ID/_deploy" | jq '.'
```

Wait about 30 seconds for deployment to complete, then verify:

```bash
# Check model status
curl -X GET "http://localhost:9210/_plugins/_ml/models/MODEL_ID" | jq '.model_state'
```

The model_state should be "DEPLOYED".

### Step 9: Create Neural Ingest Pipeline

```bash
# Replace MODEL_ID with your actual model ID
curl -X PUT "http://localhost:9210/_ingest/pipeline/neural-ingest-pipeline" \
  -H 'Content-Type: application/json' \
  -d '{
    "processors": [
      {
        "text_embedding": {
          "model_id": "MODEL_ID",
          "field_map": {
            "embedding_text": "embedding"
          }
        }
      }
    ]
  }' | jq '.'
```

### Step 10: Create Test Index

```bash
curl -X PUT "http://localhost:9210/test-neural-radial" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "index": {
        "knn": true
      },
      "number_of_shards": 2,
      "number_of_replicas": 0
    },
    "mappings": {
      "properties": {
        "title": {
          "type": "text"
        },
        "embedding": {
          "type": "knn_vector",
          "dimension": 384,
          "method": {
            "name": "hnsw",
            "space_type": "l2",
            "engine": "lucene"
          }
        }
      }
    }
  }' | jq '.'
```

### Step 11: Ingest Test Data

```bash
# Create test data file
cat > /tmp/test-neural-data.json << 'EOF'
{"index": {"_index": "test-neural-radial", "_id": "1"}}
{"title": "Introduction to machine learning algorithms", "embedding_text": "Introduction to machine learning algorithms"}
{"index": {"_index": "test-neural-radial", "_id": "2"}}
{"title": "Advanced deep learning techniques", "embedding_text": "Advanced deep learning techniques"}
{"index": {"_index": "test-neural-radial", "_id": "3"}}
{"title": "Neural networks fundamentals", "embedding_text": "Neural networks fundamentals"}
{"index": {"_index": "test-neural-radial", "_id": "4"}}
{"title": "Artificial intelligence basics", "embedding_text": "Artificial intelligence basics"}
{"index": {"_index": "test-neural-radial", "_id": "5"}}
{"title": "Python programming for data science", "embedding_text": "Python programming for data science"}
EOF

# Ingest data using the neural pipeline
curl -X POST "http://localhost:9210/_bulk?pipeline=neural-ingest-pipeline" \
  -H 'Content-Type: application/json' \
  --data-binary @/tmp/test-neural-data.json | jq '.'
```

### Step 12: Test Neural Radial Search

#### Test 1: Neural Radial Search with min_score

```bash
# Replace MODEL_ID with your actual model ID
curl -X GET "http://localhost:9210/test-neural-radial/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 5,
    "_source": {
      "excludes": ["embedding"]
    },
    "query": {
      "neural": {
        "embedding": {
          "query_text": "machine learning algorithms",
          "model_id": "MODEL_ID",
          "min_score": 0.5
        }
      }
    }
  }' | jq '.'
```

Expected: Returns documents with similarity score >= 0.5

#### Test 2: Neural Radial Search with max_distance

```bash
# Replace MODEL_ID with your actual model ID
curl -X GET "http://localhost:9210/test-neural-radial/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 5,
    "_source": {
      "excludes": ["embedding"]
    },
    "query": {
      "neural": {
        "embedding": {
          "query_text": "machine learning algorithms",
          "model_id": "MODEL_ID",
          "max_distance": 0.5
        }
      }
    }
  }' | jq '.'
```

Expected: Returns documents with distance <= 0.5

#### Test 3: Regular Neural k-NN Search (for comparison)

```bash
# Replace MODEL_ID with your actual model ID
curl -X GET "http://localhost:9210/test-neural-radial/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 5,
    "_source": {
      "excludes": ["embedding"]
    },
    "query": {
      "neural": {
        "embedding": {
          "query_text": "machine learning algorithms",
          "model_id": "MODEL_ID",
          "k": 5
        }
      }
    }
  }' | jq '.'
```

Expected: Returns top 5 nearest neighbors

### Step 13: Monitor Logs (Optional)

To debug issues, monitor the logs:

```bash
# View logs from both nodes
docker-compose logs -f

# View logs from a specific node
docker logs opensearch-fix-node1 -f

# Search for specific errors
docker logs opensearch-fix-node1 2>&1 | grep -i "error\|exception"
```

### Step 14: Clean Up

When done testing:

```bash
# Stop containers and remove volumes
docker-compose down -v

# Remove test data file
rm /tmp/test-neural-data.json
```

## Troubleshooting

### Common Issues

1. **Port already in use**: Change port 9210 in docker-compose.yml to another port
2. **Model deployment fails**: Ensure you have enough memory allocated to Docker
3. **Plugin not loading**: Check that the plugin files are correctly extracted in docker-plugins directory
4. **Cluster not forming**: Check container logs for network connectivity issues

### Useful Commands

```bash
# Check cluster status
curl -s http://localhost:9210/_cluster/health?pretty

# List all indices
curl -s http://localhost:9210/_cat/indices?v

# Check model status
curl -s http://localhost:9210/_plugins/_ml/models/MODEL_ID | jq '.model_state'

# Delete test index
curl -X DELETE http://localhost:9210/test-neural-radial
```

## Notes

- The test uses OpenSearch 3.1.0 staging image
- Security is disabled for easier testing
- Each node has 512MB heap size (adjust if needed)
- The embedding model dimension is 384
- Test data includes 5 documents about ML/AI topics
