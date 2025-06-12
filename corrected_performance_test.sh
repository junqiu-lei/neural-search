#!/bin/bash

echo "=== 修正后的真实并发性能测试 ==="
echo "目标：验证真正的并发性能改进"
echo ""

# 使用正确的模型ID
TEXT_EMBEDDING_MODEL_ID="O_LOcZcBxb-yi30P__F5"
SEMANTIC_HIGHLIGHTING_MODEL_ID="RPLPcZcBxb-yi30PhvF6"

echo "使用正确的模型ID:"
echo "  文本嵌入: $TEXT_EMBEDDING_MODEL_ID"
echo "  语义高亮: $SEMANTIC_HIGHLIGHTING_MODEL_ID"
echo ""

# 测试不同的K值，期望看到真正的并发改进
for k in 1 2 5; do
    echo "=== 测试 K=$k ==="
    
    total_time=0
    total_highlights=0
    
    for run in {1..3}; do
        echo -n "  运行 $run/3..."
        
        start_time=$(date +%s%N)
        
        result=$(curl -s -X POST "http://localhost:9200/neural-search-index/_search" \
            -H 'Content-Type: application/json' \
            -d"{
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
        duration=$(( (end_time - start_time) / 1000000 ))
        
        # 提取OpenSearch内部时间
        opensearch_time=$(echo "$result" | jq '.took')
        hits=$(echo "$result" | jq '.hits.total.value')
        highlights=$(echo "$result" | jq '[.hits.hits[] | select(has("highlight"))] | length')
        
        echo " HTTP:${duration}ms OS:${opensearch_time}ms (${highlights}/${hits} 高亮)"
        
        total_time=$((total_time + opensearch_time))
        total_highlights=$((total_highlights + highlights))
        
        sleep 1
    done
    
    avg_time=$((total_time / 3))
    avg_highlights=$((total_highlights / 3))
    
    echo "  平均结果 (K=$k):"
    echo "    OpenSearch时间: ${avg_time}ms"
    echo "    平均高亮文档: $avg_highlights"
    
    # 存储基准时间
    if [ $k -eq 1 ]; then
        baseline_time=$avg_time
        echo "    基准时间: ${baseline_time}ms"
    elif [ $k -gt 1 ] && [ $baseline_time -gt 0 ]; then
        # 计算并发效率
        theoretical_time=$((baseline_time * k))
        efficiency=$((theoretical_time * 100 / avg_time))
        echo "    理论时间: ${theoretical_time}ms (如果串行)"
        echo "    并发效率: ${efficiency}%"
        
        if [ $efficiency -gt 150 ]; then
            echo "    ✅ 并发优化显著！"
        elif [ $efficiency -gt 110 ]; then
            echo "    ✅ 有并发改进"
        else
            echo "    ⚠️  并发效果有限"
        fi
    fi
    
    echo ""
    sleep 2
done

echo "=== 分析总结 ==="
echo "如果并发优化有效，K=5的时间应该远小于K=1的5倍"
echo "目标效率 > 200% 表示显著的并发改进"