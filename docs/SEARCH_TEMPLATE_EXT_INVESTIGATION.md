# Search Template Ext Parameter Investigation

## Summary

After investigating the OpenSearch core code, I found that **ext parameters are properly preserved** when using search templates. The issue reported where ext parameters are lost appears to be a misunderstanding of how the system works.

## Key Findings

### 1. Template Processing Flow

The search template processing flow in OpenSearch is:

1. **SearchTemplateRequest** receives the template and parameters
2. **TransportSearchTemplateAction.convert()** processes the template:
   - Uses MustacheScriptEngine to expand the template with provided parameters
   - Creates a SearchSourceBuilder from the expanded JSON
   - Calls `builder.parseXContent(parser, false)` to parse the JSON

### 2. Ext Parameter Handling

In `SearchSourceBuilder.parseXContent()` (lines 1393-1415):
```java
} else if (EXT_FIELD.match(currentFieldName, parser.getDeprecationHandler())) {
    extBuilders = new ArrayList<>();
    String extSectionName = null;
    while ((token = parser.nextToken()) != XContentParser.Token.END_OBJECT) {
        if (token == XContentParser.Token.FIELD_NAME) {
            extSectionName = parser.currentName();
        } else {
            SearchExtBuilder searchExtBuilder = parser.namedObject(SearchExtBuilder.class, extSectionName, null);
            if (searchExtBuilder.getWriteableName().equals(extSectionName) == false) {
                throw new IllegalStateException(...);
            }
            extBuilders.add(searchExtBuilder);
        }
    }
}
```

This code properly parses ext parameters from the template-expanded JSON and creates SearchExtBuilder instances.

### 3. Neural Search Registration

The neural-search plugin properly registers its ext parameter handler:
```java
@Override
public List<SearchPlugin.SearchExtSpec<?>> getSearchExts() {
    return List.of(
        new SearchExtSpec<>(
            RerankSearchExtBuilder.PARAM_FIELD_NAME,
            in -> new RerankSearchExtBuilder(in),
            parser -> RerankSearchExtBuilder.parse(parser)
        )
    );
}
```

## Conclusion

The ext parameters **ARE preserved** during search template processing. The core OpenSearch code:

1. Properly expands templates using Mustache
2. Correctly parses ext fields from the expanded JSON
3. Creates appropriate SearchExtBuilder instances

## Possible Issues

If ext parameters appear to be missing, the likely causes are:

1. **Incorrect template syntax** - The ext block must be at the root level of the search request JSON
2. **Missing plugin registration** - The plugin processing the ext parameter must be properly registered
3. **Query DSL nesting** - If the ext block is nested inside the query, it won't be recognized
4. **Client-side issues** - Some clients might strip ext parameters before sending to OpenSearch

## Example Working Template

```json
{
  "script": {
    "lang": "mustache",
    "source": {
      "query": {
        "match": {
          "field": "{{query_text}}"
        }
      },
      "ext": {
        "rerank": {
          "query_context": {
            "query_text": "{{rerank_query}}",
            "model_id": "{{model_id}}"
          }
        }
      }
    }
  }
}
```

## Verification

To verify ext parameters are preserved:

1. Enable debug logging for `org.opensearch.search.builder.SearchSourceBuilder`
2. Check that the SearchRequest received by your processor contains the ext builders
3. Use the `_search/template` API with `?explain=true` to see the expanded query

## Alternative Solutions

If there are still issues with ext parameter preservation in specific scenarios, consider:

1. Using a search pipeline processor to inject ext parameters
2. Encoding ext parameters in the query metadata
3. Using custom query builders that preserve additional context