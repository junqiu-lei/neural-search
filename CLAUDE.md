# OpenSearch Plugin Repositories

## Current Task: Batch Semantic Highlighting Implementation

### Task Goal
Implement a clean batch-only solution for semantic highlighting that:
1. Completely removes parallel processing logic
2. Supports both remote and local models
3. Allows changes in ml-commons plugin as needed
4. Maintains backward compatibility with use_batch flag (default: false)
5. Uses single model_id (no batch_model_id)

### Key Requirements
- Remove all parallel processing fallback logic
- Create comprehensive design document
- Document all changes clearly
- Test with both local and remote models
- Commit changes frequently

## Important: Neural Search 3.0.0+ Compatibility

### Unified ML Client API (Since 3.0.0)
As of Neural Search 3.0.0, the `MLCommonsClientAccessor` provides a unified API for both local and remote model inference. Key changes:

1. **Inheritance-based Request Pattern**: All inference requests extend from `InferenceRequest` base class
   - `TextInferenceRequest` - for text embeddings
   - `MapInferenceRequest` - for multimodal inputs
   - `SimilarityInferenceRequest` - for text similarity
   - `SentenceHighlightingRequest` - for semantic highlighting

2. **Common Fields**: All requests share:
   - `modelId` (required) - Works for both local and remote models
   - `targetResponseFilters` - Defaults to `["sentence_embedding"]`

3. **Backward Compatibility**: When implementing new features (like batch highlighting), ensure compatibility with the unified API pattern

### Implementation Considerations for Batch Highlighting
- Extend `InferenceRequest` for new request types (already done with `BatchHighlightingRequest`)
- Ensure both local and remote models are supported through the same API
- Follow the established pattern in `MLCommonsClientAccessor`
- Test with both local and remote model configurations

### Development Requirements (3.0.0+)
- **JDK Version**: Baseline JDK-21 (required for Neural Search 3.0.0+)
- **OpenSearch Version**: Compatible with OpenSearch 3.0.0+
- **Key Features in 3.0.0**:
  - Semantic sentence highlighter
  - Unified ML client for local/remote models
  - Semantic field mapper
  - Stats API for monitoring

## Important: Commit Message Guidelines

**NEVER include Claude attribution in commit messages**. Do not add:
- "🤖 Generated with [Claude Code]"
- "Co-Authored-By: Claude"
- Any other Claude-related attribution

Keep commit messages professional and focused only on the technical changes.

## Repository Locations

- **OpenSearch Core**: `/home/junqiu/OpenSearch`
- **Neural Search Plugin**: `/home/junqiu/neural-search`
- **k-NN Plugin**: `/home/junqiu/k-NN`
- **ML Commons Plugin**: `/home/junqiu/ml-commons`

## About the Plugins

### Neural Search Plugin
The neural-search plugin enables semantic search capabilities in OpenSearch using neural networks and vector embeddings.

### k-NN Plugin
The k-NN (k-Nearest Neighbors) plugin enables efficient similarity search for vectors in OpenSearch.

## Development Notes

When working with these plugins, please note their locations:
- Neural Search codebase is at `/home/junqiu/neural-search`
- k-NN codebase is at `/home/junqiu/k-NN`

## Docker Images

For OpenSearch 3.1.0, use the staging/RC images:
- Docker image: `opensearchstaging/opensearch:3.1.0`
- Reference: https://github.com/opensearch-project/opensearch-build/issues/5487

## Docker Development Workflow for Multi-Node Testing

This workflow enables rapid testing of plugin changes in a multi-node OpenSearch cluster using Docker Compose.

### Prerequisites

1. Install Docker Compose if not present:
```bash
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

2. Increase vm.max_map_count (required for OpenSearch):
```bash
sudo sysctl -w vm.max_map_count=262144
```

### Quick Start

1. **Build the plugin**:
```bash
cd /home/junqiu/neural-search
./gradlew clean
./gradlew build -x test -x integTest
```

2. **Prepare plugin for Docker**:
```bash
# Create plugin directory with correct structure
rm -rf docker-plugins
mkdir -p docker-plugins/opensearch-neural-search
cd docker-plugins/opensearch-neural-search
unzip /home/junqiu/neural-search/build/distributions/opensearch-neural-search-*.zip
cd ../..
```

3. **Create docker-compose.yml**:
```yaml
version: '3'
services:
  opensearch-node1:
    image: opensearchstaging/opensearch:3.1.0
    container_name: opensearch-node1
    environment:
      - cluster.name=opensearch-cluster
      - node.name=opensearch-node1
      - discovery.seed_hosts=opensearch-node1,opensearch-node2
      - cluster.initial_cluster_manager_nodes=opensearch-node1,opensearch-node2
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
      - 9200:9200
      - 9600:9600
    networks:
      - opensearch-net

  opensearch-node2:
    image: opensearchstaging/opensearch:3.1.0
    container_name: opensearch-node2
    environment:
      - cluster.name=opensearch-cluster
      - node.name=opensearch-node2
      - discovery.seed_hosts=opensearch-node1,opensearch-node2
      - cluster.initial_cluster_manager_nodes=opensearch-node1,opensearch-node2
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

