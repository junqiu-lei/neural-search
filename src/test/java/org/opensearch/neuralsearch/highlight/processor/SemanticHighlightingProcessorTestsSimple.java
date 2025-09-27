/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.highlight.processor;

import org.opensearch.neuralsearch.highlight.batch.processor.SemanticHighlightingProcessor;
import org.opensearch.neuralsearch.ml.MLCommonsClientAccessor;
import org.opensearch.test.OpenSearchTestCase;

import static org.mockito.Mockito.mock;

public class SemanticHighlightingProcessorTestsSimple extends OpenSearchTestCase {

    public void testProcessorCreation() {
        MLCommonsClientAccessor mlClientAccessor = mock(MLCommonsClientAccessor.class);
        SemanticHighlightingProcessor processor = new SemanticHighlightingProcessor(false, mlClientAccessor);

        assertNotNull(processor);
        assertEquals("semantic_highlighting", processor.getType());
        assertFalse(processor.isIgnoreFailure());
    }
}
