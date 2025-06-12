#!/bin/bash

# Configuration
# OPENSEARCH_HOST="opense-clust-CePDyxTglAI8-6f22b7d87da3d2d1.elb.us-east-1.amazonaws.com"
# OPENSEARCH_PORT="80"
OPENSEARCH_HOST="localhost"
OPENSEARCH_PORT="9200"
INDEX_NAME="neural-search-index"

# AWS Credentials Configuration (for SageMaker remote models)
# 安全提示：请勿在脚本中硬编码AWS凭证！
# 使用以下方法之一来配置AWS凭证：
# 1. AWS配置文件：aws configure
# 2. 环境变量：AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN  
# 3. IAM角色（推荐用于EC2实例）
# 4. AWS SSO

# 脚本将使用以下优先级获取AWS凭证：
# 1. 环境变量
# 2. AWS配置文件 (~/.aws/credentials)  
# 3. IAM角色

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --use-local-models              Use local models instead of remote SageMaker models (default: false)"
    echo "  --skip-model-deploy             Skip model deployment (use existing models)"
    echo "  --skip-index-creation           Skip index creation (use existing index)"
    echo "  --skip-semantic-highlighting    Skip semantic highlighting model registration and test"
    echo "  --skip-ingest                   Skip document ingestion after setup"
    echo "  --text-embedding-model-id ID    Text embedding model ID (required with --skip-model-deploy)"
    echo "  --semantic-highlighting-model-id ID  Semantic highlighting model ID (required with --skip-model-deploy)"
    echo "  --sagemaker-endpoint NAME       SageMaker endpoint name for semantic highlighting (default: semantic-highlighter-20250613225303)"
    echo "  --aws-region REGION             AWS region for SageMaker (default: us-east-1)"
    echo "  --help                          Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Default: Use remote SageMaker models and create everything from scratch:"
    echo "  $0"
    echo ""
    echo "  # Use local models:"
    echo "  $0 --use-local-models"
    echo ""
    echo "  # Use custom SageMaker endpoint:"
    echo "  $0 --sagemaker-endpoint my-custom-endpoint --aws-region us-west-2"
    echo ""
    echo "  # Use existing models:"
    echo "  $0 --skip-model-deploy --text-embedding-model-id MODEL1 --semantic-highlighting-model-id MODEL2"
    echo ""
    echo "  # Use existing models and index:"
    echo "  $0 --skip-model-deploy --skip-index-creation --text-embedding-model-id MODEL1 --semantic-highlighting-model-id MODEL2"
    echo ""
    echo "  # Only set up text embedding without semantic highlighting:"
    echo "  $0 --skip-semantic-highlighting"
    echo ""
    echo "  # Setup without document ingestion:"
    echo "  $0 --skip-ingest"
}

# Parse command line arguments
USE_LOCAL_MODELS=false
SKIP_MODEL_DEPLOY=false
SKIP_INDEX_CREATION=false
SKIP_SEMANTIC_HIGHLIGHTING=false
SKIP_INGEST=false
TEXT_EMBEDDING_MODEL_ID=""
SEMANTIC_HIGHLIGHTING_MODEL_ID=""
SAGEMAKER_ENDPOINT="semantic-highlighter-20250613225303"
AWS_REGION="us-east-1"

while [[ $# -gt 0 ]]; do
  case $1 in
    --use-local-models)
      USE_LOCAL_MODELS=true
      shift
      ;;
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
    --skip-ingest)
      SKIP_INGEST=true
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
    --sagemaker-endpoint)
      SAGEMAKER_ENDPOINT="$2"
      shift 2
      ;;
    --aws-region)
      AWS_REGION="$2"
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

if [ "$USE_LOCAL_MODELS" = true ]; then
    echo "Setting up Semantic Search with Highlighting (Local Models Mode)"
else
    echo "Setting up Semantic Search with Highlighting (Remote SageMaker Models Mode)"
    echo "SageMaker Endpoint: ${SAGEMAKER_ENDPOINT}"
    echo "AWS Region: ${AWS_REGION}"
fi

# Pre-flight checks
echo -e "\n${GREEN}Running pre-flight checks...${NC}"

