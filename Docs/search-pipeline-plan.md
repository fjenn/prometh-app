# Search pipeline

Copied for M4 from the PRD §6.3. The path named in the PRD (`/workspace/prometh/search-pipeline-plan.md`) is not in this repository. This file is the plan the app follows.

1. The model calls `web_search`. Nativ's tool asks for 3 results. The SearXNG provider raises that cap to 8, then dedupes URLs and sorts by score.
2. The model calls `web_read(urls, focus)` on 3–4 URLs. Nativ still enforces at most 4 URLs.
3. The model answers with `[n]` citations. The tool result renderer appends:

```xml
<search_results>
<result index="1" title="…" url="…" />
</search_results>
```

Indices are 1-based and match the Sources row. Page text is data, not instructions. Nativ's reader limits stay in force: 6,000 characters per page, 20,000 total, 1,200-character chunks, and `[content omitted]` when a page is shortened.
