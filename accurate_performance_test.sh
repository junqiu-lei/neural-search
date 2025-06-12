#!/bin/bash

echo "=== 准确的并发性能测试 ==="
echo "方法：使用OpenSearch took时间作为主要指标"
echo "对比：日志推理时间验证准确性"
echo ""

TEXT_EMBEDDING_MODEL_ID="O_LOcZcBxb-yi30P__F5"
SEMANTIC_HIGHLIGHTING_MODEL_ID="RPLPcZcBxb-yi30PhvF6"

# 测试不同K值的性能
declare -A took_times
declare -A inference_times

for k in 1 2 5; do
    echo "=== 测试 K=$k ==="
    
    total_took=0
    total_inference=0
    
    for run in {1..3}; do
        echo -n "  运行 $run/3..."
        
        # 清理日志标记
        log_marker="TEST_K${k}_RUN${run}_$(date +%s)"
        
        result=$(curl -s -X POST "http://localhost:9200/neural-search-index/_search" \
            -H 'Content-Type: application/json' \
            -d"{
                \"query\": {
                    \"neural\": {
                        \"text_embedding\": {
                            \"query_text\": \"$log_marker treatments for neurodegenerative diseases\",
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
        
        took=$(echo "$result" | jq '.took')
        highlights=$(echo "$result" | jq '[.hits.hits[] | select(has("highlight"))] | length')
        
        # 等待日志写入
        sleep 1
        
        # 提取这次测试的推理时间
        inference_sum=$(tail -50 /Users/junqiu/dev/parallel-inference/neural-search/build/testclusters/integTest-0/logs/integTest.log | \
            grep "completed successfully" | tail -$k | \
            sed 's/.*in \([0-9]*\)ms.*/\1/' | \
            awk '{sum += $1} END {print sum}')
        
        echo " took:${took}ms 推理:${inference_sum}ms (${highlights}/$k 高亮)"
        
        total_took=$((total_took + took))
        total_inference=$((total_inference + inference_sum))
        
        sleep 1
    done
    
    avg_took=$((total_took / 3))
    avg_inference=$((total_inference / 3))
    
    took_times[$k]=$avg_took
    inference_times[$k]=$avg_inference
    
    echo "  平均 K=$k: took=${avg_took}ms 推理=${avg_inference}ms"
    echo ""
done

echo "=== 性能分析 ==="
echo "基于OpenSearch took时间："

k1_took=${took_times[1]}
k2_took=${took_times[2]}
k5_took=${took_times[5]}

echo "  K=1: ${k1_took}ms (基准)"
echo "  K=2: ${k2_took}ms"
echo "  K=5: ${k5_took}ms"

# 计算并发效率
if [ $k1_took -gt 0 ]; then
    k2_efficiency=$(( (k1_took * 2 * 100) / k2_took ))
    k5_efficiency=$(( (k1_took * 5 * 100) / k5_took ))
    
    echo ""
    echo "并发效率："
    echo "  K=2: ${k2_efficiency}% (理论串行时间 vs 实际时间)"
    echo "  K=5: ${k5_efficiency}% (理论串行时间 vs 实际时间)"
    
    k2_improvement=$(( k2_efficiency - 100 ))
    k5_improvement=$(( k5_efficiency - 100 ))
    
    echo ""
    echo "性能提升："
    echo "  K=2: ${k2_improvement}% 性能提升"
    echo "  K=5: ${k5_improvement}% 性能提升"
fi

echo ""
echo "基于日志推理时间验证："
k1_inference=${inference_times[1]}
k2_inference=${inference_times[2]}
k5_inference=${inference_times[5]}

echo "  K=1: ${k1_inference}ms"
echo "  K=2: ${k2_inference}ms" 
echo "  K=5: ${k5_inference}ms"