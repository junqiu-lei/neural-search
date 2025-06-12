#!/bin/bash

echo "=== 神经搜索语义高亮基准测试 ==="
echo "测试日期: $(date)"
echo ""

# 模型ID配置
TEXT_EMBEDDING_MODEL_ID="O_LOcZcBxb-yi30P__F5"
SEMANTIC_HIGHLIGHTING_MODEL_ID="RPLPcZcBxb-yi30PhvF6"

# 测试配置
K_VALUES="1 5 10 20 50"
PARALLELISM_VALUES="1 4 8 16"

# 结果文件
timestamp=$(date '+%Y%m%d_%H%M%S')
results_file="/Users/junqiu/dev/parallel-inference/neural-search/benchmark_results_${timestamp}.csv"
echo "parallelism,k,avg_took_ms,num_highlights,num_runs" > "$results_file"

# 辅助函数：更新并行度设置
update_parallelism() {
    local parallelism=$1
    echo "设置 max_parallelism = $parallelism"
    
    curl -s -X PUT "http://localhost:9200/_cluster/settings" \
        -H 'Content-Type: application/json' \
        -d"{
            \"transient\": {
                \"plugins.neural_search.semantic_highlighting.max_parallelism\": $parallelism
            }
        }" > /dev/null
    
    sleep 3  # 等待设置生效
}

# 辅助函数：执行测试
run_test() {
    local k=$1
    local parallelism=$2
    local runs=3
    
    echo "  测试 K=$k"
    
    local total_took=0
    local total_highlights=0
    local valid_runs=0
    
    for run in $(seq 1 $runs); do
        echo -n "    运行 $run/$runs... "
        
        # 执行搜索查询
        result=$(curl -s -X POST "http://localhost:9200/neural-search-index/_search" \
            -H 'Content-Type: application/json' \
            -d"{
                \"size\": $k,
                \"query\": {
                    \"neural\": {
                        \"text_embedding\": {
                            \"query_text\": \"test_${parallelism}_${k}_${run} treatments for neurodegenerative diseases research\",
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
        
        # 解析结果
        took=$(echo "$result" | jq -r '.took')
        highlights=$(echo "$result" | jq -r '[.hits.hits[] | select(.highlight)] | length')
        
        if [ "$took" != "null" ] && [ "$took" -gt 0 ] 2>/dev/null; then
            total_took=$((total_took + took))
            total_highlights=$((total_highlights + highlights))
            valid_runs=$((valid_runs + 1))
            echo "took=${took}ms, highlights=${highlights}"
        else
            echo "失败"
        fi
        
        sleep 2
    done
    
    if [ $valid_runs -gt 0 ]; then
        avg_took=$((total_took / valid_runs))
        avg_highlights=$((total_highlights / valid_runs))
        
        echo "    平均: ${avg_took}ms, 高亮数: ${avg_highlights} (${valid_runs}/${runs} 成功)"
        echo "$parallelism,$k,$avg_took,$avg_highlights,$valid_runs" >> "$results_file"
    else
        echo "    所有运行都失败"
        echo "$parallelism,$k,0,0,0" >> "$results_file"
    fi
}

# 主测试循环
echo "开始基准测试..."
echo ""

for parallelism in $PARALLELISM_VALUES; do
    echo "=== 并行度: $parallelism ==="
    update_parallelism $parallelism
    
    for k in $K_VALUES; do
        run_test $k $parallelism
    done
    
    echo ""
done

echo "=== 测试完成 ==="
echo "结果已保存到: $results_file"

# 生成报告
report_file="/Users/junqiu/dev/parallel-inference/neural-search/benchmark_report_${timestamp}.md"

cat > "$report_file" << EOF
# 神经搜索语义高亮基准测试报告

**生成时间**: $(date)  
**测试分支**: parallel-1  
**OpenSearch版本**: 3.1.0-SNAPSHOT  

## 测试配置

- **K值**: $K_VALUES
- **max_parallelism值**: $PARALLELISM_VALUES
- **每个配置运行次数**: 3
- **文本嵌入模型**: $TEXT_EMBEDDING_MODEL_ID
- **语义高亮模型**: $SEMANTIC_HIGHLIGHTING_MODEL_ID

## 性能测试结果

### 详细数据表格

| max_parallelism | K值 | 平均响应时间(ms) | 平均高亮数 | 成功运行数 |
|----------------|-----|-----------------|-----------|-----------|
EOF

# 添加详细数据
tail -n +2 "$results_file" | while IFS=, read -r parallelism k avg_took highlights runs; do
    echo "| $parallelism | $k | $avg_took | $highlights | $runs |" >> "$report_file"
done

cat >> "$report_file" << 'EOF'

### 性能分析

#### 1. 并发效率对比

根据不同并行度设置的测试结果，分析并发优化效果：

EOF

# 添加性能分析
for k in $K_VALUES; do
    echo "**K=$k 的性能对比**:" >> "$report_file"
    echo "" >> "$report_file"
    
    tail -n +2 "$results_file" | while IFS=, read -r parallelism kval avg_took highlights runs; do
        if [ "$kval" = "$k" ] && [ "$avg_took" != "0" ]; then
            echo "- parallelism=$parallelism: ${avg_took}ms (高亮文档: $highlights)" >> "$report_file"
        fi
    done
    echo "" >> "$report_file"
done

cat >> "$report_file" << 'EOF'

#### 2. 关键发现

1. **并行度影响**: 分析不同max_parallelism设置对响应时间的影响
2. **K值扩展性**: 观察处理更多文档时的性能变化趋势
3. **最佳配置**: 基于测试结果识别最优的并行度配置

#### 3. 测试环境

- **硬件**: Apple Silicon
- **Java版本**: OpenJDK 21.0.2
- **集群状态**: Single node, yellow status
- **数据量**: 121 documents

#### 4. 注意事项

本测试结果反映了当前技术方案在测试环境下的性能表现。实际生产环境可能存在差异。

---

*报告生成时间: $(date)*
EOF

echo "基准测试报告已生成: $report_file"
echo ""
cat "$results_file"