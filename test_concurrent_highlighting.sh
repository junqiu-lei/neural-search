#!/bin/bash

# 简单的并发测试脚本
echo "测试新的并发语义高亮实现..."

# 使用setup脚本配置的模型ID
TEXT_EMBEDDING_MODEL_ID="1AuycJcBZVNGtxBKPQFR"
SEMANTIC_HIGHLIGHTING_MODEL_ID="3QuzcJcBZVNGtxBKOQH6"

echo "使用模型: $TEXT_EMBEDDING_MODEL_ID (text), $SEMANTIC_HIGHLIGHTING_MODEL_ID (semantic)"

# 测试不同的K值来观察并发行为
for k in 1 2 5; do
    echo "=== 测试 K=$k ==="
    start_time=$(date +%s%N)
    
    result=$(curl -s -X POST "http://localhost:9200/neural-search-index/_search" \
        -H 'Content-Type: application/json' \
        -d"{
            \"_source\": {
                \"excludes\": [\"text_embedding\"]
            },
            \"query\": {
                \"neural\": {
                    \"text_embedding\": {
                        \"query_text\": \"treatments for neurodegenerative diseases\",
                        \"model_id\": \"$TEXT_EMBEDDING_MODEL_ID\",
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
                    \"model_id\": \"$SEMANTIC_HIGHLIGHTING_MODEL_ID\"
                }
            }
        }")
    
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))  # 转换为毫秒
    
    echo "K=$k 响应时间: ${duration}ms"
    
    # 检查是否有错误
    if echo "$result" | jq -e '.error' > /dev/null 2>&1; then
        echo "错误: $(echo "$result" | jq '.error')"
    else
        hits=$(echo "$result" | jq '.hits.total.value')
        highlights=$(echo "$result" | jq '[.hits.hits[] | select(has("highlight"))] | length')
        total_highlights=$(echo "$result" | jq '[.hits.hits[] | select(has("highlight")) | .highlight | keys[]] | length')
        echo "命中: $hits, 有高亮的文档: $highlights, 总高亮字段: $total_highlights"
        
        # 显示高亮内容示例
        if [ "$highlights" -gt 0 ]; then
            echo "高亮示例:"
            echo "$result" | jq -r '.hits.hits[] | select(has("highlight")) | .highlight | to_entries[] | "  字段: \(.key), 内容: \(.value[0])"' | head -2
        fi
    fi
    
    echo "---"
    sleep 2
done

echo "测试完成。"