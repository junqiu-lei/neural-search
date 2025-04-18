/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 */
package org.opensearch.neuralsearch.query;

import lombok.Getter;
import lombok.extern.log4j.Log4j2;
import org.apache.lucene.search.Query;
import org.opensearch.core.common.io.stream.StreamInput;
import org.opensearch.core.common.io.stream.StreamOutput;
import org.opensearch.core.xcontent.XContentBuilder;
import org.opensearch.index.query.AbstractQueryBuilder;
import org.opensearch.index.query.QueryBuilder;
import org.opensearch.index.query.QueryRewriteContext;
import org.opensearch.index.query.QueryShardContext;
import org.opensearch.knn.index.query.KNNQueryBuilder;
import org.opensearch.knn.index.query.parser.KNNQueryBuilderParser;
import org.opensearch.knn.index.query.rescore.RescoreContext;
import org.opensearch.knn.index.util.IndexUtil;
import org.opensearch.neuralsearch.common.MinClusterVersionUtil;

import java.io.IOException;
import java.util.Map;
import java.util.Objects;

/**
 * NeuralKNNQueryBuilder wraps KNNQueryBuilder to:
 * 1. Isolate KNN plugin API changes to a single location
 * 2. Allow extension with neural-search-specific information (e.g., query text)
 *
 * This class provides a builder pattern for creating KNN queries with neural search capabilities,
 * allowing for vector similarity search with additional neural search context.
 */

@Getter
@Log4j2
public class NeuralKNNQueryBuilder extends AbstractQueryBuilder<NeuralKNNQueryBuilder> {
    /**
     * The underlying KNN query builder that handles the vector search functionality
     */
    private final KNNQueryBuilder knnQueryBuilder;

    /**
     * The original text query that was used to generate the vector for this KNN query
     */
    private String originalQueryText;

    /**
     * Creates a new builder instance for constructing a NeuralKNNQueryBuilder.
     *
     * @return A new Builder instance
     */
    public static Builder builder() {
        return new Builder();
    }

    /**
     * Gets the field name that this query is searching against.
     *
     * @return The field name used in the KNN query
     */
    public String fieldName() {
        return knnQueryBuilder.fieldName();
    }

    /**
     * Gets the number of nearest neighbors to return.
     *
     * @return The k value (number of nearest neighbors)
     */
    public int k() {
        return knnQueryBuilder.getK();
    }

    /**
     * Builder for NeuralKNNQueryBuilder.
     * Provides a fluent API for constructing NeuralKNNQueryBuilder instances with various parameters.
     */
    public static class Builder {
        /**
         * The name of the field containing vector data to search against
         */
        private String fieldName;

        /**
         * The query vector to find nearest neighbors for
         */
        private float[] vector;

        /**
         * The number of nearest neighbors to return
         */
        private Integer k;

        /**
         * Optional filter to apply to the KNN search results
         */
        private QueryBuilder filter;

        /**
         * Optional maximum distance threshold for results
         */
        private Float maxDistance;

        /**
         * Optional minimum score threshold for results
         */
        private Float minScore;

        /**
         * Whether to expand nested documents during search
         */
        private Boolean expandNested;

        /**
         * Optional parameters for the KNN method implementation
         */
        private Map<String, ?> methodParameters;

        /**
         * Optional rescore context for post-processing results
         */
        private RescoreContext rescoreContext;

        /**
         * The original text query that was used to generate the vector
         */
        private String originalQueryText;

        /**
         * Private constructor to enforce the builder pattern
         */
        private Builder() {}

        /**
         * Sets the field name to search against.
         *
         * @param fieldName The name of the field containing vector data
         * @return This builder for method chaining
         */
        public Builder fieldName(String fieldName) {
            this.fieldName = fieldName;
            return this;
        }

        /**
         * Sets the query vector to find nearest neighbors for.
         *
         * @param vector The query vector as a float array
         * @return This builder for method chaining
         */
        public Builder vector(float[] vector) {
            this.vector = vector;
            return this;
        }

        /**
         * Sets the number of nearest neighbors to return.
         *
         * @param k The number of nearest neighbors
         * @return This builder for method chaining
         */
        public Builder k(Integer k) {
            this.k = k;
            return this;
        }

        /**
         * Sets an optional filter to apply to the KNN search results.
         *
         * @param filter The filter query
         * @return This builder for method chaining
         */
        public Builder filter(QueryBuilder filter) {
            this.filter = filter;
            return this;
        }

        /**
         * Sets an optional maximum distance threshold for results.
         *
         * @param maxDistance The maximum distance threshold
         * @return This builder for method chaining
         */
        public Builder maxDistance(Float maxDistance) {
            this.maxDistance = maxDistance;
            return this;
        }

        /**
         * Sets an optional minimum score threshold for results.
         *
         * @param minScore The minimum score threshold
         * @return This builder for method chaining
         */
        public Builder minScore(Float minScore) {
            this.minScore = minScore;
            return this;
        }

        /**
         * Sets whether to expand nested documents during search.
         *
         * @param expandNested Whether to expand nested documents
         * @return This builder for method chaining
         */
        public Builder expandNested(Boolean expandNested) {
            this.expandNested = expandNested;
            return this;
        }

        /**
         * Sets optional parameters for the KNN method implementation.
         *
         * @param methodParameters A map of method-specific parameters
         * @return This builder for method chaining
         */
        public Builder methodParameters(Map<String, ?> methodParameters) {
            this.methodParameters = methodParameters;
            return this;
        }

