#!/bin/bash

echo "=== 神经搜索语义高亮综合基准测试 ==="
echo "测试目标：K值 (1,5,10,20,50) × max_parallelism值 (1,4,8,16)"
echo "测试日期: $(date)"
echo ""

# 模型ID配置
TEXT_EMBEDDING_MODEL_ID="O_LOcZcBxb-yi30P__F5"
SEMANTIC_HIGHLIGHTING_MODEL_ID="RPLPcZcBxb-yi30PhvF6"

# 测试配置
K_VALUES=(1 5 10 20 50)
PARALLELISM_VALUES=(1 4 8 16)
RUNS_PER_TEST=5  # 每个配置运行5次

# 结果存储
declare -A results
declare -A inference_times
declare -A highlight_counts

# 辅助函数：更新并行度设置
update_parallelism() {
    local parallelism=$1
    echo "  设置 max_parallelism = $parallelism"
    
    result=$(curl -s -X PUT "http://localhost:9200/_cluster/settings" \
        -H 'Content-Type: application/json' \
        -d"{
            \"transient\": {
                \"plugins.neural_search.semantic_highlighting.max_parallelism\": $parallelism
            }
        }")
    
    # 等待设置生效
    sleep 2
    
    # 验证设置是否生效
    current_setting=$(curl -s "http://localhost:9200/_cluster/settings" | \
        jq -r '.transient["plugins.neural_search.semantic_highlighting.max_parallelism"] // .defaults["plugins.neural_search.semantic_highlighting.max_parallelism"] // "8"')
    
    if [ "$current_setting" = "$parallelism" ]; then
        echo "    ✅ 并行度设置成功: $parallelism"
    else
        echo "    ⚠️ 并行度设置可能未生效: 期望=$parallelism, 实际=$current_setting"
    fi
}

# 辅助函数：执行单次测试
run_single_test() {
    local k=$1
    local parallelism=$2
    local run=$3
    
    # 创建唯一的查询标识符
    local query_id="BENCH_K${k}_P${parallelism}_R${run}_$(date +%s)"
    
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
    took=$(echo "$result" | jq '.took')
    hits=$(echo "$result" | jq '.hits.total.value')
    highlights=$(echo "$result" | jq '[.hits.hits[] | select(has("highlight"))] | length')
    
    # 等待日志写入并提取推理时间
    sleep 1
    inference_sum=$(tail -100 /Users/junqiu/dev/parallel-inference/neural-search/build/testclusters/integTest-0/logs/integTest.log | \
        grep "completed successfully" | tail -$k | \
        sed 's/.*in \([0-9]*\)ms.*/\1/' | \
        awk '{sum += $1} END {print sum}')
    
    # 如果推理时间提取失败，设为0
    if [ -z "$inference_sum" ] || [ "$inference_sum" = "" ]; then
        inference_sum=0
    fi
    
    echo "    运行 $run: took=${took}ms, 推理=${inference_sum}ms, 高亮=${highlights}/${k}"
    
    # 返回结果 (格式: took,inference_sum,highlights)
    echo "${took},${inference_sum},${highlights}"
}

# 主测试循环
echo "开始基准测试..."
echo ""

