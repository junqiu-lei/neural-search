# Neural Search Plugin Development Guide

## Project Context
This is the OpenSearch Neural Search plugin focused on improving semantic highlighting performance through parallel processing.

## Development Environment

### Local Development Cluster
- Start local dev cluster: `./gradlew run`
- Start with preserved data (saves setup time): `./gradlew run --preserve-data`
- Start with increased heap (for performance testing): `OPENSEARCH_JAVA_OPTS="-Xms4g -Xmx6g" ./gradlew run --preserve-data`
- Compile Java code: `./gradlew compileJava`

### Development Scripts (bin/dev/)
- `1_setup.sh` - Setup models, index, and configs for semantic highlighting
- `2_ingest.sh` - Ingest more data for benchmarking
- `3_evaluate.sh` - **Primary evaluation tool** - Validate functionality + performance statistics (K=1,5,10)
- `3_benchmark_archive.sh` - Legacy performance testing script (archived)
- `4_comprehensive_benchmark.sh` - Full performance testing (feature vs main vs direct ML)
- `ml_concurrency_test.sh` - Direct ML inference concurrency comparison vs semantic highlighting
- `model_ids.txt` - Generated model IDs (automatically created by setup script, **not tracked in git**)

### Documentation Archive (bin/docs/)
- All development analysis reports and performance benchmarks
- File naming convention: `{document_name}_{YYYYMMDD_HHMMSS}.md`
- Chronological tracking of optimization progress
- See `bin/docs/README.md` for detailed documentation index

### Complete Development Workflow
```bash
1. ./gradlew compileJava          # Compile code changes
2. ./gradlew run --preserve-data  # Start cluster (keep existing data)
3. cd bin/dev && ./1_setup.sh     # Setup models/index (if needed)
4. ./3_evaluate.sh                # Primary evaluation: functionality + performance
5. ./ml_concurrency_test.sh       # Deep dive: concurrency analysis vs direct ML
6. # Analyze logs: tail -f ../../build/testclusters/integTest-0/logs/opensearch.stdout.log
```

### Code Change Evaluation Process
For each code change, run these scripts to ensure quality:

#### Quick Evaluation (Always Required)
```bash
cd bin/dev
./3_evaluate.sh
```
- **Purpose**: Validate semantic highlighting functionality and measure performance
- **Tests**: K=1,5,10 with 10 queries each (30 total tests)
- **Validates**: Highlight presence, content correctness, document mapping
- **Metrics**: p50/p90/p99 response times, success rate
- **Time**: ~2-3 minutes

#### Deep Concurrency Analysis (For Performance Changes)
```bash
cd bin/dev
./ml_concurrency_test.sh
```
- **Purpose**: Compare semantic highlighting vs direct ML inference concurrency
- **Tests**: Concurrency levels 1,5,10 for both approaches
- **Analysis**: Identifies true vs pseudo-concurrency
- **Time**: ~5-7 minutes

## Current Work
- **Branch**: `parallel-1` (feature branch)
- **Goal**: Improve semantic highlighting performance through parallel processing
- **Main Branch**: `main` (for comparison)

## Performance Optimization Focus
1. **Parallel Processing**: Implement parallel execution for semantic highlighting
2. **Response Correctness**: Ensure highlight responses are correctly returned
3. **Latency Improvement**: Reduce overall semantic highlight latency with reasonable parallel process counts

## Code Changes Scope
- **Primary**: neural-search plugin only
- **Reference**: OpenSearch core code at `/Users/junqiu/dev/parallel-inference/OpenSearch`

## Debugging & Monitoring

### Key Log Files and Locations
```bash
# Cluster logs
build/testclusters/integTest-0/logs/opensearch.stdout.log

# Performance logs
grep "semantic-hl-opt-timing" ../../build/testclusters/integTest-0/logs/opensearch.stdout.log

# Error logs
grep "ERROR" ../../build/testclusters/integTest-0/logs/opensearch.stdout.log
```

### Essential Monitoring Commands
```bash
# Check cluster health
curl localhost:9200/_cluster/health

# View model status
curl localhost:9200/_plugins/_ml/models

# Real-time performance monitoring
tail -f ../../build/testclusters/integTest-0/logs/opensearch.stdout.log | grep semantic-hl

# Check current model IDs
cat model_ids.txt
```

