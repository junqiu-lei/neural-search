#!/bin/bash

# Configuration
# OPENSEARCH_HOST="opense-clust-CePDyxTglAI8-6f22b7d87da3d2d1.elb.us-east-1.amazonaws.com"
# OPENSEARCH_PORT="80"
OPENSEARCH_HOST="localhost"
OPENSEARCH_PORT="9200"
INDEX_NAME="neural-search-index"
DEFAULT_QUERY_COUNT=5
K_VALUES=(1 5 10)

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --index-name NAME               Index name (default: neural-search-index)"
    echo "  --text-embedding-model-id ID    Text embedding model ID (required)"
    echo "   ID  Semantic highlighting model ID (required)"
    echo "  --query-count N                 Number of queries to run per K value (default: 10)"
    echo "  --k-values \"1 3 5 10\"           Space-separated K values to test (default: 1 3 5 10 20 50 100)"
    echo "  --debug                         Show actual query responses (default: false)"
    echo "  --neural-search-only            Disable semantic highlighting for pure neural search performance"
    echo "  --compare-modes                 Run both neural search only and neural search with semantic highlighting for comparison"
    echo "  --help                          Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Test all default K values:"
    echo "  $0 --text-embedding-model-id MODEL1 --semantic-highlighting-model-id MODEL2"
    echo ""
    echo "  # Test specific K values with debug output:"
    echo "  $0 --text-embedding-model-id MODEL1 --semantic-highlighting-model-id MODEL2 --k-values \"1 5 10\" --debug"
    echo ""
    echo "  # Neural search only (no highlighting):"
    echo "  $0 --text-embedding-model-id MODEL1 --neural-search-only --k-values \"1 10 50\""
    echo ""
    echo "  # Compare both modes side by side:"
    echo "  $0 --text-embedding-model-id MODEL1 --semantic-highlighting-model-id MODEL2 --compare-modes"
}

# Parse command line arguments
QUERY_COUNT=$DEFAULT_QUERY_COUNT
TEXT_EMBEDDING_MODEL_ID_ARG=""
SEMANTIC_HIGHLIGHTING_MODEL_ID_ARG=""
DEBUG_MODE=false
NEURAL_SEARCH_ONLY=false
COMPARE_MODES=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --index-name)
      INDEX_NAME="$2"
      shift 2
      ;;
    --text-embedding-model-id)
      TEXT_EMBEDDING_MODEL_ID_ARG="$2"
      shift 2
      ;;
    --semantic-highlighting-model-id)
      SEMANTIC_HIGHLIGHTING_MODEL_ID_ARG="$2"
      shift 2
      ;;
    --query-count)
      QUERY_COUNT="$2"
      shift 2
      ;;
    --k-values)
      IFS=' ' read -ra K_VALUES <<< "$2"
      shift 2
      ;;
    --debug)
      DEBUG_MODE=true
      shift
      ;;
    --neural-search-only)
      NEURAL_SEARCH_ONLY=true
      shift
      ;;
    --compare-modes)
      COMPARE_MODES=true
      shift
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

# Use argument if provided, else fallback to env var
TEXT_EMBEDDING_MODEL_ID="${TEXT_EMBEDDING_MODEL_ID_ARG:-$TEXT_EMBEDDING_MODEL_ID}"
SEMANTIC_HIGHLIGHTING_MODEL_ID="${SEMANTIC_HIGHLIGHTING_MODEL_ID_ARG:-$SEMANTIC_HIGHLIGHTING_MODEL_ID}"

# Validate required parameters
if [ -z "$TEXT_EMBEDDING_MODEL_ID" ]; then
    echo -e "${RED}Error: --text-embedding-model-id is required${NC}"
    echo ""
    show_usage
    exit 1
fi

if [ "$NEURAL_SEARCH_ONLY" = false ] && [ "$COMPARE_MODES" = false ] && [ -z "$SEMANTIC_HIGHLIGHTING_MODEL_ID" ]; then
    echo -e "${RED}Error: --semantic-highlighting-model-id is required unless --neural-search-only is used${NC}"
    echo ""
    show_usage
    exit 1
fi