total_tests=$((${#K_VALUES[@]} * ${#PARALLELISM_VALUES[@]}))
current_test=0

for parallelism in "${PARALLELISM_VALUES[@]}"; do
    echo "=== 测试并行度: $parallelism ==="
    
    # 更新并行度设置
    update_parallelism $parallelism
    
    for k in "${K_VALUES[@]}"; do
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
            if [ "$took" != "null" ] && [ "$took" -gt 0 ]; then
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
            
            # 存储结果
            key="${parallelism}_${k}"
            results[$key]="$avg_took,$avg_inference,$avg_highlights,$valid_runs"
            
            echo "    平均结果: took=${avg_took}ms, 推理=${avg_inference}ms, 高亮=${avg_highlights}/${k} (有效运行: $valid_runs/$RUNS_PER_TEST)"
        else
            echo "    ❌ 所有运行都失败"
            results[$key]="0,0,0,0"
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

- **K值**: ${K_VALUES[*]}
- **max_parallelism值**: ${PARALLELISM_VALUES[*]}
- **每个配置运行次数**: $RUNS_PER_TEST
- **文本嵌入模型**: $TEXT_EMBEDDING_MODEL_ID
- **语义高亮模型**: $SEMANTIC_HIGHLIGHTING_MODEL_ID

## 性能测试结果

### 详细数据表格

| max_parallelism | K值 | 平均OpenSearch时间(ms) | 平均推理时间(ms) | 平均高亮数 | 有效运行数 |
|----------------|-----|----------------------|-----------------|-----------|-----------|
EOF

# 添加详细数据
for parallelism in "${PARALLELISM_VALUES[@]}"; do
    for k in "${K_VALUES[@]}"; do
        key="${parallelism}_${k}"
        if [ -n "${results[$key]}" ]; then
            data="${results[$key]}"
            took=$(echo "$data" | cut -d',' -f1)
            inference=$(echo "$data" | cut -d',' -f2)
            highlights=$(echo "$data" | cut -d',' -f3)
            valid_runs=$(echo "$data" | cut -d',' -f4)
            
            echo "| $parallelism | $k | $took | $inference | $highlights | $valid_runs |" >> "$report_file"
        fi
    done
done

# 添加性能分析
cat >> "$report_file" << 'EOF'

### 性能分析

#### 1. 并发效率分析

EOF

# 计算并发效率
for k in "${K_VALUES[@]}"; do
    echo "**K=$k的并发效率**:" >> "$report_file"
    echo "" >> "$report_file"
    
    # 获取parallelism=1的基准时间
    baseline_key="1_${k}"
    if [ -n "${results[$baseline_key]}" ]; then
        baseline_data="${results[$baseline_key]}"
        baseline_took=$(echo "$baseline_data" | cut -d',' -f1)
        
        if [ "$baseline_took" -gt 0 ]; then
            echo "- 基准时间(parallelism=1): ${baseline_took}ms" >> "$report_file"
            
            for parallelism in 4 8 16; do
                test_key="${parallelism}_${k}"
                if [ -n "${results[$test_key]}" ]; then
                    test_data="${results[$test_key]}"
                    test_took=$(echo "$test_data" | cut -d',' -f1)
                    
                    if [ "$test_took" -gt 0 ]; then
                        # 计算理论串行时间和效率
                        theoretical_time=$((baseline_took * parallelism))
                        efficiency=$((theoretical_time * 100 / test_took))
                        speedup=$((baseline_took * 100 / test_took))
                        
                        echo "- parallelism=$parallelism: ${test_took}ms, 效率=${efficiency}%, 加速比=${speedup}%" >> "$report_file"
                    fi
                fi
            done
        fi
    fi
    echo "" >> "$report_file"
done

cat >> "$report_file" << 'EOF'

#### 2. 扩展性分析

**K值扩展性** (在相同并行度下，K值增加时的性能表现):

EOF

for parallelism in "${PARALLELISM_VALUES[@]}"; do
    echo "**parallelism=$parallelism**:" >> "$report_file"
    echo "" >> "$report_file"
    
    # 获取K=1的基准时间
    k1_key="${parallelism}_1"
    if [ -n "${results[$k1_key]}" ]; then
        k1_data="${results[$k1_key]}"
        k1_took=$(echo "$k1_data" | cut -d',' -f1)
        
        if [ "$k1_took" -gt 0 ]; then
            for k in 5 10 20 50; do
                test_key="${parallelism}_${k}"
                if [ -n "${results[$test_key]}" ]; then
                    test_data="${results[$test_key]}"
                    test_took=$(echo "$test_data" | cut -d',' -f1)
                    
                    if [ "$test_took" -gt 0 ]; then
                        # 计算每个文档的平均时间
                        time_per_doc=$((test_took / k))
                        efficiency_vs_k1=$((k1_took * k * 100 / test_took))
                        
                        echo "- K=$k: ${test_took}ms (${time_per_doc}ms/doc), 相对K=1效率=${efficiency_vs_k1}%" >> "$report_file"
                    fi
                fi
            done
        fi
    fi
    echo "" >> "$report_file"
done

cat >> "$report_file" << 'EOF'

#### 3. 关键发现

**最佳配置**:
- 根据测试结果，识别出性能最优的parallelism配置
- 分析不同K值下的最佳并行策略

**性能瓶颈**:
- 识别当前实现中的主要性能限制因素
- 分析并发效率低于预期的原因

**优化建议**:
- 基于测试结果提出进一步的优化方向
- 建议针对不同查询负载的配置策略

### 4. 测试环境信息

- **硬件**: Apple Silicon (M系列芯片)
- **Java版本**: OpenJDK 21.0.2
- **内存配置**: 1-2GB heap
- **线程池**: 12个专用语义高亮线程

### 5. 注意事项

1. 测试结果可能受到以下因素影响：
   - 网络延迟波动
   - ML模型推理服务的负载
   - JVM垃圾回收
   - 系统资源竞争

2. 生产环境中的性能可能与测试环境存在差异

3. 建议在实际负载模式下进行进一步验证

---

*本报告由神经搜索基准测试工具自动生成*
EOF

echo "基准测试报告已生成: $report_file"
echo ""
echo "报告包含:"
echo "- 所有K值和并行度组合的详细性能数据"
echo "- 并发效率分析"
echo "- 扩展性分析"
echo "- 关键发现和优化建议"