### Debug Analysis
- Add logs to neural-search plugin for debugging
- Inspect dev cluster logs for parallel process status
- Compare benchmark results between `main` and `parallel-1` branches

## Performance Analysis
- Compare feature branch vs main branch performance
- Analyze parallel process configurations
- Measure latency improvements with different parallel counts

## Performance Optimization Insights

### Current Performance Issues (parallel-1 branch)
- **K=1**: 272ms baseline performance
- **K=5**: 620ms (128% degradation) - indicates parallelization overhead
- **Thread Pool**: 16 completed tasks, 0 active/queued (underutilized)

### Root Cause Analysis
1. **Semaphore Bottleneck**: Per-request semaphore may be limiting concurrency
2. **Fixed Parallelism**: Current static parallelism=8 doesn't adapt to workload
3. **Context Switching Overhead**: Too many small tasks causing coordination overhead

### Optimization Recommendations
1. **Dynamic Parallelism**: Implement workload-based parallelism adjustment
2. **Batch Processing**: Group smaller inference requests to reduce overhead
3. **Async Pipeline**: Implement true async processing without blocking
4. **Resource Pooling**: Optimize thread pool configuration for ML inference

## Performance Testing Best Practices

### Latency Measurement Methods
Based on lessons learned from parallel semantic highlighting optimization:

#### 1. Three Types of Latency Measurements
```bash
# HTTP Client Time (end-to-end user experience)
start=$(date +%s%N)
result=$(curl -s "opensearch_query")
end=$(date +%s%N)
http_duration=$(( (end - start) / 1000000 ))

# OpenSearch Internal Time (most accurate for performance comparisons)
opensearch_took=$(echo "$result" | jq '.took')

# Pure ML Inference Time (from application logs)
# Check logs for "completed successfully in XXXms" messages
```

#### 2. Which Method to Use When
- **Concurrent Performance Testing** → Use `OpenSearch took` time ✅
- **User Experience Testing** → Use `HTTP client` time
- **ML Model Performance** → Use `log inference` time
- **Network Impact Analysis** → Compare HTTP vs took time

#### 3. Testing Best Practices Checklist
```bash
# ✅ CRITICAL: Always verify functionality works
highlights=$(echo "$result" | jq '[.hits.hits[] | select(has("highlight"))] | length')
hit_count=$(echo "$result" | jq '.hits.hits | length')
expected_k=5  # or whatever K value you're testing

# Validate hit count equals K
[ "$hit_count" -eq "$expected_k" ] || echo "ERROR: Expected $expected_k hits, got $hit_count"

# Validate highlights exist for all hits
[ "$highlights" -eq "$expected_k" ] || echo "ERROR: Expected $expected_k highlights, got $highlights"

# Check for empty highlights
empty_highlights=$(echo "$result" | jq '[.hits.hits[] | select(.highlight.text[0] == "")] | length')
[ "$empty_highlights" -eq 0 ] || echo "WARNING: Found $empty_highlights empty highlights"

# ✅ Use correct model IDs (check bin/dev/model_ids.txt)
source bin/dev/model_ids.txt

# ✅ Use increased heap size for performance testing
export OPENSEARCH_JAVA_OPTS="-Xms4g -Xmx6g -XX:MaxDirectMemorySize=2g"

# ✅ Run multiple iterations for statistical significance
for i in {1..10}; do
    # test and collect results with validation
done

# ✅ Monitor logs for internal execution validation
tail -f ../../build/testclusters/integTest-0/logs/opensearch.stdout.log | grep "semantic-hl"

# ✅ Account for warm-up effects (first request often slower)
```

#### 4. Performance Analysis Framework
```bash
# Calculate concurrent efficiency
baseline_time_k1=300ms
actual_time_k5=900ms
theoretical_time_k5=$((baseline_time_k1 * 5))  # 1500ms
efficiency=$((theoretical_time_k5 * 100 / actual_time_k5))  # 166%
improvement=$((efficiency - 100))  # 66% improvement
```

#### 5. Common Testing Pitfalls to Avoid
- ❌ Using wrong/expired model IDs → leads to false fast times
- ❌ Not checking if highlights are actually generated
- ❌ Single-run tests → network jitter affects results
- ❌ Ignoring warm-up effects → first request often anomalous
- ❌ Not validating internal logs → may miss silent failures