if [ "$COMPARE_MODES" = true ] && [ -z "$SEMANTIC_HIGHLIGHTING_MODEL_ID" ]; then
    echo -e "${RED}Error: --semantic-highlighting-model-id is required when using --compare-modes${NC}"
    echo ""
    show_usage
    exit 1
fi

# Validate conflicting options
if [ "$NEURAL_SEARCH_ONLY" = true ] && [ "$COMPARE_MODES" = true ]; then
    echo -e "${RED}Error: --neural-search-only and --compare-modes cannot be used together${NC}"
    echo ""
    show_usage
    exit 1
fi

# Remove any dots from model IDs
TEXT_EMBEDDING_MODEL_ID=$(echo $TEXT_EMBEDDING_MODEL_ID | tr -d '.')
if [ "$NEURAL_SEARCH_ONLY" = false ]; then
    SEMANTIC_HIGHLIGHTING_MODEL_ID=$(echo $SEMANTIC_HIGHLIGHTING_MODEL_ID | tr -d '.')
fi

echo -e "${BLUE}Semantic Search Performance Testing${NC}"
echo "=================================="
echo "Index: ${INDEX_NAME}"
echo "Text Embedding Model: ${TEXT_EMBEDDING_MODEL_ID}"
if [ "$NEURAL_SEARCH_ONLY" = false ]; then
    echo "Semantic Highlighting Model: ${SEMANTIC_HIGHLIGHTING_MODEL_ID}"
else
    echo "Mode: Neural Search Only (no highlighting)"
fi
echo "Query Count: ${QUERY_COUNT}"
echo "K Values: ${K_VALUES[@]}"
echo ""

# Array of test queries
declare -a QUERIES=(
    "diabetes treatment medications"
    "heart disease prevention"
    "cancer therapy options"
    "mental health treatment"
    "pain management strategies"
    "blood pressure control"
    "respiratory disease treatment"
    "autoimmune disorder therapy"
    "neurological condition management"
    "kidney disease treatment"
    "liver disease therapy"
    "bone health medications"
    "inflammatory conditions"
    "infection treatment antibiotics"
    "surgical interventions"
    "preventive care measures"
    "chronic disease management"
    "emergency medical treatment"
    "pediatric healthcare"
    "geriatric medicine"
)

