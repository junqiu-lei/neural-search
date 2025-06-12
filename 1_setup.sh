#!/bin/bash

# Configuration
# OPENSEARCH_HOST="opense-clust-CePDyxTglAI8-6f22b7d87da3d2d1.elb.us-east-1.amazonaws.com"
# OPENSEARCH_PORT="80"
OPENSEARCH_HOST="localhost"
OPENSEARCH_PORT="9200"
INDEX_NAME="neural-search-index"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --skip-model-deploy             Skip model deployment (use existing models)"
    echo "  --skip-index-creation           Skip index creation (use existing index)"
    echo "  --skip-semantic-highlighting    Skip semantic highlighting model registration and test"
    echo "  --text-embedding-model-id ID    Text embedding model ID (required with --skip-model-deploy)"
    echo "  --semantic-highlighting-model-id ID  Semantic highlighting model ID (required with --skip-model-deploy)"
    echo "  --help                          Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Deploy new models and create everything from scratch:"
    echo "  $0"
    echo ""
    echo "  # Use existing models:"
    echo "  $0 --skip-model-deploy --text-embedding-model-id MODEL1 --semantic-highlighting-model-id MODEL2"
    echo ""
    echo "  # Use existing models and index:"
    echo "  $0 --skip-model-deploy --skip-index-creation --text-embedding-model-id MODEL1 --semantic-highlighting-model-id MODEL2"
    echo ""
    echo "  # Only set up text embedding without semantic highlighting:"
    echo "  $0 --skip-semantic-highlighting"
}

# Parse command line arguments
SKIP_MODEL_DEPLOY=false
SKIP_INDEX_CREATION=false
SKIP_SEMANTIC_HIGHLIGHTING=false
TEXT_EMBEDDING_MODEL_ID=""
SEMANTIC_HIGHLIGHTING_MODEL_ID=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-model-deploy)
      SKIP_MODEL_DEPLOY=true
      shift
      ;;
    --skip-index-creation)
      SKIP_INDEX_CREATION=true
      shift
      ;;
    --skip-semantic-highlighting)
      SKIP_SEMANTIC_HIGHLIGHTING=true
      shift
      ;;
    --text-embedding-model-id)
      TEXT_EMBEDDING_MODEL_ID="$2"
      shift 2
      ;;
    --semantic-highlighting-model-id)
      SEMANTIC_HIGHLIGHTING_MODEL_ID="$2"
      shift 2
      ;;
    --help)
      show_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo ""
      show_usage
      exit 1
      ;;
  esac
done

echo "Setting up Semantic Search with Highlighting"

# Step 0: Configure cluster settings
echo -e "\n${GREEN}Step 0: Configuring cluster settings${NC}"
curl -s -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_cluster/settings" -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "plugins.ml_commons.allow_registering_model_via_url": "true",
    "plugins.ml_commons.only_run_on_ml_node": "false",
    "plugins.ml_commons.model_access_control_enabled": "true"
  }
}' > /dev/null

