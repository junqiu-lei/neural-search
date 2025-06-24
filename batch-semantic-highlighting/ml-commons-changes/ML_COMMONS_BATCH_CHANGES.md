# ML Commons Changes for Batch Semantic Highlighting

## Overview

This document outlines the necessary changes in the ML Commons plugin to support batch semantic highlighting in the neural-search plugin.

## Required Changes

### 1. Create BatchHighlightingInputDataSet

**Location**: `org.opensearch.ml.common.dataset`

```java
package org.opensearch.ml.common.dataset;

import lombok.Builder;
import lombok.Getter;
import lombok.Setter;
import org.opensearch.core.common.io.stream.StreamInput;
import org.opensearch.core.common.io.stream.StreamOutput;
import org.opensearch.ml.common.annotation.InputDataSet;

import java.io.IOException;
import java.util.List;
import java.util.Map;

@Getter
@InputDataSet(MLInputDataType.BATCH_HIGHLIGHTING)
public class BatchHighlightingInputDataSet extends MLInputDataset {
    
    @Setter
    private List<Map<String, String>> batch;
    
    @Builder
    public BatchHighlightingInputDataSet(List<Map<String, String>> batch) {
        this.inputDataType = MLInputDataType.BATCH_HIGHLIGHTING;
        this.batch = batch;
    }
    
    public BatchHighlightingInputDataSet(StreamInput in) throws IOException {
        super(MLInputDataType.BATCH_HIGHLIGHTING);
        int size = in.readVInt();
        this.batch = new ArrayList<>(size);
        for (int i = 0; i < size; i++) {
            this.batch.add(in.readMap());
        }
    }
    
    @Override
    public void writeTo(StreamOutput out) throws IOException {
        super.writeTo(out);
        out.writeVInt(batch.size());
        for (Map<String, String> item : batch) {
            out.writeMap(item);
        }
    }
    
    @Override
    public int size() {
        return batch != null ? batch.size() : 0;
    }
}
```

### 2. Add BATCH_HIGHLIGHTING to MLInputDataType

**Location**: `org.opensearch.ml.common.input.MLInputDataType`

```java
public enum MLInputDataType {
    // ... existing types ...
    BATCH_HIGHLIGHTING;
}
```

### 3. Update RemoteConnectorExecutor for Complex Parameters

**Location**: `org.opensearch.ml.engine.algorithms.remote.RemoteConnectorExecutor`

#### Current Issue
The current implementation converts all parameters to JSON strings:
```java
Map<String, String> parameters = StringUtils.convertScriptStringToJsonString(parametersMap);
```

This creates: `{"batch": "[{\"question\":\"...\",\"context\":\"...\"}]"}`

But SageMaker expects: `{"parameters": {"batch": [{"question": "...", "context": "..."}]}}`

#### Proposed Solution

**Option 1: Add Complex Parameter Support**
```java
// In RemoteConnectorExecutor.preparePayload()
private String preparePayload(MLInput mlInput) {
    if (mlInput.getInputDataset() instanceof BatchHighlightingInputDataSet) {
        BatchHighlightingInputDataSet dataset = (BatchHighlightingInputDataSet) mlInput.getInputDataset();
        
        // Create proper JSON structure
        Map<String, Object> payload = new HashMap<>();
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("batch", dataset.getBatch());
        payload.put("parameters", parameters);
        
        return toJson(payload);
    }
    // ... existing logic ...
}
```

**Option 2: Pre/Post Processing Function**
```java
@Override
public void executePreProcessFunction(RemoteConnectorContext context, MLInput input) {
    if (input.getInputDataset() instanceof BatchHighlightingInputDataSet) {
        // Transform the batch data into the expected format
        BatchHighlightingInputDataSet dataset = (BatchHighlightingInputDataSet) input.getInputDataset();
        Map<String, Object> transformedParams = new HashMap<>();
        transformedParams.put("batch", dataset.getBatch());
        context.setParameters(transformedParams);
    }
}
```

### 4. Response Processing for Batch Results

**Location**: `org.opensearch.ml.engine.algorithms.remote.RemoteConnectorExecutor`

```java
@Override
public ModelTensorOutput executePostProcessFunction(Object response, MLInput input) {
    if (input.getInputDataset() instanceof BatchHighlightingInputDataSet) {
        // Parse batch response
        // Expected format: {"results": [{"highlights": [...]}, ...]}
        List<ModelTensors> outputs = new ArrayList<>();
        
        // Parse response and create ModelTensors for each result
        // ...
        
        return new ModelTensorOutput(outputs);
    }
    // ... existing logic ...
}
```

### 5. Register Dataset in MLInputDatasetHandler

**Location**: `org.opensearch.ml.common.input.handler.MLInputDatasetHandler`

```java
static {
    // ... existing registrations ...
    register(MLInputDataType.BATCH_HIGHLIGHTING, BatchHighlightingInputDataSet::new);
}
```

## Testing Requirements

1. **Unit Tests**
   - Test BatchHighlightingInputDataSet serialization/deserialization
   - Test parameter transformation
   - Test response parsing

2. **Integration Tests**
   - Test with local models
   - Test with SageMaker endpoints
   - Test error handling

## Migration Considerations

1. **Backward Compatibility**: Ensure existing highlighting continues to work
2. **Feature Flag**: Use the `use_batch` flag to control behavior
3. **Graceful Degradation**: Fall back to single processing if batch fails

## Performance Targets

- Batch processing should achieve 5-10x performance improvement
- Minimize memory overhead for batch collection
- Support configurable batch sizes

## Security Considerations

1. Validate batch size limits to prevent DoS
2. Ensure proper authentication for batch requests
3. Sanitize input data in batches

## Next Steps

1. Implement BatchHighlightingInputDataSet in ml-commons
2. Update RemoteConnectorExecutor for proper parameter handling
3. Add response parsing for batch results
4. Create comprehensive test suite
5. Document API changes