# Docker Development SOP for OpenSearch Neural Search

## Overview
This SOP provides step-by-step instructions for developing and testing the neural-search plugin using Docker with both single-node and multi-node configurations.

## Prerequisites

1. **Install Docker and Docker Compose**
   ```bash
   # Install Docker (if not installed)
   sudo apt-get update
   sudo apt-get install docker.io

   # Install Docker Compose
   sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
   sudo chmod +x /usr/local/bin/docker-compose
   ```

2. **System Configuration**
   ```bash
   # Increase vm.max_map_count (required for OpenSearch)
   sudo sysctl -w vm.max_map_count=262144

   # Make it permanent
   echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
   ```

## Single-Node Development

### 1. Build the Plugin
```bash
cd /home/junqiu/neural-search
./gradlew clean
./gradlew build -x test -x integTest
```

### 2. Create docker-compose.yml for Single Node
```yaml
version: '3'
services:
  opensearch-single:
    image: opensearchstaging/opensearch:3.1.0
    container_name: opensearch-single
    environment:
      - discovery.type=single-node
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
      - opensearch-data-single:/usr/share/opensearch/data
      - ./docker-plugins/opensearch-neural-search:/usr/share/opensearch/plugins/opensearch-neural-search
    ports:
      - 9200:9200
      - 9600:9600
    networks:
      - opensearch-net

volumes:
  opensearch-data-single:

networks:
  opensearch-net:
```

### 3. Prepare and Start Single Node
```bash
# Prepare plugin directory
rm -rf docker-plugins
mkdir -p docker-plugins/opensearch-neural-search
cd docker-plugins/opensearch-neural-search
unzip ../../build/distributions/opensearch-neural-search-*.zip
cd ../..

# Start the container
docker-compose -f docker-compose-single.yml up -d

# Wait for startup
sleep 30

# Verify cluster health
curl -s http://localhost:9200/_cluster/health | jq '.'

# Check plugin installation
curl -s "http://localhost:9200/_cat/plugins?v" | grep neural
```

## Multi-Node Development

### 1. Create docker-compose.yml for Multi-Node
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

### 2. Start Multi-Node Cluster
```bash
# Use the same plugin preparation as single node

# Start the cluster
docker-compose up -d

# Wait for cluster formation
sleep 60

# Verify cluster health (should show 2 nodes)
curl -s http://localhost:9200/_cluster/health | jq '.'
```

## Development Workflow

### 1. Make Code Changes
Edit your code in `/home/junqiu/neural-search`

### 2. Rebuild Plugin
```bash
./gradlew build -x test -x integTest
```

### 3. Update Plugin in Docker
```bash
# Stop containers
docker-compose down

# Update plugin
rm -rf docker-plugins/opensearch-neural-search/*
cd docker-plugins/opensearch-neural-search
unzip ../../build/distributions/opensearch-neural-search-*.zip
cd ../..

# Restart containers
docker-compose up -d
```

### 4. Test Your Changes

#### Basic KNN Test
```bash
# Create index with KNN enabled
curl -X PUT http://localhost:9200/test-knn -H 'Content-Type: application/json' -d '{
  "settings": {
    "index": {
      "knn": true,
      "number_of_shards": 2,
      "number_of_replicas": 0
    }
  },
  "mappings": {
    "properties": {
      "embedding": {
        "type": "knn_vector",
        "dimension": 3
      }
    }
  }
}'

# Add documents
for i in {1..5}; do
  curl -X POST http://localhost:9200/test-knn/_doc/$i -H 'Content-Type: application/json' -d "{
    \"embedding\": [$i.0, $((i*2)).0, $((i*3)).0]
  }"
done

# Refresh index
curl -X POST http://localhost:9200/test-knn/_refresh

# Test KNN search
curl -X POST http://localhost:9200/test-knn/_search -H 'Content-Type: application/json' -d '{
  "query": {
    "knn": {
      "embedding": {
        "vector": [2.0, 4.0, 6.0],
        "k": 3
      }
    }
  }
}'
```

#### Neural Search Test (Simplified)
```bash
# Create index for neural search
curl -X PUT http://localhost:9200/test-neural -H 'Content-Type: application/json' -d '{
  "settings": {
    "index": {
      "knn": true,
      "number_of_shards": 2
    }
  },
  "mappings": {
    "properties": {
      "text": {
        "type": "text"
      },
      "embedding": {
        "type": "knn_vector",
        "dimension": 384
      }
    }
  }
}'

# For neural search with model, you'll need to:
# 1. Set up ML Commons
# 2. Register and deploy a model
# 3. Create ingest pipeline
# 4. Use neural query

# Test radial search with direct KNN (no model needed)
curl -X POST http://localhost:9200/test-knn/_search -H 'Content-Type: application/json' -d '{
  "query": {
    "knn": {
      "embedding": {
        "vector": [2.0, 4.0, 6.0],
        "max_distance": 5.0
      }
    }
  }
}'
```

#### Force Cross-Node Query (Multi-Node Only)
```bash
# Use preference=_primary to force cross-node communication
curl -X POST "http://localhost:9200/test-knn/_search?preference=_primary" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "knn": {
        "embedding": {
          "vector": [2.0, 4.0, 6.0],
          "min_score": 0.5
        }
      }
    }
  }'
```

## Debugging

### View Logs
```bash
# All containers
docker-compose logs -f

# Specific node
docker logs -f opensearch-node1

# Filter for specific terms
docker logs opensearch-node1 2>&1 | grep -i "neural\|knn"
```

### Access Container Shell
```bash
docker exec -it opensearch-node1 bash
```

### Check Cluster State
```bash
# Node info
curl -s http://localhost:9200/_cat/nodes?v

# Shard allocation
curl -s http://localhost:9200/_cat/shards?v

# Plugin info
curl -s http://localhost:9200/_cat/plugins?v
```

## Cleanup

### Stop and Remove Containers
```bash
# Stop containers
docker-compose down

# Stop and remove volumes (complete cleanup)
docker-compose down -v
```

### Remove Docker Images (if needed)
```bash
docker rmi opensearchstaging/opensearch:3.1.0
```

## Troubleshooting

### Common Issues

1. **Port Already in Use**
   ```bash
   # Find process using port 9200
   sudo lsof -i :9200
   # Kill the process if needed
   ```

2. **Memory Issues**
   - Reduce heap size in OPENSEARCH_JAVA_OPTS
   - Ensure Docker has enough memory allocated

3. **Plugin Not Loading**
   - Check file permissions in docker-plugins directory
   - Verify plugin compatibility with OpenSearch version
   - Check container logs for errors

4. **Cluster Not Forming (Multi-Node)**
   - Ensure containers can communicate on the Docker network
   - Check that node names and seed hosts match
   - Verify cluster.initial_cluster_manager_nodes setting

## Best Practices

1. **Development Speed**
   - Use `-x test -x integTest` for faster builds during development
   - Keep containers running and just restart after plugin updates
   - Use single-node for quick tests, multi-node for distributed behavior

2. **Testing**
   - Always test with multi-shard indices to catch serialization issues
   - Use `preference=_primary` to force cross-node communication
   - Test both regular k-NN and radial search queries

3. **Performance**
   - Monitor Docker resource usage with `docker stats`
   - Adjust heap sizes based on your system resources
   - Use volumes for data persistence between restarts

## Advantages Over CDK

- **Speed**: 2-3 minutes vs 20-30 minutes for deployment
- **Cost**: Free local development vs AWS charges
- **Flexibility**: Easy to test different configurations
- **Debugging**: Direct access to logs and containers
- **Iteration**: Hot-reload by just restarting containers
