/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch;

import org.opensearch.client.Response;
import org.opensearch.common.xcontent.XContentType;
import org.opensearch.core.xcontent.XContentParser;
import org.opensearch.core.xcontent.XContentParserUtils;

import java.io.IOException;
import java.io.InputStream;
import java.util.Map;

/**
 * Utility methods for tests
 */
public class TestUtils {

    /**
     * Convert REST response to Map
     *
     * @param response REST response
     * @return Map representation of response
     * @throws IOException if parsing fails
     */
    public static Map<String, Object> toMap(Response response) throws IOException {
        try (InputStream content = response.getEntity().getContent()) {
            XContentParser parser = XContentType.JSON.xContent().createParser(null, null, content);
            XContentParserUtils.ensureExpectedToken(XContentParser.Token.START_OBJECT, parser.nextToken(), parser);
            return parser.map();
        }
    }
}