# Function to calculate percentile from sorted array
calculate_percentile() {
    local array_name=$1
    local percentile=$2
    
    # Get array values using indirect expansion
    local array_ref="${array_name}[@]"
    local arr=("${!array_ref}")
    local len=${#arr[@]}
    
    if [ $len -eq 0 ]; then
        echo "0"
        return
    fi
    
    # Sort array
    IFS=$'\n' sorted=($(sort -n <<<"${arr[*]}"))
    unset IFS
    
    if [ $percentile -eq 100 ]; then
        echo "${sorted[$((len-1))]}"
    else
        local index=$(echo "scale=0; ($percentile * $len / 100) - 1" | bc -l)
        # Ensure index is within bounds
        if [ $index -lt 0 ]; then
            index=0
        fi
        if [ $index -ge $len ]; then
            index=$((len-1))
        fi
        echo "${sorted[$index]}"
    fi
}

# Function to run performance tests for a specific mode
run_performance_test() {
    local mode_name=$1
    local use_highlighting=$2
    local mode_results_prefix=$3
    
    echo -e "${YELLOW}Testing Mode: $mode_name${NC}"
    echo "=================================================="
    
    # Arrays to store results for each K value for this mode
    local -a MODE_LATENCY_P50=()
    local -a MODE_LATENCY_P90=()
    local -a MODE_LATENCY_P99=()
    local -a MODE_LATENCY_P100=()
    local -a MODE_OPENSEARCH_P50=()
    local -a MODE_OPENSEARCH_P90=()
    local -a MODE_OPENSEARCH_P99=()
    local -a MODE_OPENSEARCH_P100=()
    
    local k_index=0
    
    for k in "${K_VALUES[@]}"; do
        echo -e "${BLUE}Testing K value: $k${NC}"
        
        # Arrays to store results for this K value
        declare -a LATENCIES=()
        declare -a OPENSEARCH_TIMES=()
        declare -a DOCUMENT_LENGTHS=()
        declare -a HIT_COUNTS=()
        declare -a ACTUAL_HITS=()
        
        for ((i=1; i<=QUERY_COUNT; i++)); do
            # Select query (cycle through available queries)
            query_index=$(((i-1) % ${#QUERIES[@]}))
            query="${QUERIES[query_index]}"
            
            echo -n "Query $i/$QUERY_COUNT: \"$query\"... "
            
            # Measure query time using a more reliable method
            start_time=$(python3 -c "import time; print(time.time())")
            
            # Build query with conditional highlighting
            if [ "$use_highlighting" = false ]; then
                # Neural search only - no highlighting
                response=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_search" -H 'Content-Type: application/json' -d"{
                    \"_source\": {
                        \"excludes\": [\"text_embedding\"]
                    },
                    \"size\": $k,
                    \"query\": {
                        \"neural\": {
                            \"text_embedding\": {
                                \"query_text\": \"$query\",
                                \"model_id\": \"${TEXT_EMBEDDING_MODEL_ID}\",
                                \"k\": $k
                            }
                        }
                    }
                }")
            else
                # Neural search with semantic highlighting
                response=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_search" -H 'Content-Type: application/json' -d"{
                    \"_source\": {
                        \"excludes\": [\"text_embedding\"]
                    },
                    \"size\": $k,
                    \"query\": {
                        \"neural\": {
                            \"text_embedding\": {
                                \"query_text\": \"$query\",
                                \"model_id\": \"${TEXT_EMBEDDING_MODEL_ID}\",
                                \"k\": $k
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
            fi
            
            end_time=$(python3 -c "import time; print(time.time())")
            
            # Calculate latency in milliseconds with better precision
            latency=$(python3 -c "print(int(round(($end_time - $start_time) * 1000)))")
            
            # Extract OpenSearch's internal "took" time
            opensearch_took=$(echo "$response" | grep -o '"took":[0-9]*' | cut -d':' -f2)
            
            # Extract hit count
            hit_count=$(echo "$response" | jq -r '.hits.total.value')
            actual_hits=$(echo "$response" | jq -r '.hits.hits | length')
            HIT_COUNTS+=($hit_count)
            ACTUAL_HITS+=($actual_hits)
            
            # Extract and analyze document lengths if highlighting is enabled
            if [ "$use_highlighting" = true ]; then
                # Use jq to extract text lengths from hits
                doc_lengths=$(echo "$response" | jq -r '.hits.hits[]._source.text | length')
                
                # Store lengths for statistics
                if [ ! -z "$doc_lengths" ]; then
                    for length in $doc_lengths; do
                        DOCUMENT_LENGTHS+=($length)
                    done
                fi
            fi
            
            # Check for errors
            if [[ $response == *"\"error\":"* ]] || [[ $response == *"\"errors\":true"* ]]; then
                echo -e "${RED}ERROR${NC}"
                echo "Response: $response"
                exit 1
            fi
            
            # Store results
            LATENCIES+=($latency)
            if [ ! -z "$opensearch_took" ]; then
                OPENSEARCH_TIMES+=($opensearch_took)
            fi
            
            echo "${latency}ms (OpenSearch: ${opensearch_took}ms)"
            
            # Show debug output if enabled
            if [ "$DEBUG_MODE" = true ]; then
                echo -e "${BLUE}=== DEBUG: Query Response ===${NC}"
                echo "Query: \"$query\""
                echo "K Value: $k"
                echo "Mode: $mode_name"
                echo "Response:"
                echo "$response" | jq '.' 2>/dev/null || echo "$response"
                echo -e "${BLUE}=== END DEBUG ===${NC}"
                echo ""
            fi
        done
        
        # Calculate percentiles for this K value and store in arrays
        if [ ${#LATENCIES[@]} -gt 0 ]; then
            MODE_LATENCY_P50[$k_index]=$(calculate_percentile LATENCIES 50)
            MODE_LATENCY_P90[$k_index]=$(calculate_percentile LATENCIES 90)
            MODE_LATENCY_P99[$k_index]=$(calculate_percentile LATENCIES 99)
            MODE_LATENCY_P100[$k_index]=$(calculate_percentile LATENCIES 100)
        fi
        
        if [ ${#OPENSEARCH_TIMES[@]} -gt 0 ]; then
            MODE_OPENSEARCH_P50[$k_index]=$(calculate_percentile OPENSEARCH_TIMES 50)
            MODE_OPENSEARCH_P90[$k_index]=$(calculate_percentile OPENSEARCH_TIMES 90)
            MODE_OPENSEARCH_P99[$k_index]=$(calculate_percentile OPENSEARCH_TIMES 99)
            MODE_OPENSEARCH_P100[$k_index]=$(calculate_percentile OPENSEARCH_TIMES 100)
        fi
        
        # After the k-value loop, calculate and display document length statistics
        if [ "$use_highlighting" = true ] && [ ${#DOCUMENT_LENGTHS[@]} -gt 0 ]; then
            echo -e "\n${BLUE}Document Length Statistics:${NC}"
            echo "----------------------------------------"
            
            # Sort lengths for percentile calculation
            IFS=$'\n' sorted_lengths=($(sort -n <<<"${DOCUMENT_LENGTHS[*]}"))
            unset IFS
            
            total_docs=${#DOCUMENT_LENGTHS[@]}
            total_length=0
            min_length=${sorted_lengths[0]}
            max_length=${sorted_lengths[$((total_docs-1))]}
            
            # Calculate total and average
            for length in "${DOCUMENT_LENGTHS[@]}"; do
                total_length=$((total_length + length))
            done
            avg_length=$((total_length / total_docs))
            
            # Calculate p50, p90, p99
            p50_idx=$((total_docs * 50 / 100))
            p90_idx=$((total_docs * 90 / 100))
            p99_idx=$((total_docs * 99 / 100))
            
            p50_length=${sorted_lengths[$p50_idx]}
            p90_length=${sorted_lengths[$p90_idx]}
            p99_length=${sorted_lengths[$p99_idx]}
            
            echo "Total Documents Analyzed: $total_docs"
            echo "Average Length: $avg_length characters"
            echo "Min Length: $min_length characters"
            echo "Max Length: $max_length characters"
            echo "p50 Length: $p50_length characters"
            echo "p90 Length: $p90_length characters"
            echo "p99 Length: $p99_length characters"
            echo "----------------------------------------"
        fi

        # Display hit count statistics
        echo -e "\n${BLUE}Hit Count Statistics for K=$k${NC}"
        echo "----------------------------------------"
        
        # Sort hit counts for percentile calculation
        IFS=$'\n' sorted_hits=($(sort -n <<<"${HIT_COUNTS[*]}"))
        IFS=$'\n' sorted_actual=($(sort -n <<<"${ACTUAL_HITS[*]}"))
        unset IFS
        
        total_queries=${#HIT_COUNTS[@]}
        
        # Calculate statistics for total available hits
        min_hits=${sorted_hits[0]}
        max_hits=${sorted_hits[$((total_queries-1))]}
        sum_hits=0
        for hits in "${HIT_COUNTS[@]}"; do
            sum_hits=$((sum_hits + hits))
        done
        avg_hits=$((sum_hits / total_queries))
        
        # Calculate statistics for actual returned hits
        min_actual=${sorted_actual[0]}
        max_actual=${sorted_actual[$((total_queries-1))]}
        sum_actual=0
        for hits in "${ACTUAL_HITS[@]}"; do
            sum_actual=$((sum_actual + hits))
        done
        avg_actual=$((sum_actual / total_queries))
        
        # Count queries that returned fewer hits than K
        under_k_count=0
        for hits in "${ACTUAL_HITS[@]}"; do
            if [ "$hits" -lt "$k" ]; then
                under_k_count=$((under_k_count + 1))
            fi
        done
        under_k_percent=$((under_k_count * 100 / total_queries))
        
        echo "Total Available Hits (from total.value):"
        echo "  Minimum: $min_hits"
        echo "  Maximum: $max_hits"
        echo "  Average: $avg_hits"
        echo ""
        echo "Actually Returned Hits:"
        echo "  Minimum: $min_actual"
        echo "  Maximum: $max_actual"
        echo "  Average: $avg_actual"
        echo "  Queries with < $k hits: $under_k_count ($under_k_percent%)"
        echo "----------------------------------------"
        
        k_index=$((k_index + 1))
        echo ""
    done
    
    # Store results in global arrays with mode prefix
    eval "${mode_results_prefix}_LATENCY_P50=(\"\${MODE_LATENCY_P50[@]}\")"
    eval "${mode_results_prefix}_LATENCY_P90=(\"\${MODE_LATENCY_P90[@]}\")"
    eval "${mode_results_prefix}_LATENCY_P99=(\"\${MODE_LATENCY_P99[@]}\")"
    eval "${mode_results_prefix}_LATENCY_P100=(\"\${MODE_LATENCY_P100[@]}\")"
    eval "${mode_results_prefix}_OPENSEARCH_P50=(\"\${MODE_OPENSEARCH_P50[@]}\")"
    eval "${mode_results_prefix}_OPENSEARCH_P90=(\"\${MODE_OPENSEARCH_P90[@]}\")"
    eval "${mode_results_prefix}_OPENSEARCH_P99=(\"\${MODE_OPENSEARCH_P99[@]}\")"
    eval "${mode_results_prefix}_OPENSEARCH_P100=(\"\${MODE_OPENSEARCH_P100[@]}\")"
    
    echo -e "${GREEN}$mode_name testing completed!${NC}"
    echo ""
}

# Use seconds instead of milliseconds for calculations
start_total_time=$(date +%s)

echo -e "${GREEN}Starting performance test...${NC}"

# Run tests based on mode
if [ "$COMPARE_MODES" = true ]; then
    # Run both modes for comparison
    run_performance_test "Neural Search with Semantic Highlighting" true "HIGHLIGHTING"
    run_performance_test "Neural Search Only" false "NEURAL_ONLY"
elif [ "$NEURAL_SEARCH_ONLY" = true ]; then
    # Run only neural search
    run_performance_test "Neural Search Only" false "RESULTS"
else
    # Run only neural search with highlighting
    run_performance_test "Neural Search with Semantic Highlighting" true "RESULTS"
fi

end_total_time=$(date +%s)
total_time=$((end_total_time - start_total_time))

echo ""
echo -e "${YELLOW}Performance Results${NC}"
echo "==================="

# Add timestamp to results
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')
echo ""
echo "**Test Execution Time**: $TIMESTAMP"

if [ "$COMPARE_MODES" = true ]; then
    # Output comparison tables with separate columns
    echo ""
    echo "## Total Latency Comparison (including network) - Milliseconds"
    echo ""
    echo "| K Value | With Highlighting p50 | p90 | p99 | p100 | Neural Only p50 | p90 | p99 | p100 |"
    echo "|---------|----------------------|-----|-----|------|-----------------|-----|-----|------|"
    k_index=0
    for k in "${K_VALUES[@]}"; do
        # Get highlighting results
        eval "h_p50=\${HIGHLIGHTING_LATENCY_P50[$k_index]:-N/A}"
        eval "h_p90=\${HIGHLIGHTING_LATENCY_P90[$k_index]:-N/A}"
        eval "h_p99=\${HIGHLIGHTING_LATENCY_P99[$k_index]:-N/A}"
        eval "h_p100=\${HIGHLIGHTING_LATENCY_P100[$k_index]:-N/A}"
        
        # Get neural only results
        eval "n_p50=\${NEURAL_ONLY_LATENCY_P50[$k_index]:-N/A}"
        eval "n_p90=\${NEURAL_ONLY_LATENCY_P90[$k_index]:-N/A}"
        eval "n_p99=\${NEURAL_ONLY_LATENCY_P99[$k_index]:-N/A}"
        eval "n_p100=\${NEURAL_ONLY_LATENCY_P100[$k_index]:-N/A}"
        
        echo "| $k | $h_p50 | $h_p90 | $h_p99 | $h_p100 | $n_p50 | $n_p90 | $n_p99 | $n_p100 |"
        k_index=$((k_index + 1))
    done

    echo ""
    echo "## OpenSearch Processing Time Comparison - Milliseconds"
    echo ""
    echo "| K Value | With Highlighting p50 | p90 | p99 | p100 | Neural Only p50 | p90 | p99 | p100 |"
    echo "|---------|----------------------|-----|-----|------|-----------------|-----|-----|------|"
    k_index=0
    for k in "${K_VALUES[@]}"; do
        # Get highlighting results
        eval "h_p50=\${HIGHLIGHTING_OPENSEARCH_P50[$k_index]:-N/A}"
        eval "h_p90=\${HIGHLIGHTING_OPENSEARCH_P90[$k_index]:-N/A}"
        eval "h_p99=\${HIGHLIGHTING_OPENSEARCH_P99[$k_index]:-N/A}"
        eval "h_p100=\${HIGHLIGHTING_OPENSEARCH_P100[$k_index]:-N/A}"
        
        # Get neural only results
        eval "n_p50=\${NEURAL_ONLY_OPENSEARCH_P50[$k_index]:-N/A}"
        eval "n_p90=\${NEURAL_ONLY_OPENSEARCH_P90[$k_index]:-N/A}"
        eval "n_p99=\${NEURAL_ONLY_OPENSEARCH_P99[$k_index]:-N/A}"
        eval "n_p100=\${NEURAL_ONLY_OPENSEARCH_P100[$k_index]:-N/A}"
        
        echo "| $k | $h_p50 | $h_p90 | $h_p99 | $h_p100 | $n_p50 | $n_p90 | $n_p99 | $n_p100 |"
        k_index=$((k_index + 1))
    done
else
    # Output single mode tables (existing format)
    echo ""
    echo "## Total Latency (including network) - Milliseconds"
    echo ""
    echo "| K Value | p50 | p90 | p99 | p100 |"
    echo "|---------|-----|-----|-----|------|"
    k_index=0
    for k in "${K_VALUES[@]}"; do
        eval "p50=\${RESULTS_LATENCY_P50[$k_index]:-N/A}"
        eval "p90=\${RESULTS_LATENCY_P90[$k_index]:-N/A}"
        eval "p99=\${RESULTS_LATENCY_P99[$k_index]:-N/A}"
        eval "p100=\${RESULTS_LATENCY_P100[$k_index]:-N/A}"
        echo "| $k | $p50 | $p90 | $p99 | $p100 |"
        k_index=$((k_index + 1))
    done

    echo ""
    echo "## OpenSearch Processing Time - Milliseconds"
    echo ""
    echo "| K Value | p50 | p90 | p99 | p100 |"
    echo "|---------|-----|-----|-----|------|"
    k_index=0
    for k in "${K_VALUES[@]}"; do
        eval "p50=\${RESULTS_OPENSEARCH_P50[$k_index]:-N/A}"
        eval "p90=\${RESULTS_OPENSEARCH_P90[$k_index]:-N/A}"
        eval "p99=\${RESULTS_OPENSEARCH_P99[$k_index]:-N/A}"
        eval "p100=\${RESULTS_OPENSEARCH_P100[$k_index]:-N/A}"
        echo "| $k | $p50 | $p90 | $p99 | $p100 |"
        k_index=$((k_index + 1))
    done
fi

echo ""
echo "## Summary"
echo ""
if [ "$COMPARE_MODES" = true ]; then
    echo "- **Test Mode**: Comparison (Neural Search + Semantic Highlighting vs Neural Search Only)"
    echo "- **Total K Values Tested**: ${#K_VALUES[@]}"
    echo "- **Queries per K Value per Mode**: $QUERY_COUNT"
    echo "- **Total Queries**: $((QUERY_COUNT * ${#K_VALUES[@]} * 2))"
else
    echo "- **Total K Values Tested**: ${#K_VALUES[@]}"
    echo "- **Queries per K Value**: $QUERY_COUNT"
    echo "- **Total Queries**: $((QUERY_COUNT * ${#K_VALUES[@]}))"
fi
echo "- **Total Test Time**: ${total_time}s"
echo ""

echo -e "${GREEN}Performance test completed!${NC}" 