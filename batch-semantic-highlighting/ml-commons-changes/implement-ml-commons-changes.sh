#!/bin/bash

# Script to implement ML Commons changes for batch highlighting support
# Run this script from the ml-commons repository root

echo "=== Implementing ML Commons Batch Highlighting Support ==="

# 1. Create BatchHighlightingInputDataSet
echo "Creating BatchHighlightingInputDataSet..."

cat > common/src/main/java/org/opensearch/ml/common/dataset/BatchHighlightingInputDataSet.java << 'EOF'
/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.ml.common.dataset;

import lombok.Builder;
import lombok.Getter;
import lombok.Setter;
import org.opensearch.core.common.io.stream.StreamInput;
import org.opensearch.core.common.io.stream.StreamOutput;
import org.opensearch.ml.common.annotation.InputDataSet;
import org.opensearch.ml.common.input.MLInputDataType;

import java.io.IOException;
import java.util.ArrayList;
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
            Map<String, String> item = in.readMap(StreamInput::readString, StreamInput::readString);
            this.batch.add(item);
        }
    }
    
    @Override
    public void writeTo(StreamOutput out) throws IOException {
        super.writeTo(out);
        out.writeVInt(batch.size());
        for (Map<String, String> item : batch) {
            out.writeMap(item, StreamOutput::writeString, StreamOutput::writeString);
        }
    }
    
    @Override
    public int size() {
        return batch != null ? batch.size() : 0;
    }
}
EOF

# 2. Update MLInputDataType enum
echo "Updating MLInputDataType enum..."
# This would need to be done manually by editing the file
echo "TODO: Add BATCH_HIGHLIGHTING to MLInputDataType enum in:"
echo "  common/src/main/java/org/opensearch/ml/common/input/MLInputDataType.java"

# 3. Create unit test for BatchHighlightingInputDataSet
echo "Creating unit test..."

cat > common/src/test/java/org/opensearch/ml/common/dataset/BatchHighlightingInputDataSetTest.java << 'EOF'
/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.ml.common.dataset;

import org.junit.Test;
import org.opensearch.common.io.stream.BytesStreamOutput;
import org.opensearch.core.common.io.stream.StreamInput;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;

public class BatchHighlightingInputDataSetTest {

    @Test
    public void testConstructorAndGetters() {
        List<Map<String, String>> batch = createTestBatch();
        BatchHighlightingInputDataSet dataset = BatchHighlightingInputDataSet.builder()
            .batch(batch)
            .build();
        
        assertNotNull(dataset);
        assertEquals(2, dataset.size());
        assertEquals(batch, dataset.getBatch());
    }

    @Test
    public void testSerialization() throws IOException {
        List<Map<String, String>> batch = createTestBatch();
        BatchHighlightingInputDataSet dataset = BatchHighlightingInputDataSet.builder()
            .batch(batch)
            .build();
        
        BytesStreamOutput output = new BytesStreamOutput();
        dataset.writeTo(output);
        
        StreamInput input = output.bytes().streamInput();
        BatchHighlightingInputDataSet deserializedDataset = new BatchHighlightingInputDataSet(input);
        
        assertEquals(dataset.size(), deserializedDataset.size());
        assertEquals(dataset.getBatch(), deserializedDataset.getBatch());
    }
    
    private List<Map<String, String>> createTestBatch() {
        List<Map<String, String>> batch = new ArrayList<>();
        
        Map<String, String> item1 = new HashMap<>();
        item1.put("question", "What is the capital?");
        item1.put("context", "The capital of France is Paris.");
        item1.put("documentId", "doc1");
        batch.add(item1);
        
        Map<String, String> item2 = new HashMap<>();
        item2.put("question", "What is the population?");
        item2.put("context", "Paris has a population of 2.1 million.");
        item2.put("documentId", "doc2");
        batch.add(item2);
        
        return batch;
    }
}
EOF

echo "=== ML Commons Changes Implementation Complete ==="
echo ""
echo "Next steps:"
echo "1. Add BATCH_HIGHLIGHTING to MLInputDataType enum"
echo "2. Update MLInputDatasetHandler to register BatchHighlightingInputDataSet"
echo "3. Update RemoteConnectorExecutor to handle batch parameters properly"
echo "4. Build and test ml-commons"
echo "5. Update neural-search build.gradle to use the new ml-commons version"