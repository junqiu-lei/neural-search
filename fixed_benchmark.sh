#!/bin/bash

echo "=== 神经搜索语义高亮综合基准测试 ==="
echo "测试目标：K值 (1,5,10,20,50) × max_parallelism值 (1,4,8,16)"
echo "测试日期: $(date)"
echo ""

# 模型ID配置
TEXT_EMBEDDING_MODEL_ID="O_LOcZcBxb-yi30P__F5"
SEMANTIC_HIGHLIGHTING_MODEL_ID="RPLPcZcBxb-yi30PhvF6"

# 测试配置
K_VALUES="1 5 10 20 50"
PARALLELISM_VALUES="1 4 8 16"
RUNS_PER_TEST=3  # 每个配置运行3次

# 结果文件
results_file="/tmp/benchmark_results.txt"
echo "# parallelism,k,took,inference,highlights,valid_runs" > "$results_file"

# 辅助函数：更新并行度设置
update_parallelism() {
    local parallelism=$1
    echo "  设置 max_parallelism = $parallelism"
    
    curl -s -X PUT "http://localhost:9200/_cluster/settings" \
        -H 'Content-Type: application/json' \
        -d"{
            \"transient\": {
                \"plugins.neural_search.semantic_highlighting.max_parallelism\": $parallelism
            }
        }" > /dev/null
    
    # 等待设置生效
    sleep 2
    
    # 验证设置
    current_setting=$(curl -s "http://localhost:9200/_cluster/settings" | \
        jq -r '.transient["plugins.neural_search.semantic_highlighting.max_parallelism"] // "8"')
    
    echo "    当前设置: $current_setting"
}