4. **Start the cluster**:
```bash
docker-compose up -d
```

5. **Verify cluster health**:
```bash
# Wait for cluster to be ready
sleep 60
curl -s http://localhost:9200/_cluster/health | jq '.'

# Check installed plugins
curl -s "http://localhost:9200/_cat/plugins?v"
```

### Testing Workflow

1. **Make code changes** to the plugin
2. **Rebuild the plugin**:
```bash
./gradlew build -x test -x integTest
```
3. **Update plugin in Docker**:
```bash
rm -rf docker-plugins/opensearch-neural-search/*
cd docker-plugins/opensearch-neural-search
unzip /home/junqiu/neural-search/build/distributions/opensearch-neural-search-*.zip
cd ../..
```
4. **Restart cluster**:
```bash
docker-compose down -v
docker-compose up -d
```
5. **Run tests** against the cluster

### Useful Commands

- **View logs**: `docker-compose logs -f`
- **View specific node logs**: `docker logs opensearch-node1`
- **Stop cluster**: `docker-compose down -v`
- **Check container status**: `docker ps`
- **Execute command in container**: `docker exec -it opensearch-node1 bash`

### Debugging Tips

1. **Check for errors in logs**:
```bash
docker logs opensearch-node1 2>&1 | grep -i "error\|exception"
```

2. **Monitor debug logs**:
```bash
docker logs -f opensearch-node1 2>&1 | grep -i "neural"
```

3. **Test multi-shard behavior**:
   - Create indices with `number_of_shards: 2` to ensure queries are distributed across nodes
   - This helps catch serialization/deserialization issues

### Advantages Over CDK Deployment

- **Speed**: 2-3 minutes vs 20-30 minutes
- **Cost**: Free (local) vs AWS charges
- **Iteration**: Hot-reload by restarting containers
- **Debugging**: Direct access to logs and containers
- **Flexibility**: Easy to test different configurations

## Standard Workflow: Code Change to S3 Artifact

Follow this workflow when making code changes and creating OpenSearch artifacts for deployment:

### 1. Create a New Branch
```bash
git checkout -b <branch-name>
```

### 2. Apply Code Changes
- Make necessary code modifications
- Add debug logging if needed for troubleshooting
- Ensure code follows existing patterns and conventions

### 3. Build the Plugin
```bash
./gradlew clean
./gradlew build -x test  # Skip tests for faster builds during development
# Or with tests:
# ./gradlew build
```

### 4. Create OpenSearch Artifact

#### 4.1 Download Base OpenSearch Artifact (if not already present)
```bash
wget -O opensearch-3.1.0-linux-arm64.tar.gz \
  https://ci.opensearch.org/ci/dbc/distribution-build-opensearch/3.1.0/11179/linux/arm64/tar/dist/opensearch/opensearch-3.1.0-linux-arm64.tar.gz
```

#### 4.2 Create Fixed Artifact Script
Create a script to build the artifact with proper plugin structure:

```bash
#!/bin/bash
set -e

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
WORK_DIR="/tmp/opensearch-artifact-$TIMESTAMP"
ARTIFACT_NAME="opensearch-3.1.0-linux-arm64-<fix-description>-$TIMESTAMP.tar.gz"

# Create work directory
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Extract base artifact
tar -xzf /path/to/opensearch-3.1.0-linux-arm64.tar.gz

# Remove existing plugin
rm -rf opensearch-3.1.0/plugins/<plugin-name>

# Create temp directory for plugin extraction
PLUGIN_TEMP="$WORK_DIR/plugin-temp"
mkdir -p "$PLUGIN_TEMP"
cd "$PLUGIN_TEMP"

# Extract the built plugin (maintains proper directory structure)
cp /path/to/plugin/build/distributions/<plugin-name>-*.zip ./
unzip -q <plugin-name>-*.zip

# Move to plugins directory
mv <plugin-name> "$WORK_DIR/opensearch-3.1.0/plugins/"

# Create tarball
cd "$WORK_DIR"
tar -czf "$ARTIFACT_NAME" opensearch-3.1.0/

# Move to output location
mv "$ARTIFACT_NAME" /path/to/output/

# Cleanup
rm -rf "$WORK_DIR"

echo "Artifact created: $ARTIFACT_NAME"
```

