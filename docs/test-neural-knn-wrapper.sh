#!/bin/bash

# Comprehensive test script for NeuralKNNQueryBuilder wrapper
# Tests various parameter combinations to ensure the fix works correctly

ENDPOINT="http://opense-clust-K4bCaybUk8qn-28f88d52a1777650.elb.us-east-2.amazonaws.com"
INDEX="neural-search-index"
MODEL_ID="HB-ghZcBNFpY2An76khT"

echo "==================================================================="
echo "Testing NeuralKNNQueryBuilder with various parameter combinations"
echo "==================================================================="

# Function to run a test and capture results
run_test() {
    local test_name="$1"
    local query="$2"
    
    echo ""
    echo "-------------------------------------------------------------------"
    echo "TEST: $test_name"
    echo "-------------------------------------------------------------------"
    echo "Query:"
    echo "$query" | jq '.'
    echo ""
    echo "Response:"
    
    response=$(curl -s -X POST "$ENDPOINT/$INDEX/_search" \
        -H 'Content-Type: application/json' \
        -d "$query")
    
    echo "$response" | jq '.'
    
    # Check for errors
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        echo "❌ ERROR DETECTED!"
    elif echo "$response" | jq -e '._shards.failures' > /dev/null 2>&1; then
        echo "❌ SHARD FAILURES DETECTED!"
        echo "$response" | jq '._shards.failures'
    else
        hits=$(echo "$response" | jq '.hits.total.value')
        echo "✅ SUCCESS - Found $hits hits"
    fi
    
    # Wait a bit between tests to allow logs to be written
    sleep 2
}

# Test 1: Neural query with k parameter only (traditional k-NN search)
echo ""
echo "1. Testing with k parameter only (traditional k-NN search)"
run_test "k=5 only" '{
    "_source": {"excludes": ["text_embedding"]},
    "size": 3,
    "query": {
        "neural": {
            "text_embedding": {
                "query_text": "What are the symptoms of heart disease?",
                "model_id": "'$MODEL_ID'",
                "k": 5
            }
        }
    }
}'

# Test 2: Neural query with min_score only (radial search)
echo ""
echo "2. Testing with min_score only (radial search)"
run_test "min_score=0.4 only" '{
    "_source": {"excludes": ["text_embedding"]},
    "size": 3,
    "query": {
        "neural": {
            "text_embedding": {
                "query_text": "What are the main treatments for type 2 diabetes?",
                "model_id": "'$MODEL_ID'",
                "min_score": 0.4
            }
        }
    }
}'

# Test 3: Neural query with max_distance only (radial search)
echo ""
echo "3. Testing with max_distance only (radial search)"
run_test "max_distance=20.0 only" '{
    "_source": {"excludes": ["text_embedding"]},
    "size": 3,
    "query": {
        "neural": {
            "text_embedding": {
                "query_text": "How to prevent cardiovascular problems?",
                "model_id": "'$MODEL_ID'",
                "max_distance": 20.0
            }
        }
    }
}'

# Test 4: Neural query with both k and min_score (should fail)
echo ""
echo "4. Testing with both k and min_score (should fail with validation error)"
run_test "k=5 + min_score=0.4" '{
    "_source": {"excludes": ["text_embedding"]},
    "size": 3,
    "query": {
        "neural": {
            "text_embedding": {
                "query_text": "Cancer treatment options",
                "model_id": "'$MODEL_ID'",
                "k": 5,
                "min_score": 0.4
            }
        }
    }
}'

# Test 5: Neural query with both k and max_distance (should fail)
echo ""
echo "5. Testing with both k and max_distance (should fail with validation error)"
run_test "k=5 + max_distance=20.0" '{
    "_source": {"excludes": ["text_embedding"]},
    "size": 3,
    "query": {
        "neural": {
            "text_embedding": {
                "query_text": "Respiratory disease symptoms",
                "model_id": "'$MODEL_ID'",
                "k": 5,
                "max_distance": 20.0
            }
        }
    }
}'

# Test 6: Neural query with filter and k
echo ""
echo "6. Testing with filter and k parameter"
run_test "k=5 + filter" '{
    "_source": {"excludes": ["text_embedding"]},
    "size": 3,
    "query": {
        "neural": {
            "text_embedding": {
                "query_text": "Kidney disease management",
                "model_id": "'$MODEL_ID'",
                "k": 5,
                "filter": {
                    "range": {
                        "_id": {
                            "gte": "1",
                            "lte": "50"
                        }
                    }
                }
            }
        }
    }
}'

# Test 7: Neural query with filter and min_score
echo ""
echo "7. Testing with filter and min_score"
run_test "min_score=0.4 + filter" '{
    "_source": {"excludes": ["text_embedding"]},
    "size": 3,
    "query": {
        "neural": {
            "text_embedding": {
                "query_text": "Mental health treatment approaches",
                "model_id": "'$MODEL_ID'",
                "min_score": 0.4,
                "filter": {
                    "range": {
                        "_id": {
                            "gte": "10",
                            "lte": "100"
                        }
                    }
                }
            }
        }
    }
}'

# Test 8: Neural query with no k, min_score, or max_distance (should fail)
echo ""
echo "8. Testing with no k, min_score, or max_distance (should fail)"
run_test "no search parameters" '{
    "_source": {"excludes": ["text_embedding"]},
    "size": 3,
    "query": {
        "neural": {
            "text_embedding": {
                "query_text": "General health information",
                "model_id": "'$MODEL_ID'"
            }
        }
    }
}'

echo ""
echo "==================================================================="
echo "All tests completed. Check the results above."
echo "==================================================================="