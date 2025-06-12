#!/bin/bash

echo "=== 简单并发性能测试 ==="
echo "测试目标：验证并发语义高亮性能提升"
echo ""

# 测试K=1 vs K=5的响应时间
echo "测试 K=1 (基准):"
for i in {1..3}; do
    start=$(date +%s%N)
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
    end=$(date +%s%N)
    duration=$(( (end - start) / 1000000 ))
    echo "  运行 $i: ${duration}ms"
    sleep 1
done

echo ""
echo "测试 K=5 (并发):"
for i in {1..3}; do
    start=$(date +%s%N)
    curl -s -X POST "http://localhost:9200/neural-search-index/_search" \
        -H 'Content-Type: application/json' \
        -d'{
            "query": {
                "neural": {
                    "text_embedding": {
                        "query_text": "treatments for neurodegenerative diseases",
                        "model_id": "1AuycJcBZVNGtxBKPQFR",
                        "k": 5
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
    end=$(date +%s%N)
    duration=$(( (end - start) / 1000000 ))
    echo "  运行 $i: ${duration}ms"
    sleep 1
done

echo ""
echo "分析：如果并发优化生效，K=5的响应时间应该不会是K=1的5倍"