### 5. Verify the Artifact Locally

#### 5.1 Extract and Configure
```bash
tar -xzf <artifact-name>.tar.gz
cd opensearch-3.1.0
echo "plugins.security.disabled: true" >> config/opensearch.yml
export OPENSEARCH_INITIAL_ADMIN_PASSWORD="TestPassword123!"
```

#### 5.2 Start OpenSearch
```bash
./opensearch-tar-install.sh
```

#### 5.3 Verify Plugin Installation
```bash
# Check cluster health
curl -s http://localhost:9200/_cluster/health | jq '.'

# Check installed plugins
curl -s "http://localhost:9200/_cat/plugins?v" | grep <plugin-name>
```

#### 5.4 Verify Code Changes
- Check that the plugin JAR contains your changes
- For class file verification:
```bash
cd plugins/<plugin-name>
jar -xf <plugin-jar>.jar path/to/YourClass.class
strings path/to/YourClass.class | grep -i "your-change"
```

### 6. Upload to S3

Once verified, upload the artifact to S3:

```bash
aws s3 cp <artifact-name>.tar.gz s3://junqiu-opensearch-artifacts/
```

### 7. Document the Changes

Create a README for the artifact documenting:
- The issue being fixed
- The changes made
- Testing performed
- Installation instructions

### Important Notes

1. **Multi-node Issues**: Issues that only occur in multi-node/multi-shard deployments require serialization/deserialization of queries across nodes

2. **Plugin Structure**: Ensure plugins are in their own directories under `plugins/`, not scattered files

3. **Security**: Always disable security plugin for local testing with `plugins.security.disabled: true`

4. **Cleanup**: Always clean up test directories and kill OpenSearch processes after testing

5. **Naming Convention**: Use descriptive names for artifacts including timestamp: `opensearch-VERSION-ARCH-description-TIMESTAMP.tar.gz`

## Deploying Embedding Models for Neural Search Testing

When testing neural search functionality, you need to deploy an embedding model first. Here's how:

### Quick Model Deployment Script

```bash
#!/bin/bash
# deploy-embedding-model.sh

OPENSEARCH_HOST="localhost"
OPENSEARCH_PORT="9200"  # Adjust based on your setup

# Configure ML settings
curl -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_cluster/settings" -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "plugins.ml_commons.allow_registering_model_via_url": "true",
    "plugins.ml_commons.only_run_on_ml_node": "false",
    "plugins.ml_commons.model_access_control_enabled": "true"
  }
}'

# Register and deploy model
RESPONSE=$(curl -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/_register?deploy=true" -H 'Content-Type: application/json' -d'
{
  "name": "huggingface/sentence-transformers/all-MiniLM-L6-v2",
  "version": "1.0.2",
  "model_format": "TORCH_SCRIPT"
}')

TASK_ID=$(echo $RESPONSE | grep -o '"task_id":"[^"]*"' | cut -d'"' -f4)
echo "Task ID: $TASK_ID"

# Wait for deployment (check task status)
sleep 30

# Get model ID
TASK_RESPONSE=$(curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/tasks/${TASK_ID}")
MODEL_ID=$(echo $TASK_RESPONSE | grep -o '"model_id":"[^"]*"' | cut -d'"' -f4)
echo "Model ID: $MODEL_ID"
```

### Creating Test Index for Neural Search

```bash
# Create index with KNN enabled
curl -X PUT "http://localhost:9200/neural-test" -H 'Content-Type: application/json' -d'
{
  "settings": {
    "number_of_shards": 2,
    "number_of_replicas": 1,
    "index.knn": true
  },
  "mappings": {
    "properties": {
      "text": {"type": "text"},
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
}'

# Create ingest pipeline
curl -X PUT "http://localhost:9200/_ingest/pipeline/text-embedding-pipeline" -H 'Content-Type: application/json' -d"{
  \"description\": \"Generate embeddings\",
  \"processors\": [{
    \"text_embedding\": {
      \"model_id\": \"${MODEL_ID}\",
      \"field_map\": {\"text\": \"embedding\"}
    }
  }]
}"
```

### Testing Neural Radial Search

