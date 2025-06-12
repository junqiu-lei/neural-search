#!/bin/bash

echo "=== 延迟测试方法对比分析 ==="
echo "目标：分析不同时间测量方法的准确性"
echo ""

TEXT_EMBEDDING_MODEL_ID="O_LOcZcBxb-yi30P__F5"
SEMANTIC_HIGHLIGHTING_MODEL_ID="RPLPcZcBxb-yi30PhvF6"

# 运行5次测试进行对比
for i in {1..5}; do
    echo "=== 测试 $i/5 (K=2) ==="
    
    # 1. HTTP客户端时间测量 (bash)
    start_time=$(date +%s%N)
    
    result=$(curl -s -X POST "http://localhost:9200/neural-search-index/_search" \
        -H 'Content-Type: application/json' \
        -d"{
            \"query\": {
                \"neural\": {
                    \"text_embedding\": {
                        \"query_text\": \"treatments for neurodegenerative diseases\",
                        \"model_id\": \"$TEXT_EMBEDDING_MODEL_ID\",
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
                    \"model_id\": \"$SEMANTIC_HIGHLIGHTING_MODEL_ID\"
                }
            }
        }")
    
    end_time=$(date +%s%N)
    http_duration=$(( (end_time - start_time) / 1000000 ))
    
    # 2. OpenSearch内部时间
    opensearch_took=$(echo "$result" | jq '.took')
    
    # 3. 网络和JSON处理开销
    network_overhead=$((http_duration - opensearch_took))
    
    highlights=$(echo "$result" | jq '[.hits.hits[] | select(has("highlight"))] | length')
    
    echo "  HTTP客户端时间: ${http_duration}ms"
    echo "  OpenSearch took: ${opensearch_took}ms"
    echo "  网络+JSON开销: ${network_overhead}ms"
    echo "  高亮成功: ${highlights}/2"
    
    # 4. 检查日志中的实际推理时间
    sleep 0.5
    echo -n "  日志中的推理时间: "
    tail -20 /Users/junqiu/dev/parallel-inference/neural-search/build/testclusters/integTest-0/logs/integTest.log | \
        grep "completed successfully" | tail -2 | \
        sed 's/.*in \([0-9]*\)ms.*/\1ms/' | tr '\n' ' '
    echo ""
    
    echo "  ---"
    sleep 2
done

echo ""
echo "=== 时间测量方法分析 ==="
echo "1. HTTP客户端时间 = OpenSearch took + 网络延迟 + JSON处理"
echo "2. OpenSearch took = 查询执行 + 语义高亮 + 响应构建"
echo "3. 日志推理时间 = 纯语义高亮ML推理时间"
echo ""
echo "最准确的方法："
echo "- 端到端性能: HTTP客户端时间"
echo "- OpenSearch性能: took字段"
echo "- 语义高亮性能: 日志中的推理时间"