# Function to get model ID from task ID
get_model_id_from_task() {
    local task_id=$1
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local response=$(curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/tasks/${task_id}")
        local state=$(echo $response | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
        
        if [ "$state" = "COMPLETED" ]; then
            # Extract model ID and remove any dots
            local model_id=$(echo $response | grep -o '"model_id":"[^"]*"' | cut -d'"' -f4 | tr -d '.')
            echo $model_id
            return 0
        elif [ "$state" = "FAILED" ]; then
            echo "Task failed: $response" >&2
            return 1
        fi
        
        echo -n "."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    echo -e "\nTask timed out after $max_attempts attempts" >&2
    return 1
}

# Function to check if model exists
check_model_exists() {
    local model_id=$1
    local response=$(curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/${model_id}")
    if [[ $response == *"model_state"* ]] && [[ $response != *"error"* ]]; then
        return 0
    else
        return 1
    fi
}

# Deploy models if not skipped
if [ "$SKIP_MODEL_DEPLOY" = false ]; then
    # Step 1: Register and deploy the text embedding model
    echo -e "\n${GREEN}Step 1: Registering and deploying text embedding model${NC}"
    TEXT_EMBEDDING_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/_register?deploy=true" -H 'Content-Type: application/json' -d'
    {
      "name": "huggingface/sentence-transformers/all-MiniLM-L6-v2",
      "version": "1.0.2",
      "model_format": "TORCH_SCRIPT"
    }')

    TEXT_EMBEDDING_TASK_ID=$(echo $TEXT_EMBEDDING_RESPONSE | grep -o '"task_id":"[^"]*"' | cut -d'"' -f4)
    echo -n "Waiting for text embedding model deployment"
    TEXT_EMBEDDING_MODEL_ID=$(get_model_id_from_task $TEXT_EMBEDDING_TASK_ID)
    if [ $? -ne 0 ]; then
        echo -e "\n${RED}Failed to get text embedding model ID${NC}"
        exit 1
    fi
    echo " Done"
    # Clean up the model ID by removing dots
    TEXT_EMBEDDING_MODEL_ID=$(echo $TEXT_EMBEDDING_MODEL_ID | tr -d '.')
    echo -e "${GREEN}Text Embedding Model ID: ${TEXT_EMBEDDING_MODEL_ID}${NC}"
    
    # Wait a bit more for model to be fully ready
    echo "Waiting for model to be fully deployed..."
    sleep 5

    # Step 2: Register and deploy the semantic highlighting model
    if [ "$SKIP_SEMANTIC_HIGHLIGHTING" = false ]; then
        echo -e "\n${GREEN}Step 2: Registering and deploying semantic highlighting model${NC}"
        SEMANTIC_HIGHLIGHTING_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/_register?deploy=true" -H 'Content-Type: application/json' -d'
        {
          "name": "amazon/sentence-highlighting/opensearch-semantic-highlighter-v1",
          "version": "1.0.0",
          "model_format": "TORCH_SCRIPT",
          "function_name": "QUESTION_ANSWERING"
        }')

        SEMANTIC_HIGHLIGHTING_TASK_ID=$(echo $SEMANTIC_HIGHLIGHTING_RESPONSE | grep -o '"task_id":"[^"]*"' | cut -d'"' -f4)
        echo -n "Waiting for semantic highlighting model deployment"
        SEMANTIC_HIGHLIGHTING_MODEL_ID=$(get_model_id_from_task $SEMANTIC_HIGHLIGHTING_TASK_ID)
        if [ $? -ne 0 ]; then
            echo -e "\n${RED}Failed to get semantic highlighting model ID${NC}"
            exit 1
        fi
        echo " Done"
        # Clean up the model ID by removing dots
        SEMANTIC_HIGHLIGHTING_MODEL_ID=$(echo $SEMANTIC_HIGHLIGHTING_MODEL_ID | tr -d '.')
        echo -e "${GREEN}Semantic Highlighting Model ID: ${SEMANTIC_HIGHLIGHTING_MODEL_ID}${NC}"
    else
        echo -e "\n${GREEN}Step 2: Skipping semantic highlighting model registration${NC}"
    fi
else
    if [ -z "$TEXT_EMBEDDING_MODEL_ID" ]; then
        echo -e "${RED}Error: When skipping model deployment, --text-embedding-model-id must be provided${NC}"
        exit 1
    fi
    if [ "$SKIP_SEMANTIC_HIGHLIGHTING" = false ] && [ -z "$SEMANTIC_HIGHLIGHTING_MODEL_ID" ]; then
        echo -e "${RED}Error: When skipping model deployment and not skipping semantic highlighting, --semantic-highlighting-model-id must be provided${NC}"
        exit 1
    fi
    # Remove any dots from provided model IDs
    TEXT_EMBEDDING_MODEL_ID=$(echo $TEXT_EMBEDDING_MODEL_ID | tr -d '.')
    if [ "$SKIP_SEMANTIC_HIGHLIGHTING" = false ]; then
        SEMANTIC_HIGHLIGHTING_MODEL_ID=$(echo $SEMANTIC_HIGHLIGHTING_MODEL_ID | tr -d '.')
    fi
    echo -e "\n${GREEN}Skipping model deployment, using provided model IDs:${NC}"
    echo -e "${GREEN}Text Embedding Model ID: ${TEXT_EMBEDDING_MODEL_ID}${NC}"
    if [ "$SKIP_SEMANTIC_HIGHLIGHTING" = false ]; then
        echo -e "${GREEN}Semantic Highlighting Model ID: ${SEMANTIC_HIGHLIGHTING_MODEL_ID}${NC}"
    fi
fi

# Verify models exist
echo -e "\n${GREEN}Verifying models exist...${NC}"
if ! check_model_exists $TEXT_EMBEDDING_MODEL_ID; then
    echo -e "${RED}Error: Text embedding model ${TEXT_EMBEDDING_MODEL_ID} not found${NC}"
    exit 1
fi
if [ "$SKIP_SEMANTIC_HIGHLIGHTING" = false ] && ! check_model_exists $SEMANTIC_HIGHLIGHTING_MODEL_ID; then
    echo -e "${RED}Error: Semantic highlighting model ${SEMANTIC_HIGHLIGHTING_MODEL_ID} not found${NC}"
    exit 1
fi
echo -e "${GREEN}Models verified${NC}"

# Step 3: Create index with mappings
if [ "$SKIP_INDEX_CREATION" = false ]; then
    echo -e "\n${GREEN}Step 3: Creating index with mappings${NC}"
    INDEX_RESPONSE=$(curl -s -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}" -H 'Content-Type: application/json' -d'
    {
      "settings": {
        "index.knn": true
      },
      "mappings": {
        "properties": {
          "text": {
            "type": "text"
          },
          "text_embedding": {
            "type": "knn_vector",
            "dimension": 384,
            "method": {
              "name": "hnsw",
              "space_type": "l2",
              "engine": "lucene",
              "parameters": {
                "ef_construction": 128,
                "m": 24
              }
            }
          }
        }
      }
    }')
    if [[ $INDEX_RESPONSE == *"resource_already_exists_exception"* ]]; then
        echo -e "${GREEN}Index already exists, continuing...${NC}"
    elif [[ $INDEX_RESPONSE == *"error"* ]]; then
        echo -e "${RED}Error creating index: $INDEX_RESPONSE${NC}"
        exit 1
    else
        echo -e "${GREEN}Index created with KNN settings${NC}"
    fi
else
    echo -e "\n${GREEN}Step 3: Skipping index creation${NC}"
fi

# Step 4: Configure ingest pipeline
echo -e "\n${GREEN}Step 4: Configuring ingest pipeline${NC}"
PIPELINE_RESPONSE=$(curl -s -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_ingest/pipeline/nlp-ingest-pipeline" -H 'Content-Type: application/json' -d"
{
  \"description\": \"A pipeline to generate text embeddings\",
  \"processors\": [
    {
      \"text_embedding\": {
        \"model_id\": \"${TEXT_EMBEDDING_MODEL_ID}\",
        \"field_map\": {
          \"text\": \"text_embedding\"
        }
      }
    }
  ]
}")
if [[ $PIPELINE_RESPONSE == *"error"* ]]; then
    echo -e "${RED}Error creating pipeline: $PIPELINE_RESPONSE${NC}"
    exit 1
fi
echo -e "${GREEN}Ingest pipeline configured with Text Embedding Model ID: ${TEXT_EMBEDDING_MODEL_ID}${NC}"

# Set default pipeline for the index
SETTINGS_RESPONSE=$(curl -s -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_settings" -H 'Content-Type: application/json' -d'
{
  "index.default_pipeline": "nlp-ingest-pipeline"
}')
if [[ $SETTINGS_RESPONSE == *"error"* ]]; then
    echo -e "${RED}Error setting default pipeline: $SETTINGS_RESPONSE${NC}"
    exit 1
fi
echo -e "${GREEN}Default pipeline set for index${NC}"

# Step 5: Index sample documents
echo -e "\n${GREEN}Step 5: Indexing sample documents${NC}"

# Document 1
DOC1_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_doc/1" -H 'Content-Type: application/json' -d'
{
  "text": "Alzheimers disease is a progressive neurodegenerative disorder characterized by accumulation of amyloid-beta plaques and neurofibrillary tangles in the brain. Early symptoms include short-term memory impairment, followed by language difficulties, disorientation, and behavioral changes. While traditional treatments such as cholinesterase inhibitors and memantine provide modest symptomatic relief, they do not alter disease progression. Recent clinical trials investigating monoclonal antibodies targeting amyloid-beta, including aducanumab, lecanemab, and donanemab, have shown promise in reducing plaque burden and slowing cognitive decline. Early diagnosis using biomarkers such as cerebrospinal fluid analysis and PET imaging may facilitate timely intervention and improved outcomes."
}')
if [[ $DOC1_RESPONSE == *"error"* ]]; then
    echo -e "${RED}Error indexing document 1: $DOC1_RESPONSE${NC}"
    exit 1
fi

# Document 2
DOC2_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_doc/2" -H 'Content-Type: application/json' -d'
{
  "text": "Major depressive disorder is characterized by persistent feelings of sadness, anhedonia, and neurovegetative symptoms affecting sleep, appetite, and energy levels. First-line pharmacological treatments include selective serotonin reuptake inhibitors and serotonin-norepinephrine reuptake inhibitors, with response rates of approximately 60-70 percent. Cognitive-behavioral therapy demonstrates comparable efficacy to medication for mild to moderate depression and may provide more durable benefits. Treatment-resistant depression may respond to augmentation strategies including atypical antipsychotics, lithium, or thyroid hormone. Electroconvulsive therapy remains the most effective intervention for severe or treatment-resistant depression, while newer modalities such as transcranial magnetic stimulation and ketamine infusion offer promising alternatives with fewer side effects."
}')
if [[ $DOC2_RESPONSE == *"error"* ]]; then
    echo -e "${RED}Error indexing document 2: $DOC2_RESPONSE${NC}"
    exit 1
fi

# Document 3
DOC3_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_doc/3" -H 'Content-Type: application/json' -d'
{
  "text": "Cardiovascular disease remains the leading cause of mortality worldwide, accounting for approximately one-third of all deaths. Risk factors include hypertension, diabetes mellitus, smoking, obesity, and family history. Recent advancements in preventive cardiology emphasize lifestyle modifications such as Mediterranean diet, regular exercise, and stress reduction techniques. Pharmacological interventions including statins, beta-blockers, and ACE inhibitors have significantly reduced mortality rates. Emerging treatments focus on inflammation modulation and precision medicine approaches targeting specific genetic profiles associated with cardiac pathologies."
}')
if [[ $DOC3_RESPONSE == *"error"* ]]; then
    echo -e "${RED}Error indexing document 3: $DOC3_RESPONSE${NC}"
    exit 1
fi

echo -e "${GREEN}Sample documents indexed${NC}"

# Refresh the index to make documents available for search
echo -e "${GREEN}Refreshing index for search...${NC}"
curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_refresh" > /dev/null
sleep 2

# Step 6: Perform semantic search with highlighting
echo -e "\n${GREEN}Step 6: Performing semantic search${NC}"
echo -e "${GREEN}Using Text Embedding Model ID: ${TEXT_EMBEDDING_MODEL_ID}${NC}"
if [ "$SKIP_SEMANTIC_HIGHLIGHTING" = false ]; then
    echo -e "${GREEN}Using Semantic Highlighting Model ID: ${SEMANTIC_HIGHLIGHTING_MODEL_ID}${NC}"
    SEARCH_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_search" -H 'Content-Type: application/json' -d"
    {
      \"_source\": {
        \"excludes\": [\"text_embedding\"]
      },
      \"query\": {
        \"neural\": {
          \"text_embedding\": {
            \"query_text\": \"treatments for neurodegenerative diseases\",
            \"model_id\": \"${TEXT_EMBEDDING_MODEL_ID}\",
            \"k\": 2
          }
        }
      },
      \"highlight\": {
        \"fields\": {
          \"text\": {
            \"type\": \"semantic\"
          }
        },
        \"options\": {
          \"model_id\": \"${SEMANTIC_HIGHLIGHTING_MODEL_ID}\"
        }
      }
    }")