```bash
# Test radial search with min_score
curl -X POST "http://localhost:9200/neural-test/_search" -H 'Content-Type: application/json' -d"{
  \"query\": {
    \"neural\": {
      \"embedding\": {
        \"query_text\": \"search query\",
        \"model_id\": \"${MODEL_ID}\",
        \"min_score\": 0.3
      }
    }
  }
}"
```

## Batch Semantic Highlighting Models

### Production Models Location
The verified batch highlighting models are located at: `/home/junqiu/tracing_gpu/batch_model/FINAL/`

### Model Requirements

| Model Type | Batch Support | API Pattern | Description |
|------------|---------------|-------------|-------------|
| Single Document | No | `/_plugins/_ml/models/<model-id>/_predict` | Process one document at a time |
| Batch Processing | Yes | `/_plugins/_ml/models/<model-id>/_predict` | Process multiple documents |

**Note**:
- Model IDs are deployment-specific
- Batch size limits are configured at model deployment (e.g., 512)
- No client-side batch size configuration needed
- Reference implementation: `/home/junqiu/tracing_gpu/batch_model/FINAL/`

### Model Architecture
- **Base Model**: BERT-based (`bert-base-uncased`)
- **Task**: Sentence-level semantic highlighting
- **Batch Support**: True dynamic batching (limit set at model deployment)
- **Performance**: ~8ms per document in batch mode
- **Format**: TorchScript (PyTorch JIT)

### Example API Usage

#### Single Document
```bash
curl -X POST "http://<opensearch-host>/_plugins/_ml/models/<single-model-id>/_predict" \
  -H 'Content-Type: application/json' \
  -d '{
    "parameters": {
      "question": "What are the symptoms?",
      "context": "Common symptoms include fever and cough."
    }
  }'
```

#### Batch Processing
```bash
curl -X POST "http://<opensearch-host>/_plugins/_ml/models/<batch-model-id>/_predict" \
  -H 'Content-Type: application/json' \
  -d '{
    "parameters": {
      "batch": [
        {"question": "What is AI?", "context": "AI stands for artificial intelligence."},
        {"question": "What is ML?", "context": "ML stands for machine learning."}
      ]
    }
  }'
```

### Response Format
- **Single**: Returns `highlights` array with highlighted sentences
- **Batch**: Returns `results` array with highlights for each document
- Each highlight includes: `text`, `start`, `end`, `score`, `position`

### Performance Guidelines
- **Batch size**: Determined by model configuration
- **Context length**: Keep under 512 tokens
- **Timeout**: Set appropriately for expected batch sizes

## Checking ML Models in OpenSearch

### List All ML Models

```bash
# List all ML models with their status
curl -s -X GET "http://<OPENSEARCH_HOST>/_plugins/_ml/models/_search" \
  -H 'Content-Type: application/json' \
  -d'{"query":{"match_all":{}}}' | jq '.'

# Get a specific model's details
curl -s "http://<OPENSEARCH_HOST>/_plugins/_ml/models/<MODEL_ID>" | jq '.'
```

### Check ML Tasks

```bash
# List all ML tasks
curl -s -X GET "http://<OPENSEARCH_HOST>/_plugins/_ml/tasks/_search" \
  -H 'Content-Type: application/json' \
  -d'{"query":{"match_all":{}}}' | jq '.'

# Get a specific task status
curl -s "http://<OPENSEARCH_HOST>/_plugins/_ml/tasks/<TASK_ID>" | jq '.'
```

### ML Commons Statistics

```bash
# Get ML stats
curl -s "http://<OPENSEARCH_HOST>/_plugins/_ml/stats" | jq '.'

# Get ML profile (node-level information)
curl -s "http://<OPENSEARCH_HOST>/_plugins/_ml/profile" | jq '.'
```

### Common Model States

- **REGISTERING**: Model is being registered
- **REGISTERED**: Model is registered but not deployed
- **DEPLOYING**: Model is being deployed to nodes
- **DEPLOYED**: Model is ready to use
- **UNDEPLOYING**: Model is being removed from nodes
- **DEPLOY_FAILED**: Model deployment failed

### Useful Model Filters

```bash
# Find deployed models only
curl -s -X GET "http://<OPENSEARCH_HOST>/_plugins/_ml/models/_search" \
  -H 'Content-Type: application/json' \
  -d'{
    "query": {
      "term": {
        "model_state": "DEPLOYED"
      }
    }
  }' | jq '.'

# Find models by algorithm type
curl -s -X GET "http://<OPENSEARCH_HOST>/_plugins/_ml/models/_search" \
  -H 'Content-Type: application/json' \
  -d'{
    "query": {
      "term": {
        "algorithm": "TEXT_EMBEDDING"
      }
    }
  }' | jq '.'
```