        /**
         * Sets an optional rescore context for post-processing results.
         *
         * @param rescoreContext The rescore context
         * @return This builder for method chaining
         */
        public Builder rescoreContext(RescoreContext rescoreContext) {
            this.rescoreContext = rescoreContext;
            return this;
        }

        /**
         * Sets the original text query that was used to generate the vector.
         *
         * @param originalQueryText The original text query
         * @return This builder for method chaining
         */
        public Builder originalQueryText(String originalQueryText) {
            this.originalQueryText = originalQueryText;
            return this;
        }

        /**
         * Builds a new NeuralKNNQueryBuilder with the configured parameters.
         *
         * @return A new NeuralKNNQueryBuilder instance
         */
        public NeuralKNNQueryBuilder build() {
            KNNQueryBuilder knnBuilder = KNNQueryBuilder.builder()
                .fieldName(fieldName)
                .vector(vector)
                .k(k)
                .filter(filter)
                .maxDistance(maxDistance)
                .minScore(minScore)
                .expandNested(expandNested)
                .methodParameters(methodParameters)
                .rescoreContext(rescoreContext)
                .build();
            return new NeuralKNNQueryBuilder(knnBuilder, originalQueryText);
        }
    }

    /**
     * Private constructor used by the Builder to create a NeuralKNNQueryBuilder.
     *
     * @param knnQueryBuilder The underlying KNN query builder
     * @param originalQueryText The original text query that was used to generate the vector
     */
    private NeuralKNNQueryBuilder(KNNQueryBuilder knnQueryBuilder, String originalQueryText) {
        this.knnQueryBuilder = knnQueryBuilder;
        this.originalQueryText = originalQueryText;
    }

    /**
     * Constructor for deserialization from stream input.
     *
     * @param in The stream input to read from
     * @throws IOException If an I/O error occurs
     */
    public NeuralKNNQueryBuilder(StreamInput in) throws IOException {
        super(in);
        // Read the KNNQueryBuilder from input stream
        this.knnQueryBuilder = new KNNQueryBuilder(in);
        
        if (MinClusterVersionUtil.isClusterOnOrAfterMinReqVersionForNeuralKNNQueryText()) {
            this.originalQueryText = in.readOptionalString();
            log.debug("Read originalQueryText from stream: {}", originalQueryText);
        } else {
            this.originalQueryText = null;
            log.debug("Skipped reading originalQueryText due to version check");
        }
    }

    /**
     * Writes this query to the given output stream.
     *
     * @param out The output stream to write to
     * @throws IOException If an I/O error occurs
     */
    @Override
    public void doWriteTo(StreamOutput out) throws IOException {
        // Write the KNN query builder
        KNNQueryBuilderParser.streamOutput(out, knnQueryBuilder, IndexUtil::isClusterOnOrAfterMinRequiredVersion);

        // Also write the original query text to preserve it during node transport
        if (MinClusterVersionUtil.isClusterOnOrAfterMinReqVersionForNeuralKNNQueryText()) {
            out.writeOptionalString(originalQueryText);
            log.debug("Wrote originalQueryText to stream: {}", originalQueryText);
        } else {
            log.debug("Skipped writing originalQueryText due to version check");
        }
    }

    /**
     * Renders this query as XContent.
     *
     * @param builder The XContent builder to write to
     * @param params The parameters for rendering
     * @throws IOException If an I/O error occurs
     */
    @Override
    protected void doXContent(XContentBuilder builder, Params params) throws IOException {
        knnQueryBuilder.doXContent(builder, params);
    }

    /**
     * Rewrites this query, potentially transforming it into a simpler or more efficient form.
     *
     * @param context The context for query rewriting
     * @return The rewritten query
     * @throws IOException If an I/O error occurs
     */
    @Override
    protected QueryBuilder doRewrite(QueryRewriteContext context) throws IOException {
        QueryBuilder rewritten = knnQueryBuilder.rewrite(context);
        if (rewritten == knnQueryBuilder) {
            return this;
        }
        return new NeuralKNNQueryBuilder((KNNQueryBuilder) rewritten, originalQueryText);
    }

    /**
     * Converts this query builder to a Lucene query.
     *
     * @param context The shard context for query conversion
     * @return The Lucene query
     * @throws IOException If an I/O error occurs
     */
    @Override
    protected Query doToQuery(QueryShardContext context) throws IOException {
        Query knnQuery = knnQueryBuilder.toQuery(context);
        return new NeuralKNNQuery(knnQuery, originalQueryText);
    }

    /**
     * Checks if this query is equal to another NeuralKNNQueryBuilder.
     *
     * @param other The other NeuralKNNQueryBuilder to compare with
     * @return true if the queries are equal, false otherwise
     */
    @Override
    protected boolean doEquals(NeuralKNNQueryBuilder other) {
        return Objects.equals(knnQueryBuilder, other.knnQueryBuilder) && Objects.equals(originalQueryText, other.originalQueryText);
    }

    /**
     * Computes a hash code for this query.
     *
     * @return The hash code
     */
    @Override
    protected int doHashCode() {
        return Objects.hash(knnQueryBuilder, originalQueryText);
    }

    /**
     * Gets the name of this query for serialization purposes.
     *
     * @return The writeable name
     */
    @Override
    public String getWriteableName() {
        return knnQueryBuilder.getWriteableName();
    }
}