else
    echo -e "${GREEN}Skipping semantic highlighting test${NC}"
    SEARCH_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_search" -H 'Content-Type: application/json' -d"
    {
      \"_source\": {
        \"excludes\": [\"text_embedding\"]
      },
      \"query\": {
        \"neural\": {
          \"text_embedding\": {
            \"query_text\": \"treatments for neurodegenerative diseases\",
            \"model_id\": \"${TEXT_EMBEDDING_MODEL_ID}\",
            \"k\": 2
          }
        }
      }
    }")
fi
if [[ $SEARCH_RESPONSE == *"error"* ]]; then
    echo -e "${RED}Error performing search: $SEARCH_RESPONSE${NC}"
    exit 1
fi
echo "$SEARCH_RESPONSE" | jq '.'

echo -e "\n${GREEN}Setup completed!${NC}"
echo -e "\n${GREEN}Final Model IDs:${NC}"
echo "Text Embedding Model ID: ${TEXT_EMBEDDING_MODEL_ID}"
if [ "$SKIP_SEMANTIC_HIGHLIGHTING" = false ]; then
    echo "Semantic Highlighting Model ID: ${SEMANTIC_HIGHLIGHTING_MODEL_ID}"
else
    echo "Semantic highlighting was skipped"
fi

echo -e "\n# To use these model IDs in your shell, run:"
echo "export TEXT_EMBEDDING_MODEL_ID=${TEXT_EMBEDDING_MODEL_ID}"
if [ "$SKIP_SEMANTIC_HIGHLIGHTING" = false ]; then
    echo "export SEMANTIC_HIGHLIGHTING_MODEL_ID=${SEMANTIC_HIGHLIGHTING_MODEL_ID}"
fi 