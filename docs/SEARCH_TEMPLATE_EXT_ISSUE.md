# Search Template Ext Parameter Flow Issue

## Problem Summary

When using search templates with ext parameters (e.g., ML inference parameters), the ext parameters are lost during template processing. This prevents ML inference and other ext-based functionality from working with search templates.

## Root Cause

In `TransportSearchTemplateAction.convert()` method, when a search template is processed:

1. The template is executed to generate the search JSON
2. A new `SearchSourceBuilder` is created from this generated JSON
3. This new builder replaces the original one in the SearchRequest
4. **The original ext parameters are NOT preserved**

### Code Location

File: `/home/junqiu/OpenSearch/modules/lang-mustache/src/main/java/org/opensearch/script/mustache/TransportSearchTemplateAction.java`

```java
static SearchRequest convert(...) throws IOException {
    // ... template execution ...
    
    SearchRequest searchRequest = searchTemplateRequest.getRequest();
    
    try (XContentParser parser = ...) {
        // Line 151: Creates NEW SearchSourceBuilder
        SearchSourceBuilder builder = SearchSourceBuilder.searchSource();
        // Line 152: Parses template output into new builder
        builder.parseXContent(parser, false);
        // ...
        // Line 156: Replaces original source (losing ext params!)
        searchRequest.source(builder);
    }
    return searchRequest;
}
```

## Impact

This affects any functionality that relies on ext parameters, including:
- ML inference search request processors
- Any custom ext builders registered by plugins

## Reproduction Steps

1. Create a search request with ext parameters:
```json
POST /my-index/_search
{
  "query": {"match_all": {}},
  "ext": {
    "ml_inference": {
      "model_id": "my-model",
      "input_map": {...}
    }
  }
}
```

2. Use the same request with a search template:
```json
POST /_search/template
{
  "source": {
    "query": {"match_all": {}}
  },
  "params": {},
  "ext": {
    "ml_inference": {
      "model_id": "my-model", 
      "input_map": {...}
    }
  }
}
```

3. The ext parameters will be lost during template processing

## Proposed Fix

In `TransportSearchTemplateAction.convert()`, preserve ext parameters from the original request:

```java
static SearchRequest convert(...) throws IOException {
    // ... existing template execution code ...
    
    SearchRequest searchRequest = searchTemplateRequest.getRequest();
    
    try (XContentParser parser = ...) {
        SearchSourceBuilder builder = SearchSourceBuilder.searchSource();
        builder.parseXContent(parser, false);
        builder.explain(searchTemplateRequest.isExplain());
        builder.profile(searchTemplateRequest.isProfile());
        
        // PROPOSED FIX: Preserve ext parameters from original request
        SearchSourceBuilder originalSource = searchRequest.source();
        if (originalSource != null && !originalSource.ext().isEmpty()) {
            builder.ext(originalSource.ext());
        }
        
        checkRestTotalHitsAsInt(searchRequest, builder);
        searchRequest.source(builder);
    }
    return searchRequest;
}
```

## Alternative Solutions

1. **Template-level ext support**: Allow ext parameters to be included in the template itself
2. **Request-level preservation**: Always preserve certain fields from the original request that shouldn't be overridden by templates

## Testing

A test should be added to verify:
1. Ext parameters are preserved when using search templates
2. Ext parameters in the template can override request-level ext parameters (if desired)
3. Multiple ext builders are properly preserved