#!/bin/bash

echo "=== 真实性能测试：确保语义高亮完成 ==="
echo "目标：测量真实的语义高亮完成时间"
echo ""

# 清空日志标记
echo "开始测试前日志位置："
tail -1 /Users/junqiu/dev/parallel-inference/neural-search/build/testclusters/integTest-0/logs/integTest.log

echo ""
echo "=== 测试 K=1 ==="
start_time=$(date +%s%N)
echo "发起请求时间: $(date +%T.%3N)"

curl -s -X POST "http://localhost:9200/neural-search-index/_search" \
    -H 'Content-Type: application/json' \
    -d'{
        "query": {
            "neural": {
                "text_embedding": {
                    "query_text": "treatments for neurodegenerative diseases",
                    "model_id": "1AuycJcBZVNGtxBKPQFR",
                    "k": 1
                }
            }
        },
        "highlight": {
            "fields": {
                "text": {
                    "type": "semantic"
                }
            },
            "options": {
                "model_id": "3QuzcJcBZVNGtxBKOQH6"
            }
        }
    }' > /dev/null

end_time=$(date +%s%N)
duration=$(( (end_time - start_time) / 1000000 ))
echo "HTTP响应时间: ${duration}ms"
echo "响应完成时间: $(date +%T.%3N)"

sleep 2

echo ""
echo "检查日志中的实际推理时间："
tail -20 /Users/junqiu/dev/parallel-inference/neural-search/build/testclusters/integTest-0/logs/integTest.log | grep -E "(START|END|duration)" | tail -6

echo ""
echo "=== 分析 ==="
echo "如果HTTP响应时间 << 推理duration，说明响应在推理完成前返回了"
echo "如果HTTP响应时间 ≈ 推理duration，说明等待了推理完成"