# Check OpenSearch cluster health
echo -e "${GREEN}Checking OpenSearch cluster connectivity...${NC}"
CLUSTER_HEALTH=$(curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_cluster/health" 2>/dev/null)
if [[ $? -ne 0 ]] || [[ $CLUSTER_HEALTH == *"error"* ]] || [[ -z "$CLUSTER_HEALTH" ]]; then
    echo -e "${RED}Error: Cannot connect to OpenSearch cluster at ${OPENSEARCH_HOST}:${OPENSEARCH_PORT}${NC}"
    echo -e "${RED}Please ensure OpenSearch is running and accessible${NC}"
    exit 1
fi

CLUSTER_STATUS=$(echo $CLUSTER_HEALTH | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
echo -e "${GREEN}OpenSearch cluster status: ${CLUSTER_STATUS}${NC}"

if [[ "$CLUSTER_STATUS" == "red" ]]; then
    echo -e "${RED}Warning: OpenSearch cluster status is RED. Some functionality may not work properly.${NC}"
    read -p "Do you want to continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check AWS credentials if using remote models
if [ "$USE_LOCAL_MODELS" = false ] && [ "$SKIP_SEMANTIC_HIGHLIGHTING" = false ]; then
    echo -e "${GREEN}Validating AWS credentials...${NC}"
    
    # 检查AWS凭证是否可用（通过AWS CLI默认凭证链）
    echo "检查AWS凭证配置..."
    
    # Check if credentials are valid
    AWS_IDENTITY=$(aws sts get-caller-identity --region "$AWS_REGION" 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$AWS_IDENTITY" ]]; then
        echo -e "${RED}错误：AWS凭证无效或已过期${NC}"
        echo -e "${RED}请配置AWS凭证：${NC}"
        echo -e "${RED}  1. 运行 'aws configure' 配置凭证${NC}"
        echo -e "${RED}  2. 或设置环境变量 AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY${NC}"
        echo -e "${RED}  3. 或使用IAM角色${NC}"
        exit 1
    fi
    
    AWS_ACCOUNT=$(echo "$AWS_IDENTITY" | jq -r '.Account')
    AWS_USER_ARN=$(echo "$AWS_IDENTITY" | jq -r '.Arn')
    echo -e "${GREEN}AWS credentials valid for account: ${AWS_ACCOUNT}${NC}"
    echo -e "${GREEN}User ARN: ${AWS_USER_ARN}${NC}"
    
    # Check if SageMaker endpoint exists and is accessible
    echo -e "${GREEN}检查SageMaker端点: ${SAGEMAKER_ENDPOINT}${NC}"
    ENDPOINT_STATUS=$(aws sagemaker describe-endpoint --endpoint-name "$SAGEMAKER_ENDPOINT" --region "$AWS_REGION" 2>&1)
    ENDPOINT_CHECK_EXIT_CODE=$?
    
    if [[ $ENDPOINT_CHECK_EXIT_CODE -ne 0 ]]; then
        if [[ $ENDPOINT_STATUS == *"InvalidClientTokenId"* ]] || [[ $ENDPOINT_STATUS == *"UnrecognizedClientException"* ]]; then
            echo -e "${RED}错误：AWS凭证无效或已过期${NC}"
            echo -e "${RED}您的临时凭证可能已过期。请重新配置AWS凭证：${NC}"
            echo -e "${RED}  1. 重新运行 'aws configure' 或 'aws sso login'${NC}"
            echo -e "${RED}  2. 或更新环境变量中的凭证${NC}"
            exit 1
        elif [[ $ENDPOINT_STATUS == *"does not exist"* ]]; then
            echo -e "${RED}警告：SageMaker端点 '${SAGEMAKER_ENDPOINT}' 在区域 '${AWS_REGION}' 中不存在${NC}"
            echo -e "${RED}可能的原因：${NC}"
            echo -e "${RED}  1. 端点名称错误${NC}"
            echo -e "${RED}  2. 区域设置错误${NC}"
            echo -e "${RED}  3. 端点已被删除${NC}"
        else
            echo -e "${RED}警告：无法访问SageMaker端点 '${SAGEMAKER_ENDPOINT}' 在区域 '${AWS_REGION}'${NC}"
            echo -e "${RED}错误详情：${ENDPOINT_STATUS}${NC}"
            echo -e "${RED}请检查端点名称、区域设置和您的AWS权限${NC}"
        fi
        read -p "是否仍要继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        ENDPOINT_STATUS_VALUE=$(echo "$ENDPOINT_STATUS" | jq -r '.EndpointStatus')
        echo -e "${GREEN}SageMaker端点状态: ${ENDPOINT_STATUS_VALUE}${NC}"
        
        if [[ "$ENDPOINT_STATUS_VALUE" != "InService" ]]; then
            echo -e "${RED}警告：SageMaker端点不处于'InService'状态${NC}"
            echo -e "${RED}当前状态：${ENDPOINT_STATUS_VALUE}${NC}"
            echo -e "${RED}可能需要等待端点启动完成，或者端点存在问题${NC}"
            read -p "是否仍要继续？(y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
fi

echo -e "${GREEN}Pre-flight checks completed successfully!${NC}"

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

# Function to create SageMaker connector
create_sagemaker_connector() {
    local endpoint_name="$1"
    local region="$2"
    echo -e "\n${GREEN}Creating SageMaker connector for endpoint: ${endpoint_name}${NC}" >&2
    # 获取AWS凭证（从环境变量或AWS配置文件）
    local access_key=""
    local secret_key=""
    local session_token=""
    # 优先使用环境变量
    if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
        access_key="$AWS_ACCESS_KEY_ID"
        secret_key="$AWS_SECRET_ACCESS_KEY"
        session_token="$AWS_SESSION_TOKEN"
    else
        # 尝试从AWS配置文件获取凭证
        access_key=$(aws configure get aws_access_key_id 2>/dev/null)
        secret_key=$(aws configure get aws_secret_access_key 2>/dev/null)
        session_token=$(aws configure get aws_session_token 2>/dev/null)
    fi
    if [ -z "$access_key" ] || [ -z "$secret_key" ]; then
        echo -e "${RED}错误：无法获取AWS凭证${NC}" >&2
        echo -e "${RED}请配置AWS凭证：${NC}" >&2
        echo -e "${RED}  1. 运行 'aws configure' 配置凭证${NC}" >&2
        echo -e "${RED}  2. 或设置环境变量 AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY${NC}" >&2
        exit 1
    fi
    # Build credential object using jq for proper JSON formatting
    local credential_json
    if [ -n "$session_token" ]; then
        credential_json=$(jq -nc --arg ak "$access_key" --arg sk "$secret_key" --arg st "$session_token" '{access_key: $ak, secret_key: $sk, session_token: $st}')
    else
        credential_json=$(jq -nc --arg ak "$access_key" --arg sk "$secret_key" '{access_key: $ak, secret_key: $sk}')
    fi
    # Build connector JSON using jq for proper JSON formatting
    local connector_json
    connector_json=$(jq -nc \
        --arg name "semantic-highlighter-connector-remote" \
        --arg desc "Connector for semantic highlighter SageMaker endpoint" \
        --arg endpoint "runtime.sagemaker.${region}.amazonaws.com" \
        --arg model "$endpoint_name" \
        --arg service "sagemaker" \
        --arg region "$region" \
        --arg url "https://runtime.sagemaker.${region}.amazonaws.com/endpoints/${endpoint_name}/invocations" \
        --argjson cred "$credential_json" \
        '{
            name: $name,
            description: $desc,
            version: 1,
            protocol: "aws_sigv4",
            parameters: {
                endpoint: $endpoint,
                model: $model,
                service_name: $service,
                region: $region
            },
            credential: $cred,
            actions: [{
                action_type: "predict",
                method: "POST",
                url: $url,
                headers: {
                    "Content-Type": "application/json"
                },
                request_body: "{ \"question\": \"${parameters.question}\", \"context\": \"${parameters.context}\" }",
                pre_process_function: "if (params.question != null && params.context != null) { return \"{\\\"parameters\\\":{\\\"question\\\":\\\"\" + params.question + \"\\\",\\\"context\\\":\\\"\" + params.context + \"\\\"}}\"; } else { throw new IllegalArgumentException(\"Missing required parameters: question and context\"); }"
            }]
        }')
    
    local connector_response=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/connectors/_create" \
        -H 'Content-Type: application/json' \
        -d "$connector_json")
    
    if [[ $connector_response == *"error"* ]]; then
        echo -e "${RED}Error creating SageMaker connector: $connector_response${NC}" >&2
        exit 1
    fi
    
    local connector_id=$(echo "$connector_response" | jq -r '.connector_id')
    if [ "$connector_id" = "null" ] || [ -z "$connector_id" ]; then
        echo -e "${RED}Failed to extract connector ID from response: $connector_response${NC}" >&2
        exit 1
    fi
    
    echo -e "${GREEN}SageMaker connector created with ID: ${connector_id}${NC}" >&2
    echo "$connector_id"
}

# Function to register remote model
register_remote_model() {
    local connector_id="$1"
    local model_name="$2"
    
    echo -e "\n${GREEN}Registering remote model: ${model_name}${NC}" >&2
    
    # Build register JSON using jq for proper JSON formatting
    local register_json
    register_json=$(jq -nc \
        --arg name "$model_name" \
        --arg desc "Remote semantic highlighter model for text highlighting" \
        --arg cid "$connector_id" \
        '{
            name: $name,
            function_name: "remote",
            description: $desc,
            connector_id: $cid
        }')
    
    local register_response=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/_register?deploy=true" \
        -H 'Content-Type: application/json' \
        -d "$register_json")
    
    if [[ $register_response == *"error"* ]]; then
        echo -e "${RED}Error registering remote model: $register_response${NC}" >&2
        exit 1
    fi
    
    local task_id=$(echo "$register_response" | jq -r '.task_id')
    if [ "$task_id" = "null" ] || [ -z "$task_id" ]; then
        echo -e "${RED}Failed to extract task ID from response: $register_response${NC}" >&2
        exit 1
    fi
    
    echo -n "Waiting for remote model registration" >&2
    local model_id=$(get_model_id_from_task "$task_id")
    if [ $? -ne 0 ]; then
        echo -e "\n${RED}Failed to get remote model ID${NC}" >&2
        exit 1
    fi
    echo " Done" >&2
    
    # Clean up the model ID by removing dots
    model_id=$(echo "$model_id" | tr -d '.')
    echo -e "${GREEN}Remote model registered with ID: ${model_id}${NC}" >&2
    echo "$model_id"
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
    
    # Wait longer for model to be fully ready
    echo "Waiting for model to be fully deployed..."
    sleep 15

    # Step 2: Register and deploy the semantic highlighting model
    if [ "$SKIP_SEMANTIC_HIGHLIGHTING" = false ]; then
        if [ "$USE_LOCAL_MODELS" = true ]; then
            echo -e "\n${GREEN}Step 2: Registering and deploying local semantic highlighting model${NC}"
            SEMANTIC_HIGHLIGHTING_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/_register?deploy=true" -H 'Content-Type: application/json' -d'
            {
              "name": "amazon/sentence-highlighting/opensearch-semantic-highlighter-v1",
              "version": "1.0.0",
              "model_format": "TORCH_SCRIPT",
              "function_name": "QUESTION_ANSWERING"
            }')

            SEMANTIC_HIGHLIGHTING_TASK_ID=$(echo $SEMANTIC_HIGHLIGHTING_RESPONSE | grep -o '"task_id":"[^"]*"' | cut -d'"' -f4)
            echo -n "Waiting for local semantic highlighting model deployment"
            SEMANTIC_HIGHLIGHTING_MODEL_ID=$(get_model_id_from_task $SEMANTIC_HIGHLIGHTING_TASK_ID)
            if [ $? -ne 0 ]; then
                echo -e "\n${RED}Failed to get local semantic highlighting model ID${NC}"
                exit 1
            fi
            echo " Done"
            # Clean up the model ID by removing dots
            SEMANTIC_HIGHLIGHTING_MODEL_ID=$(echo $SEMANTIC_HIGHLIGHTING_MODEL_ID | tr -d '.')
            echo -e "${GREEN}Local Semantic Highlighting Model ID: ${SEMANTIC_HIGHLIGHTING_MODEL_ID}${NC}"
        else
            echo -e "\n${GREEN}Step 2: Setting up remote semantic highlighting model${NC}"
            # Create SageMaker connector
            CONNECTOR_ID=$(create_sagemaker_connector "$SAGEMAKER_ENDPOINT" "$AWS_REGION")
            
            # Register remote model
            SEMANTIC_HIGHLIGHTING_MODEL_ID=$(register_remote_model "$CONNECTOR_ID" "semantic-highlighter-remote")
            echo -e "${GREEN}Remote Semantic Highlighting Model ID: ${SEMANTIC_HIGHLIGHTING_MODEL_ID}${NC}"
            
            # Wait for remote model to be fully ready
            echo "Waiting for remote semantic highlighting model to be fully deployed..."
            sleep 10
        fi
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

# Save model IDs to file for other scripts to use
MODEL_IDS_FILE="model_ids.txt"
echo -e "\n${GREEN}Saving model IDs to ${MODEL_IDS_FILE}...${NC}"

# Create the directory if it doesn't exist
mkdir -p "$(dirname "$MODEL_IDS_FILE")"

# Write model IDs to file with timestamp
cat > "$MODEL_IDS_FILE" << EOF
# Neural Search Model IDs
# Generated on: $(date '+%Y-%m-%d %H:%M:%S %Z')
# Setup script: $0
# Configuration: Index=${INDEX_NAME}, Use Local Models=${USE_LOCAL_MODELS}

TEXT_EMBEDDING_MODEL_ID=${TEXT_EMBEDDING_MODEL_ID}
EOF

if [ "$SKIP_SEMANTIC_HIGHLIGHTING" = false ]; then
    echo "SEMANTIC_HIGHLIGHTING_MODEL_ID=${SEMANTIC_HIGHLIGHTING_MODEL_ID}" >> "$MODEL_IDS_FILE"
else
    echo "# SEMANTIC_HIGHLIGHTING_MODEL_ID=<not configured>" >> "$MODEL_IDS_FILE"
fi

# Add export statements for convenience
cat >> "$MODEL_IDS_FILE" << EOF

# To use these in your shell, run:
# source ${MODEL_IDS_FILE}
# Or copy the export commands below:
export TEXT_EMBEDDING_MODEL_ID=${TEXT_EMBEDDING_MODEL_ID}
EOF

if [ "$SKIP_SEMANTIC_HIGHLIGHTING" = false ]; then
    echo "export SEMANTIC_HIGHLIGHTING_MODEL_ID=${SEMANTIC_HIGHLIGHTING_MODEL_ID}" >> "$MODEL_IDS_FILE"
fi

echo -e "${GREEN}Model IDs saved to ${MODEL_IDS_FILE}${NC}"

# Step 7: Run document ingestion if not skipped
if [ "$SKIP_INGEST" = false ]; then
    echo -e "\n${GREEN}Step 7: Running document ingestion...${NC}"
    
    # Check if ingest script exists
    INGEST_SCRIPT="bin/dev/2_ingest.sh"
    if [ ! -f "$INGEST_SCRIPT" ]; then
        echo -e "${RED}Warning: Ingest script not found at ${INGEST_SCRIPT}${NC}"
        echo -e "${RED}Please run the ingest script manually: bash ${INGEST_SCRIPT} --index-name ${INDEX_NAME}${NC}"
    else
        echo -e "${GREEN}Calling ingest script: ${INGEST_SCRIPT}${NC}"
        bash "$INGEST_SCRIPT" --index-name "$INDEX_NAME"
        
        if [ $? -eq 0 ]; then
            echo -e "\n${GREEN}Document ingestion completed successfully!${NC}"
        else
            echo -e "\n${RED}Document ingestion failed. You can run it manually later:${NC}"
            echo -e "${RED}bash ${INGEST_SCRIPT} --index-name ${INDEX_NAME}${NC}"
        fi
    fi
else
    echo -e "\n${GREEN}Step 7: Skipping document ingestion${NC}"
    echo -e "${GREEN}To ingest documents later, run:${NC}"
    echo "bash bin/dev/2_ingest.sh --index-name ${INDEX_NAME}"
fi

echo -e "\n${GREEN}🎉 All setup tasks completed!${NC}" 