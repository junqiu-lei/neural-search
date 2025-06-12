#!/bin/bash

echo "=== ML模型直接推理并发性能测试 ==="
echo "测试目标：测试ML推理API的并发性能"
echo "测试日期: $(date)"
echo ""

# 配置
MODEL_ID="RPLPcZcBxb-yi30PhvF6"
OPENSEARCH_HOST="localhost"
OPENSEARCH_PORT="9200"
API_URL="http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ml/models/${MODEL_ID}/_predict"

# 测试参数
CONCURRENCY_LEVELS="1 5 10 20 50"
RUNS_PER_LEVEL=10  # 每个并发级别运行10次

# 结果文件
timestamp=$(date '+%Y%m%d_%H%M%S')
results_file="/Users/junqiu/dev/parallel-inference/neural-search/ml_inference_results_${timestamp}.csv"
echo "concurrency,run,response_time_ms,success" > "$results_file"

# 测试数据变体
TEST_CONTEXTS=(
    "While effective, patients may experience stomach upset and bleeding as common side effects."
    "Common adverse reactions include nausea, dizziness, and headache in clinical trials."
    "Most patients tolerate the medication well, but some report fatigue and sleep disturbances."
    "Serious side effects are rare but may include liver dysfunction and allergic reactions."
    "Gastrointestinal symptoms such as diarrhea and abdominal pain occur in 10-15% of patients."
)

TEST_QUESTIONS=(
    "What are the side effects?"
    "What adverse reactions should I expect?"
    "Are there any serious complications?"
    "What symptoms might occur?"
    "What are the common problems?"
)

# 函数：执行单次推理请求
execute_single_request() {
    local context="${TEST_CONTEXTS[$((RANDOM % ${#TEST_CONTEXTS[@]}))]}"
    local question="${TEST_QUESTIONS[$((RANDOM % ${#TEST_QUESTIONS[@]}))]}"
    
    start_time=$(date +%s%N)
    
    response=$(curl -s --max-time 30 -X POST "$API_URL" \
        -H 'Content-Type: application/json' \
        -d"{
            \"parameters\": {
                \"question\": \"$question\",
                \"context\": \"$context\"
            }
        }")
    
    end_time=$(date +%s%N)
    
    # 计算响应时间（毫秒）
    response_time=$(( (end_time - start_time) / 1000000 ))
    
    # 检查是否成功
    if echo "$response" | grep -q "inference_results" 2>/dev/null; then
        echo "success,$response_time"
    else
        echo "failed,$response_time"
    fi
}

# 函数：执行并发测试
run_concurrent_test() {
    local concurrency=$1
    local run_number=$2
    
    echo "  运行 $run_number/$RUNS_PER_LEVEL (并发数: $concurrency)..."
    
    # 创建临时文件存储结果
    temp_file="/tmp/ml_test_${concurrency}_${run_number}.tmp"
    
    # 启动并发请求
    for i in $(seq 1 $concurrency); do
        execute_single_request > "${temp_file}_${i}" &
    done
    
    # 等待所有请求完成
    wait
    
    # 收集结果
    local total_time=0
    local success_count=0
    local failed_count=0
    
    for i in $(seq 1 $concurrency); do
        if [ -f "${temp_file}_${i}" ]; then
            result=$(cat "${temp_file}_${i}")
            status=$(echo "$result" | cut -d',' -f1)
            time_ms=$(echo "$result" | cut -d',' -f2)
            
            # 记录到CSV
            echo "$concurrency,$run_number,$time_ms,$status" >> "$results_file"
            
            if [ "$status" = "success" ]; then
                total_time=$((total_time + time_ms))
                success_count=$((success_count + 1))
            else
                failed_count=$((failed_count + 1))
            fi
            
            # 清理临时文件
            rm -f "${temp_file}_${i}"
        fi
    done
    
    # 计算平均响应时间
    if [ $success_count -gt 0 ]; then
        avg_time=$((total_time / success_count))
        echo "    结果: 成功=${success_count}/${concurrency}, 平均响应时间=${avg_time}ms, 失败=${failed_count}"
    else
        echo "    结果: 所有请求都失败"
    fi
}

# 主测试循环
echo "开始ML推理并发测试..."
echo ""

for concurrency in $CONCURRENCY_LEVELS; do
    echo "=== 测试并发数: $concurrency ==="
    
    # 运行多次测试
    for run in $(seq 1 $RUNS_PER_LEVEL); do
        run_concurrent_test $concurrency $run
        sleep 1  # 避免过载
    done
    
    echo ""
