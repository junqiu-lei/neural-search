# Batch Semantic Highlighting Test Plan

## Test Categories

### 1. Unit Tests

#### Neural Search Plugin

**MLCommonsClientAccessor Tests**
- Test `inferenceBatchHighlighting` with various batch sizes
- Test retry logic for batch requests
- Test error handling for partial failures
- Mock ML Commons client responses

**SemanticHighlighterEngine Tests**
- Test `getHighlightedSentencesBatch` method
- Test `fetchBatchModelResults` method
- Test batch result correlation
- Test empty batch handling

**SemanticHighlighter Tests**
- Test `use_batch` configuration parsing
- Test batch mode detection
- Test fallback behavior

#### ML Commons Plugin

**BatchHighlightingInputDataSet Tests**
- Test construction with various batch sizes
- Test serialization/deserialization
- Test stream input/output
- Test edge cases (empty batch, null values)

**RemoteConnectorExecutor Tests**
- Test parameter transformation for batch requests
- Test JSON serialization format
- Test response parsing for batch results

### 2. Integration Tests

#### Local Model Tests
```java
@Test
public void testBatchHighlightingWithLocalModel() {
    // Setup
    String modelId = deployLocalHighlightingModel();
    List<Document> documents = createTestDocuments(10);
    
    // Execute
    SearchResponse response = client().prepareSearch("test-index")
        .setQuery(matchQuery("content", "symptoms"))
        .highlighter(new HighlightBuilder()
            .field("content")
            .highlighterType("semantic")
            .options(Map.of(
                "model_id", modelId,
                "use_batch", true
            )))
        .get();
    
    // Verify
    assertThat(response.getHits().getTotalHits().value, equalTo(10L));
    for (SearchHit hit : response.getHits()) {
        assertNotNull(hit.getHighlightFields().get("content"));
    }
}
```

#### Remote Model Tests
```java
@Test
public void testBatchHighlightingWithSageMaker() {
    // Setup
    String connectorId = createSageMakerConnector();
    String modelId = registerRemoteModel(connectorId);
    
    // Test batch highlighting
    // Similar to local model test
}
```

### 3. Performance Tests

#### Benchmark Test
```java
@Test
public void benchmarkBatchVsSingleProcessing() {
    // Setup
    List<Document> documents = createTestDocuments(100);
    
    // Single processing
    long singleStart = System.currentTimeMillis();
    SearchResponse singleResponse = searchWithHighlighting(false);
    long singleTime = System.currentTimeMillis() - singleStart;
    
    // Batch processing
    long batchStart = System.currentTimeMillis();
    SearchResponse batchResponse = searchWithHighlighting(true);
    long batchTime = System.currentTimeMillis() - batchStart;
    
    // Verify performance improvement
    double improvement = (double) singleTime / batchTime;
    assertThat(improvement, greaterThan(5.0));
}
```

### 4. Error Handling Tests

#### Partial Failure Test
```java
@Test
public void testPartialBatchFailure() {
    // Create batch with some invalid documents
    // Verify graceful handling
    // Check successful documents are highlighted
}
```

#### Timeout Test
```java
@Test
public void testBatchTimeout() {
    // Configure short timeout
    // Create large batch
    // Verify timeout handling
}
```

### 5. Compatibility Tests

#### Backward Compatibility
```java
@Test
public void testBackwardCompatibility() {
    // Test without use_batch flag (should default to false)
    // Test with use_batch=false explicitly
    // Verify single processing behavior
}
```

#### Mixed Configuration
```java
@Test
public void testMixedHighlightingTypes() {
    // Use semantic highlighting on one field
    // Use plain highlighting on another
    // Verify both work correctly
}
```

## Test Data

### Sample Documents
```json
[
  {
    "id": "1",
    "title": "COVID-19 Symptoms",
    "content": "Common symptoms of COVID-19 include fever, cough, and fatigue. Some patients also experience loss of taste or smell."
  },
  {
    "id": "2",
    "title": "Flu Symptoms",
    "content": "Influenza symptoms typically include high fever, body aches, and respiratory issues. The onset is usually sudden."
  },
  {
    "id": "3",
    "title": "Cold Symptoms",
    "content": "Common cold symptoms are generally mild and include runny nose, sneezing, and sore throat."
  }
]
```

### Test Queries
- "What are the symptoms?"
- "fever and cough"
- "respiratory issues"
- "loss of taste"

## Test Environment

### Local Development
1. OpenSearch 3.1.0 with neural-search plugin
2. ML Commons with batch highlighting support
3. Local Python model for testing

### CI/CD Pipeline
1. Unit tests run on every commit
2. Integration tests run on PR
3. Performance tests run nightly
4. Compatibility tests on release

## Test Execution Plan

### Phase 1: Unit Tests (Days 1-2)
- Implement all unit tests
- Achieve 80%+ code coverage
- Fix any issues found

### Phase 2: Integration Tests (Days 3-4)
- Set up test environment
- Deploy test models
- Run integration test suite

### Phase 3: Performance Tests (Day 5)
- Benchmark batch vs single processing
- Profile memory usage
- Optimize based on findings

### Phase 4: Error & Compatibility Tests (Day 6)
- Test error scenarios
- Verify backward compatibility
- Document any limitations

## Success Criteria

1. **All tests pass**: 100% of test cases pass
2. **Code coverage**: >80% coverage for new code
3. **Performance**: Batch processing is 5x+ faster
4. **Reliability**: No flaky tests
5. **Documentation**: All test cases documented

## Test Automation

```bash
#!/bin/bash
# run-batch-highlighting-tests.sh

echo "Running Batch Highlighting Test Suite"

# Unit tests
./gradlew :neural-search:test --tests "*Batch*Test"

# Integration tests
./gradlew :neural-search:integTest --tests "*BatchHighlighting*IT"

# Performance tests
./gradlew :neural-search:performanceTest --tests "*BatchHighlightingBenchmark"

# Generate coverage report
./gradlew :neural-search:jacocoTestReport
```

## Known Limitations

1. Highlighter interface processes one field at a time
2. Batch collection requires additional memory
3. Network latency affects batch performance gains
4. Model-specific batch size limits

## Risk Mitigation

1. **Test Data Variety**: Use diverse test data sets
2. **Load Testing**: Test with production-like loads
3. **Error Injection**: Test with network failures, timeouts
4. **Monitoring**: Add metrics for test execution