#### 6. Configuration Tuning Parameters
```bash
# Dynamic semantic highlighting parallelism setting
curl -X PUT "localhost:9200/_cluster/settings" -H 'Content-Type: application/json' -d'{
  "persistent": {
    "plugins.neural_search.semantic_highlighting.max_parallelism": 16
  }
}'

# Check current settings
curl -X GET "localhost:9200/_cluster/settings"
```

### Performance Optimization Results (Latest)
- **优化前 (K=5)**: ~865ms (semantic highlighting 不工作)
- **优化后 (K=5)**: ~479ms (44% 性能提升)
- **ML推理优化**: 从162ms降至112-123ms per task
- **批处理策略**: batchSize=2，确保小K值查询正常触发
- **并行效率**: 169% (69% 提升相比串行处理)
- **Thread Pool**: 12 threads (CPU-based), 1000 queue size
- **Architecture**: OpenSearch FetchSubPhase constraints require synchronous waiting per document, but enables inter-request concurrency

### Performance Analysis Tools
```bash
# Detailed performance analysis
grep "semantic-hl-opt-timing.*ML" ../../build/testclusters/integTest-0/logs/opensearch.stdout.log

# Batch processing effectiveness
grep "Batch.*completed" ../../build/testclusters/integTest-0/logs/opensearch.stdout.log

# Concurrency analysis
grep "concurrent=" ../../build/testclusters/integTest-0/logs/opensearch.stdout.log

# Queue wait time analysis
grep "queueTime=" ../../build/testclusters/integTest-0/logs/opensearch.stdout.log
```

## Troubleshooting

### Common Issues and Solutions
```bash
# 1. Port occupied error
pkill -f "org.opensearch.bootstrap.OpenSearch"

# 2. Model IDs expired/invalid
cd bin/dev && ./1_setup.sh  # Re-run setup

# 3. No highlight results
# Check if semantic highlighting is properly configured
highlights=$(echo "$result" | jq '[.hits.hits[] | select(has("highlight"))] | length')
[ "$highlights" -gt 0 ] || echo "WARNING: No highlights generated!"

# 4. Performance anomalies
# Compare with main branch baseline performance
git checkout main && ./gradlew run && cd bin/dev && ./3_benchmark.sh
```

### Key Configuration Parameters
```bash
# Semantic highlighting parallelism
plugins.neural_search.semantic_highlighting.max_parallelism: 8

# Thread pool configuration
thread_pool.semantic_highlight.size: 12
thread_pool.semantic_highlight.queue_size: 1000
```

## Git Workflow and Branch Strategy

### Current Development Setup
```bash
# Branch structure
- Feature Branch: parallel-1 (current work)
- Main Branch: main (baseline comparison)
- Commit Convention: conventional commits (feat:, fix:, docs:)

# Performance testing workflow
1. Develop on parallel-1 branch
2. Compare performance with main branch
3. Ensure semantic highlighting functionality works
4. Document performance improvement metrics
```

### Code Architecture Key Points
```bash
# Core optimization implementation
- OptimizedSemanticHighlightSubPhase.java: Main optimization class
- Batch Processing Logic: Fixes small K-value query batch triggering
- Performance Monitoring: AtomicLong counters track timing at each stage
- Async Concurrency: CompletableFuture enables true concurrent processing
```

### Development Script Usage
```bash
# Always use scripts from bin/dev/ directory
cd bin/dev
./1_setup.sh    # Model IDs saved to model_ids.txt (current directory)
./3_benchmark.sh # Auto-reads model_ids.txt

# Important: Scripts now use relative paths (model_ids.txt)
# No longer: bin/dev/model_ids.txt (fixed path duplication issue)
```

## Important Notes
- Focus on neural-search plugin modifications only
- Ensure semantic highlighting correctness while improving performance
- Use systematic approach to identify performance bottlenecks
- Document performance improvements with concrete metrics
- Always validate that semantic highlighting actually executes (check highlights > 0)
- Use OpenSearch 'took' time for accurate performance comparisons
- Use `./gradlew run --preserve-data` to save setup time during development

## Documentation Standards
- **All analysis documents** must be created in `bin/docs/` directory
- **File naming convention**: `{document_name}_$(date '+%Y%m%d_%H%M%S').md`
- **Timestamp format**: YYYYMMDD_HHMMSS (e.g., 20250615_000737)
- **Purpose**: Track development progress and compare different optimization versions
- **Example**: `semantic_highlighting_analysis_20250615_143022.md`