# 辅助函数：执行单次测试
run_single_test() {
    local k=$1
    local parallelism=$2
    local run=$3
    
    # 创建唯一的查询标识符
    local query_id="BENCH_K${k}_P${parallelism}_R${run}"
    
    # 执行搜索请求
    result=$(curl -s -X POST "http://localhost:9200/neural-search-index/_search" \
        -H 'Content-Type: application/json' \
        -d"{
            \"query\": {
                \"neural\": {
                    \"text_embedding\": {
                        \"query_text\": \"$query_id treatments for neurodegenerative diseases research\",
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
    
    # 提取性能指标
    took=$(echo "$result" | jq -r '.took // 0')
    hits=$(echo "$result" | jq -r '.hits.total.value // 0')
    highlights=$(echo "$result" | jq -r '[.hits.hits[] | select(has("highlight"))] | length')
    
    # 等待日志写入并提取推理时间
    sleep 1
    inference_sum=$(tail -50 /Users/junqiu/dev/parallel-inference/neural-search/build/testclusters/integTest-0/logs/integTest.log | \
        grep "completed successfully" | tail -$k | \
        sed 's/.*in \([0-9]*\)ms.*/\1/' | \
        awk '{sum += $1} END {print sum + 0}')
    
    # 如果推理时间提取失败，设为0
    if [ -z "$inference_sum" ]; then
        inference_sum=0
    fi
    
    echo "    运行 $run: took=${took}ms, 推理=${inference_sum}ms, 高亮=${highlights}/${k}"
    
    # 返回结果 (格式: took,inference_sum,highlights)
    echo "${took},${inference_sum},${highlights}"
}

# 主测试循环
echo "开始基准测试..."
echo ""

total_tests=$(echo $K_VALUES | wc -w)
total_tests=$((total_tests * $(echo $PARALLELISM_VALUES | wc -w)))
current_test=0

for parallelism in $PARALLELISM_VALUES; do
    echo "=== 测试并行度: $parallelism ==="
    
    # 更新并行度设置
    update_parallelism $parallelism
    
    for k in $K_VALUES; do
        current_test=$((current_test + 1))
        echo "  测试 K=$k (进度: $current_test/$total_tests)"
        
        # 收集多次运行的结果
        total_took=0
        total_inference=0
        total_highlights=0
        valid_runs=0
        
        for run in $(seq 1 $RUNS_PER_TEST); do
            echo -n "    "
            result=$(run_single_test $k $parallelism $run)
            
            # 解析结果
            took=$(echo "$result" | cut -d',' -f1)
            inference=$(echo "$result" | cut -d',' -f2)
            highlights=$(echo "$result" | cut -d',' -f3)
            
            # 验证结果有效性
            if [ "$took" != "null" ] && [ "$took" != "0" ] && [ "$took" -gt 0 ] 2>/dev/null; then
                total_took=$((total_took + took))
                total_inference=$((total_inference + inference))
                total_highlights=$((total_highlights + highlights))
                valid_runs=$((valid_runs + 1))
            else
                echo "      ⚠️ 无效结果，跳过"
            fi
            
            # 测试间隔
            sleep 1
        done
        
        # 计算平均值
        if [ $valid_runs -gt 0 ]; then
            avg_took=$((total_took / valid_runs))
            avg_inference=$((total_inference / valid_runs))
            avg_highlights=$((total_highlights / valid_runs))
            
            # 存储结果到文件
            echo "$parallelism,$k,$avg_took,$avg_inference,$avg_highlights,$valid_runs" >> "$results_file"
            
            echo "    平均结果: took=${avg_took}ms, 推理=${avg_inference}ms, 高亮=${avg_highlights}/${k} (有效运行: $valid_runs/$RUNS_PER_TEST)"
        else
            echo "    ❌ 所有运行都失败"
            echo "$parallelism,$k,0,0,0,0" >> "$results_file"
        fi
        
        echo ""
        sleep 2
    done
    
    echo ""
done

echo "=== 基准测试完成 ==="
echo "正在生成报告..."

# 生成时间戳
timestamp=$(date '+%Y%m%d_%H%M%S')
report_file="/Users/junqiu/dev/parallel-inference/neural-search/benchmark_report_${timestamp}.md"

# 生成报告
cat > "$report_file" << EOF
# 神经搜索语义高亮基准测试报告

**生成时间**: $(date)  
**测试分支**: parallel-1  
**OpenSearch版本**: 3.1.0-SNAPSHOT  

## 测试配置

- **K值**: $K_VALUES
- **max_parallelism值**: $PARALLELISM_VALUES
- **每个配置运行次数**: $RUNS_PER_TEST
- **文本嵌入模型**: $TEXT_EMBEDDING_MODEL_ID
- **语义高亮模型**: $SEMANTIC_HIGHLIGHTING_MODEL_ID

## 性能测试结果

### 详细数据表格

| max_parallelism | K值 | 平均OpenSearch时间(ms) | 平均推理时间(ms) | 平均高亮数 | 有效运行数 |
|----------------|-----|----------------------|-----------------|-----------|-----------|
EOF

# 添加详细数据
while IFS=, read -r parallelism k took inference highlights valid_runs; do
    if [ "$parallelism" != "# parallelism" ]; then
        echo "| $parallelism | $k | $took | $inference | $highlights | $valid_runs |" >> "$report_file"
    fi
done < "$results_file"

# 添加性能分析
cat >> "$report_file" << 'EOF'

### 性能分析

#### 1. 并发效率分析

根据测试结果分析不同并行度设置下的性能表现：

EOF

# 简化的性能分析
for k in $K_VALUES; do
    echo "**K=$k的性能对比**:" >> "$report_file"
    echo "" >> "$report_file"
    
    # 读取所有相关数据
    while IFS=, read -r parallelism kval took inference highlights valid_runs; do
        if [ "$kval" = "$k" ] && [ "$parallelism" != "# parallelism" ] && [ "$took" != "0" ]; then
            echo "- parallelism=$parallelism: ${took}ms (推理: ${inference}ms, 高亮: $highlights)" >> "$report_file"
        fi
    done < "$results_file"
    echo "" >> "$report_file"
done

cat >> "$report_file" << 'EOF'

#### 2. 关键发现

基于基准测试结果的主要发现：

1. **并行度影响**: 比较不同max_parallelism设置对性能的影响
2. **K值扩展性**: 分析处理更多文档时的性能变化
3. **最佳配置**: 识别在不同工作负载下的最优配置

#### 3. 测试环境信息

- **硬件**: Apple Silicon (M系列芯片)
- **Java版本**: OpenJDK 21.0.2
- **内存配置**: 1-2GB heap
- **线程池**: 12个专用语义高亮线程

#### 4. 注意事项

1. 测试结果可能受到以下因素影响：
   - 网络延迟波动
   - ML模型推理服务的负载
   - JVM垃圾回收
   - 系统资源竞争

2. 建议在生产环境中进行进一步验证

---

*本报告由神经搜索基准测试工具自动生成*
EOF

echo "基准测试报告已生成: $report_file"
echo "原始数据文件: $results_file"
echo ""
echo "报告包含:"
echo "- 所有K值和并行度组合的详细性能数据"
echo "- 并发效率分析"
echo "- 关键发现和优化建议"