done

echo "=== 测试完成 ==="

# 生成统计报告
echo "正在生成分析报告..."

report_file="/Users/junqiu/dev/parallel-inference/neural-search/ml_inference_analysis_${timestamp}.md"

cat > "$report_file" << EOF
# ML模型直接推理并发性能分析报告

**生成时间**: $(date)
**测试模型**: $MODEL_ID
**测试类型**: 直接ML推理API调用

## 测试配置

- **并发级别**: $CONCURRENCY_LEVELS
- **每个级别运行次数**: $RUNS_PER_LEVEL
- **API端点**: $API_URL
- **测试数据**: 5种不同的上下文和问题组合

## 详细统计结果

EOF

# 生成每个并发级别的统计
for concurrency in $CONCURRENCY_LEVELS; do
    echo "### 并发数: $concurrency" >> "$report_file"
    echo "" >> "$report_file"
    
    # 提取该并发级别的数据
    level_data=$(grep "^$concurrency," "$results_file")
    
    if [ ! -z "$level_data" ]; then
        # 计算统计数据
        success_times=$(echo "$level_data" | grep ",success$" | cut -d',' -f3)
        
        if [ ! -z "$success_times" ]; then
            success_count=$(echo "$success_times" | wc -l | xargs)
            total_requests=$((concurrency * RUNS_PER_LEVEL))
            success_rate=$(( success_count * 100 / total_requests ))
            
            min_time=$(echo "$success_times" | sort -n | head -1)
            max_time=$(echo "$success_times" | sort -n | tail -1)
            avg_time=$(echo "$success_times" | awk '{sum += $1; count++} END {print int(sum/count)}')
            
            echo "- **总请求数**: $total_requests" >> "$report_file"
            echo "- **成功请求数**: $success_count" >> "$report_file"
            echo "- **成功率**: ${success_rate}%" >> "$report_file"
            echo "- **平均响应时间**: ${avg_time}ms" >> "$report_file"
            echo "- **最小响应时间**: ${min_time}ms" >> "$report_file"
            echo "- **最大响应时间**: ${max_time}ms" >> "$report_file"
            
            # 计算百分位数
            p50=$(echo "$success_times" | sort -n | awk '{all[NR] = $0} END{print all[int(NR*0.5)]}')
            p95=$(echo "$success_times" | sort -n | awk '{all[NR] = $0} END{print all[int(NR*0.95)]}')
            
            echo "- **P50延迟**: ${p50}ms" >> "$report_file"
            echo "- **P95延迟**: ${p95}ms" >> "$report_file"
        else
            echo "- **结果**: 所有请求都失败" >> "$report_file"
        fi
    else
        echo "- **结果**: 无数据" >> "$report_file"
    fi
    
    echo "" >> "$report_file"
done

# 添加性能对比部分
cat >> "$report_file" << 'EOF'

## 与Semantic Highlighting性能对比

### 对比分析方法

本测试测量的是**纯ML推理性能**，不包括：
- 文档检索时间
- JSON解析开销  
- 网络传输延迟
- OpenSearch处理开销

### 性能基准对比

将此数据与之前的Semantic Highlighting端到端测试进行对比：

**Semantic Highlighting (端到端)**:
- K=1: ~245-334ms
- K=5: ~841-1015ms  
- K=10: ~1763-2073ms
- K=20: ~3517-4305ms
- K=50: ~9096-9752ms

**ML推理 (纯推理)**:
- 并发1: [从上面的数据填入]
- 并发5: [从上面的数据填入]
- 并发10: [从上面的数据填入]
- 并发20: [从上面的数据填入]
- 并发50: [从上面的数据填入]

### 性能瓶颈分析

1. **ML推理延迟**: 如果单次推理时间较高，说明瓶颈在ML服务
2. **并发扩展性**: 对比并发扩展能力识别资源限制
3. **系统开销**: 端到端时间 - 推理时间 = 系统处理开销

### 优化建议

基于对比结果的优化建议将在分析完成后提供。

EOF

echo "分析报告已生成: $report_file"
echo "原始数据文件: $results_file"
echo ""
echo "测试统计概览:"
echo "- 总测试配置: $(echo $CONCURRENCY_LEVELS | wc -w | xargs)个并发级别"
echo "- 每级别运行次数: $RUNS_PER_LEVEL"
echo "- 总请求数: $(( $(echo $CONCURRENCY_LEVELS | tr ' ' '+' | bc) * RUNS_PER_LEVEL ))"