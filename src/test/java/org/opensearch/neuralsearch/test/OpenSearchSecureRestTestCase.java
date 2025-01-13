/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.test;

import org.opensearch.test.rest.OpenSearchRestTestCase;
import org.opensearch.common.settings.Settings;

/**
 * Base class for REST tests
 */
public abstract class OpenSearchSecureRestTestCase extends OpenSearchRestTestCase {

    @Override
    protected Settings restClientSettings() {
        return Settings.builder().put(super.restClientSettings()).build();
    }

    @Override
    protected String getProtocol() {
        // Use HTTP for testing
        return "http";
    }
}
