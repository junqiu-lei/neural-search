# OpenSearch Issue #1331: Search Template Ext Parameters

This directory contains all work related to fixing the search template ext parameters issue that prevents generative QA from working with search templates.

## Issue Summary
- **Problem**: Search templates lose ext parameters (like `generative_qa_parameters`) during template expansion
- **Impact**: RAG/Generative QA doesn't work with search templates
- **Root Cause**: `TransportSearchTemplateAction.convert()` creates new SearchSourceBuilder without preserving ext

## Directory Structure

```
.
├── README.md                                    # This file
├── ISSUE_1331_WORK_SUMMARY.md                  # Complete work summary
├── SEARCH_TEMPLATE_EXT_INVESTIGATION.md        # Initial investigation
├── SEARCH_TEMPLATE_EXT_ISSUE.md               # Concise problem description
├── SEARCH_TEMPLATE_EXT_COMPLETE_ANALYSIS.md    # Full technical analysis
│
├── opensearch-core-fix/                        # OpenSearch core fix
│   ├── TransportSearchTemplateAction.patch     # The patch file
│   └── TransportSearchTemplateActionTests.java # Unit tests
│
├── ml-commons-workaround/                      # ML Commons workaround
│   ├── GenerativeQATemplateProcessor.java      # Processor implementation
│   └── GenerativeQATemplateProcessorIT.java    # Integration tests
│
├── ext-parameter-preserving-processor-*.java   # Original processor approach
├── issue-1331-*.md                            # Various documentation files
├── sample-test-case-ext-params.sh            # Demo script
├── setup-opensearch-core-fix.sh              # Setup for core fix
└── setup-ml-commons-workaround.sh            # Setup for ML Commons
```

## Quick Start

### Option 1: Immediate User Workaround (No code changes)
Include ext parameters directly in your search template:
```json
PUT _scripts/my_template
{
  "script": {
    "lang": "mustache",
    "source": {
      "query": { "match": { "content": "{{query}}" } },
      "ext": {
        "generative_qa_parameters": {
          "llm_model": "gpt-4",
          "context_size": 5
        }
      }
    }
  }
}
```

### Option 2: ML Commons Workaround (Production ready)
1. Copy files from `ml-commons-workaround/` to your ml-commons repo
2. Run `./setup-ml-commons-workaround.sh`
3. Create search pipeline with the processor
4. Use pipeline when executing search templates

### Option 3: OpenSearch Core Fix (Permanent solution)
1. Copy files from `opensearch-core-fix/` to your OpenSearch repo
2. Run `./setup-opensearch-core-fix.sh`
3. Create PR to OpenSearch repository

## Key Files

- **ISSUE_1331_WORK_SUMMARY.md** - Start here for complete overview
- **issue-1331-implementation-guide.md** - Step-by-step implementation
- **issue-1331-production-solution.md** - Production deployment guide
- **sample-test-case-ext-params.sh** - Working demo you can run

## Testing

Run the demo script to see the issue and solution:
```bash
./sample-test-case-ext-params.sh
```

## Git Information
- Branch: `fix/issue-1331-search-template-ext-params`
- Repository: neural-search (original work location)

## Related Links
- GitHub Issue: https://github.com/opensearch-project/neural-search/issues/1331
- OpenSearch Core: https://github.com/opensearch-project/OpenSearch
- ML Commons: https://github.com/opensearch-project/ml-commons

## Status
- Investigation: ✅ Complete
- Root cause: ✅ Identified
- Solutions: ✅ Implemented
- Tests: ✅ Created
- Documentation: ✅ Complete
- Ready for: PR submission