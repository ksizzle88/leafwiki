# Full-Text Search & File Indexing for Dev Toolkit

**Research Date**: 2026-03-13
**Context**: Claudio Dev Toolkit (Epic #55) — multiple tools need search across local files (Markdown Browser #57, Agent Builder #60, jtbl #58).
**Stack Context**: FastAPI backend + React frontend (Vite + shadcn/ui), running inside Docker devcontainers. Python 3.12 and Node.js 22 are both available in the base image.

---

## 1. Executive Summary

**Recommendation: Hybrid architecture — SQLite FTS5 (server-side, primary) + MiniSearch (client-side, UI-layer)**

SQLite FTS5 should serve as the unified search index for the Dev Toolkit. It runs server-side in Python (built into the standard library — confirmed working in the Claudio devcontainer with SQLite 3.45.1), provides BM25 ranking, snippet/highlight support, incremental updates, and scales to hundreds of thousands of documents with sub-millisecond query times. It requires zero additional dependencies.

MiniSearch should be used client-side for instant, in-memory filtering of already-loaded data (e.g., filtering a file tree, searching within a loaded JSON dataset in jtbl, or auto-completing search suggestions). It is tiny (~5KB gzipped), has TypeScript support, and is battle-tested in VitePress.

This two-layer approach keeps the heavy indexing on the server (where file system access and persistence live) while giving the frontend instant responsiveness for UI-level filtering.

---

## 2. Client-Side JavaScript Search Libraries

### 2.1 Comparison Table

| Criterion | Lunr.js | FlexSearch | MiniSearch | Fuse.js | Pagefind |
|---|---|---|---|---|---|
| **Type** | TF-IDF inverted index | Context-based scoring | Inverted index | Fuzzy (Bitap algorithm) | WASM static index |
| **Bundle size (gzipped)** | ~8.4 KB | 4.5–16.3 KB (3 tiers) | ~5 KB | ~5.5 KB | ~100 KB (WASM) |
| **Weekly npm downloads** | ~3.7M | ~811K | ~657K | ~6.9M | N/A (CLI tool) |
| **GitHub stars** | ~9.2K | ~13.6K | ~5.8K | ~20K | ~12K |
| **Last maintained** | Stable/slow (years) | Active (5 months ago) | Active (5 months ago) | Stable (1 year ago) | Active |
| **TypeScript support** | Community types | Partial (75%) | Native types | Native types | N/A |
| **Index serialization** | JSON (immutable index) | Custom export/import | JSON (loadJSON) | No index (runtime) | Pre-built WASM chunks |
| **Fuzzy search** | Via wildcards | Phonetic encoders | Native fuzzy + prefix | Core feature (Bitap) | Via WASM |
| **Stemming** | Built-in (14 langs) | Via custom encoders | Manual (via options) | No | Built-in |
| **Dynamic add/remove** | No (immutable) | Yes | Yes | N/A (no index) | No (rebuild required) |
| **Worker support** | No | Yes (bundle only) | No | No | WASM thread |
| **Memory efficiency** | Moderate | Best (16 bytes/op) | Good (mobile-friendly) | Poor (no index) | Excellent (lazy-loaded) |
| **Best for** | Static site search | High-volume real-time | Small-medium interactive | Small fuzzy lists | Static site search |

### 2.2 Detailed Analysis

#### Lunr.js
- **Strengths**: Mature, well-documented, TF-IDF scoring, 14-language stemming, serializable index.
- **Weaknesses**: Immutable index (cannot add/remove documents after build), index build is slow for >100K docs (15+ seconds for 800K items), no dynamic updates. Essentially abandoned — last meaningful update years ago.
- **Verdict**: Not suitable for dynamic dev tool use. The immutable index model is a dealbreaker for file watching scenarios.

#### FlexSearch
- **Strengths**: Fastest raw query performance (50.9M ops/sec in benchmarks), multiple bundle tiers (light 4.5KB to full 16.3KB), worker thread support, context-based scoring, v0.8 persistent index support (IndexedDB, Redis, SQLite, etc.), memory-efficient.
- **Weaknesses**: Documentation is fragmented and hard to follow. TypeScript support is only 75%. Export/import API is non-standard (not plain JSON). The API surface is large and the codebase is complex. Community reports of bugs in newer versions.
- **Verdict**: Most performant option but highest integration risk due to documentation quality and API complexity. The persistent index feature (v0.8) is interesting but overlaps with our server-side SQLite FTS5 approach.

#### MiniSearch (RECOMMENDED for client-side)
- **Strengths**: Tiny (~5KB), native TypeScript, clean API, fuzzy + prefix + auto-suggest built-in, dynamic add/remove, JSON serialization, memory-efficient (designed for mobile), actively maintained, used in VitePress (proof of production quality in a documentation search context very similar to ours).
- **Weaknesses**: No built-in stemming (must configure manually), all data must fit in memory, not suitable for very large datasets (100K+ documents).
- **Verdict**: Best fit for client-side use in the Dev Toolkit. Perfect for filtering file trees, searching within loaded JSON data, and providing instant search suggestions. The VitePress precedent directly validates this use case.

#### Fuse.js
- **Strengths**: Most popular (6.9M weekly downloads), simple API, excellent fuzzy matching via Bitap algorithm, weighted multi-field search, no index to build.
- **Weaknesses**: No inverted index — scans all documents on every query. Performance degrades rapidly with dataset size. O(n) per query makes it unsuitable for anything beyond small lists (<1000 items). No stemming, no prefix search.
- **Verdict**: Not suitable as a primary search library. Could be useful for tiny fuzzy-match scenarios (e.g., command palette autocomplete) but not for file search.

#### Pagefind
- **Strengths**: WASM-powered, extremely efficient bandwidth (lazy-loads index chunks), excellent for static content, Node.js API for programmatic indexing (`addCustomRecord` supports non-HTML content), used by Astro/Hugo.
- **Weaknesses**: Designed for static sites — requires a build step to generate the index. No dynamic add/remove at runtime. The WASM bundle (~100KB) is heavier than pure JS libraries. Integration with a dynamic dev tool would require re-running the indexer on file changes and reloading the WASM index.
- **Verdict**: Interesting technology but poor fit for a dynamic dev tool. The build-then-search model conflicts with our need for real-time file change tracking. Would add unnecessary complexity versus server-side FTS5.

### 2.3 Client-Side Recommendation

**Use MiniSearch** for all client-side search needs:
- File tree filtering in the Markdown Browser
- In-memory search within loaded JSON data in jtbl
- Auto-suggest / command palette search
- Quick-filter for agent definitions in Agent Builder

MiniSearch handles all of these well within its sweet spot (hundreds to low thousands of items in memory). For full-text search across all files, delegate to the server (SQLite FTS5).

---

## 3. Server-Side Search Solutions

### 3.1 Comparison Table

| Criterion | SQLite FTS5 | Tantivy (Rust) / tantivy-py | Whoosh (Python) | Bleve (Go) |
|---|---|---|---|---|
| **Language** | C (SQLite extension) | Rust (Python bindings) | Pure Python | Go |
| **Additional deps** | None (built into Python 3.12) | tantivy-py wheel (~5MB) | whoosh-reloaded pip | Go binary |
| **Ranking** | BM25 (built-in, column weights) | BM25, custom scorers | BM25F | BM25 |
| **Snippet/Highlight** | Built-in (snippet(), highlight()) | Built-in | Built-in | Built-in |
| **Tokenizers** | unicode61, porter, ascii, trigram | Standard, CJK, custom | Analyzers, filters | Standard, CJK |
| **Stemming** | Porter stemmer (wraps tokenizer) | Snowball stemmers | Snowball stemmers | Snowball stemmers |
| **Incremental updates** | INSERT/DELETE/UPDATE per row | Add/delete per doc | Add/delete per doc | Add/delete per doc |
| **Prefix search** | Configurable prefix indexes | Native | Native | Native |
| **Persistence** | SQLite database file | Directory of index files | Directory of index files | Directory of index files |
| **Query latency (1K docs)** | <1ms | <1ms | ~5-10ms | <1ms |
| **Query latency (100K docs)** | ~1-10ms | <1ms | ~50-100ms | ~1-5ms |
| **Index size** | ~45% of source data (detail=full) | ~30-40% of source data | ~40-50% of source data | ~30-40% of source data |
| **Maintenance status** | Core SQLite (perpetual) | Active (Quickwit) | Abandoned (fork exists) | Active |
| **Already in Claudio image** | Yes (Python 3.12 sqlite3) | No | No | No |

### 3.2 Detailed Analysis

#### SQLite FTS5 (RECOMMENDED)

**Why FTS5 is the clear winner for this project:**

1. **Zero additional dependencies**: Python 3.12 in the Claudio base image ships with sqlite3 that has FTS5 enabled (confirmed: SQLite 3.45.1 with ENABLE_FTS5). No pip install, no binary wheel, no compilation.

2. **Unified data layer**: SQLite can serve as the Dev Toolkit's metadata store AND search index in a single file. File metadata (path, mtime, size, type), search index, and application state all live in one `.db` file. This simplifies backup, reset, and migration.

3. **FastAPI integration is natural**: Python's `sqlite3` module is synchronous, but for a local dev tool serving a single user, this is fine. Queries complete in <10ms. If needed, wrap in `run_in_executor` for async compatibility.

4. **Built-in ranking and highlighting**:
   - `bm25()` with per-column weights (e.g., weight title 10x, headings 5x, body 1x)
   - `snippet()` returns contextual fragments with match markers
   - `highlight()` wraps matches in configurable HTML tags

5. **External content tables** for space efficiency: The FTS5 index can reference an external content table, storing only the inverted index (not the full text). Since we have the actual files on disk, we do not need to duplicate content in SQLite.

6. **Incremental updates are trivial**: INSERT/DELETE on FTS5 tables work like regular SQL. When a file changes, DELETE the old row and INSERT the new content. The auto-merge system handles index optimization in the background.

7. **Prefix search** can be configured at table creation time (`prefix='2 3'`) for instant-feeling typeahead queries.

8. **Content-sync via triggers or application code**: External content FTS5 tables can be kept in sync with triggers on the source table, or managed directly by application code on file change events.

**FTS5 Schema Design for Dev Toolkit:**

```sql
-- File metadata (source of truth for paths, mtimes)
CREATE TABLE files (
    id INTEGER PRIMARY KEY,
    path TEXT UNIQUE NOT NULL,
    type TEXT NOT NULL,           -- 'markdown', 'json', 'agent_def', etc.
    mtime REAL NOT NULL,
    size INTEGER NOT NULL,
    tool TEXT NOT NULL             -- 'markdown_browser', 'jtbl', 'agent_builder'
);

-- Full-text search index (external content, referencing files table)
CREATE VIRTUAL TABLE files_fts USING fts5(
    title,                        -- extracted heading or filename
    headings,                     -- all headings concatenated
    body,                         -- full text content
    front_matter,                 -- YAML front matter values
    content='files',
    content_rowid='id',
    tokenize='porter unicode61',
    prefix='2 3'
);

-- Query with ranking and snippets
SELECT
    f.path,
    f.type,
    bm25(files_fts, 10.0, 5.0, 1.0, 3.0) AS score,
    snippet(files_fts, 2, '<mark>', '</mark>', '...', 32) AS context
FROM files_fts
JOIN files f ON f.id = files_fts.rowid
WHERE files_fts MATCH ?
ORDER BY score
LIMIT 20;
```

**Performance expectations for the Dev Toolkit use case:**
- Typical workspace: 50–500 markdown files, 10–50 agent definitions, varying JSON files
- Even at 10,000 files, FTS5 queries return in <5ms on modern hardware
- Index size: ~45% of source text (with `detail=full`), can be reduced to ~20% with `detail=column`
- Indexing speed: thousands of documents per second

#### Tantivy / tantivy-py

- **Strengths**: Lucene-level performance (2x faster than Lucene in benchmarks), sophisticated ranking, excellent for large-scale search.
- **Weaknesses**: Adds a binary dependency (Rust wheels). Overkill for the scale of this project (hundreds of files, not millions). Separate index directory to manage alongside the SQLite metadata store. Being adopted by Turso as a replacement for FTS5 in cloud-scale scenarios — not our use case.
- **Verdict**: Would be the right choice if we were building a search service for millions of documents. For a local dev tool with <10K files, it adds complexity without meaningful benefit over FTS5.

#### Whoosh / Whoosh-Reloaded

- **Strengths**: Pure Python, easy API, good for prototyping.
- **Weaknesses**: Original project abandoned. Fork (whoosh-reloaded) exists but uncertain long-term maintenance. Significantly slower than FTS5 (5-10x for queries, worse for indexing). Separate index directory.
- **Verdict**: No reason to choose this over FTS5, which is faster, built-in, and maintained as part of SQLite core.

#### Bleve (Go)

- **Strengths**: Strong Go library for search.
- **Weaknesses**: Requires Go binary. No Python bindings. The Dev Toolkit is Python + Node, not Go.
- **Verdict**: Not applicable to the current stack.

### 3.3 Server-Side Recommendation

**Use SQLite FTS5** as the single server-side search solution. It covers all use cases with zero additional dependencies.

---

## 4. Indexing Strategy

### 4.1 Recommended: Background Incremental with Startup Catch-Up

The indexing strategy should combine startup scanning with background file watching:

```
┌─────────────────────────────────────────────────┐
│ Dev Toolkit Server Starts                        │
│                                                  │
│  1. Open/create SQLite DB with FTS5 tables       │
│  2. Walk configured directories                  │
│  3. Compare file mtimes vs DB records            │
│  4. Batch-index new/changed files                │
│  5. Remove deleted files from index              │
│  6. Start file watcher for ongoing changes       │
│                                                  │
│  Ongoing:                                        │
│  - File change → debounce 500ms → re-index file  │
│  - File delete → remove from index               │
│  - File create → index new file                  │
│  - Periodic optimize (merge FTS5 b-trees)        │
└─────────────────────────────────────────────────┘
```

### 4.2 File Watching

**Recommended library: `watchfiles`** (Python)

- Written in Rust (via the `notify` crate), provides async `awatch()` coroutine
- Works natively with FastAPI's asyncio event loop
- Handles Linux inotify, macOS FSEvents, Windows ReadDirectoryChanges
- Previously named `watchgod`, maintained by Samuel Colvin (pydantic author)
- Already works inside Docker containers with volume mounts (the `/workspace` bind mount)

**Alternative: `watchdog`** (Python, pure Python fallback, larger community, slightly more mature but heavier)

**Implementation pattern:**

```python
import watchfiles
from pathlib import Path

async def watch_and_index(root: Path, db: sqlite3.Connection):
    """Background task: watch for file changes and update FTS5 index."""
    async for changes in watchfiles.awatch(
        root,
        watch_filter=watchfiles.DefaultFilter(
            allowed_extensions=['.md', '.json', '.yaml', '.yml']
        ),
    ):
        for change_type, path in changes:
            if change_type in (watchfiles.Change.added, watchfiles.Change.modified):
                index_file(db, path)
            elif change_type == watchfiles.Change.deleted:
                remove_from_index(db, path)
```

### 4.3 Startup Indexing Performance

For a typical workspace with 500 markdown files averaging 5KB each:
- **File walking**: ~10ms (os.walk)
- **mtime comparison**: ~5ms (SELECT from files table)
- **Content reading**: ~50ms (reading only changed files)
- **FTS5 indexing**: ~100ms (INSERT into FTS5 table)
- **Total cold start (first run)**: ~200ms
- **Warm start (no changes)**: ~20ms

This is well within the "sub-second startup" requirement from Issue #55.

### 4.4 Index Persistence

The SQLite database file (containing both metadata and FTS5 index) should live at a known location:

```
~/.local/share/claudio-dev-toolkit/search.db
```

Or within the project:

```
/workspace/.dev-toolkit/search.db
```

The `.dev-toolkit/` directory should be added to `.gitignore`. The index can be safely deleted and rebuilt from source files at any time.

---

## 5. Search Highlighting in Rendered Markdown

### 5.1 Server-Side Highlighting (FTS5)

FTS5's `highlight()` and `snippet()` functions return plain text with configurable markers:

```sql
SELECT highlight(files_fts, 2, '<mark>', '</mark>') AS highlighted_body
FROM files_fts WHERE files_fts MATCH 'search term';
```

This works well for returning search result previews in API responses.

### 5.2 Client-Side Highlighting (in rendered Markdown)

For highlighting search terms within the full rendered markdown document (after the user navigates to a search result), use **mark.js**:

- ~8KB gzipped, zero dependencies
- Works on DOM ranges — does not modify source markdown
- `accuracy: "exactly"` for whole-word matching, `accuracy: "partially"` for substring
- Can be applied after React renders the markdown content
- Does not interfere with React's virtual DOM (operates on actual DOM nodes)

**Alternative: CSS Custom Highlight API** — a browser-native API that highlights without DOM modification. Not yet supported in Firefox, so mark.js is the safer choice for now.

### 5.3 Recommended Flow

```
User types search query
  → Frontend sends query to FastAPI /search endpoint
  → FastAPI queries SQLite FTS5 with bm25() ranking
  → Returns results with snippet() previews
  → User clicks a result
  → Frontend loads and renders the full markdown file
  → Frontend applies mark.js to highlight the search terms in the rendered HTML
```

---

## 6. Cross-Tool Unified Search Architecture

### 6.1 Design

All Dev Toolkit tools share a single SQLite FTS5 index, differentiated by the `tool` and `type` columns:

```
┌──────────────────────────────────────────────────┐
│               Unified Search Service              │
│                                                   │
│  SQLite DB: search.db                             │
│  ┌───────────┐  ┌───────────┐  ┌──────────────┐  │
│  │ files_fts │  │  files    │  │  search_log  │  │
│  │ (FTS5)    │  │ (metadata)│  │  (optional)  │  │
│  └───────────┘  └───────────┘  └──────────────┘  │
│                                                   │
│  Indexers (per tool):                             │
│  ├─ markdown_indexer: .md files → extract         │
│  │  title, headings, body, front_matter           │
│  ├─ agent_indexer: agent defs → extract           │
│  │  name, description, commands, hooks            │
│  └─ json_indexer: .json files → extract           │
│     keys, values, structure                       │
│                                                   │
│  File Watcher:                                    │
│  watchfiles → debounce → route to correct indexer │
│                                                   │
│  API:                                             │
│  GET /api/search?q=...&tool=...&type=...          │
│  GET /api/search/suggest?q=...                    │
└──────────────────────────────────────────────────┘
```

### 6.2 Per-Tool Indexing

Each tool has its own indexer that knows how to extract searchable fields from its file types:

**Markdown Browser (#57)**:
- Parse front matter (YAML) → `front_matter` field
- Extract first H1 or filename → `title` field
- Extract all headings → `headings` field
- Full text content (minus front matter) → `body` field
- Column weights: title=10, headings=5, body=1, front_matter=3

**Agent Builder (#60)**:
- Parse agent YAML/JSON definitions
- Agent name → `title` field
- Description → `headings` field
- Commands, hooks, settings → `body` field

**jtbl (#58)**:
- This is different — JSON data is typically loaded on demand, not pre-indexed
- Use MiniSearch client-side for filtering loaded JSON tables
- If persistent JSON file search is needed, index JSON file keys/values in FTS5

### 6.3 Search API Design

```python
# FastAPI search endpoint
@router.get("/api/search")
async def search(
    q: str,
    tool: str | None = None,    # Filter by tool: 'markdown_browser', 'agent_builder'
    type: str | None = None,     # Filter by type: 'markdown', 'json', 'agent_def'
    limit: int = 20,
    offset: int = 0,
):
    """Unified search across all indexed files."""
    # Build FTS5 MATCH query
    # Filter by tool/type if specified
    # Return ranked results with snippets
    ...

@router.get("/api/search/suggest")
async def suggest(q: str, limit: int = 5):
    """Auto-complete suggestions based on prefix search."""
    # Use FTS5 prefix query: q + '*'
    # Return top suggestions
    ...
```

### 6.4 Global Search UX

The frontend should provide a global search bar (Cmd+K / Ctrl+K) that:
1. Sends the query to `/api/search` (all tools)
2. Groups results by tool
3. Shows snippet previews with highlighted matches
4. Clicking a result navigates to the appropriate tool with that file open

This is similar to VS Code's Cmd+P / Ctrl+P but scoped to the Dev Toolkit's indexed content.

---

## 7. Key Design Decisions

### 7.1 Fuzzy Search vs Exact Match

**Default: Prefix match with optional fuzzy**

- FTS5 prefix queries (`search*`) provide the best balance of precision and recall for typeahead
- For the search bar, use prefix matching by default (append `*` to the last term)
- For explicit fuzzy search, use MiniSearch client-side (it has native fuzzy support)
- FTS5's trigram tokenizer can provide substring matching if needed, but at the cost of larger index size

**Recommended default query transformation:**
```python
def prepare_query(raw: str) -> str:
    """Transform user input into FTS5 query."""
    terms = raw.strip().split()
    if not terms:
        return ""
    # Prefix-match the last term for typeahead feel
    terms[-1] = terms[-1] + "*"
    return " ".join(terms)
```

### 7.2 Ranking Across Different File Types

Use BM25 column weights to normalize relevance across file types:
- Title matches always rank highest (weight=10)
- Heading matches rank high (weight=5)
- Front matter / metadata matches are moderate (weight=3)
- Body text matches are base weight (weight=1)

Since all file types map to the same FTS5 columns (title, headings, body, front_matter), BM25 ranking works uniformly. If tool-specific boosting is needed, apply a multiplier in application code.

### 7.3 Can We Use SQLite FTS5 as a Unified Index for Everything?

**Yes.** This is the recommended approach. Key advantages:
- Single database file for all search data
- Unified query API across all tools
- Consistent ranking and highlighting
- Atomic updates (SQLite transactions)
- Easy to debug (sqlite3 CLI tool)
- Easy to reset (delete the .db file)

The only exception is jtbl's in-memory JSON filtering, which is better served by MiniSearch on the client side since the data is already loaded in the browser.

---

## 8. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| FTS5 not compiled into some Python distributions | Low (confirmed in Claudio image) | High | Check at startup; fall back to FTS4 or error clearly |
| File watcher misses changes in Docker volume mounts | Medium | Medium | Periodic rescan (every 60s) as fallback; inotify works with volume mounts in practice |
| Index corruption on crash | Low | Low | SQLite WAL mode + periodic OPTIMIZE; index is always rebuildable from source files |
| Large workspaces (10K+ files) slow startup | Low | Medium | Incremental indexing (only re-index changed files); parallelize with asyncio |
| MiniSearch memory pressure with large client-side datasets | Low | Low | Paginate and lazy-load; only index visible/loaded data client-side |

---

## 9. Summary: Recommended Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Dev Toolkit                           │
│                                                              │
│  ┌─────────────────────────┐  ┌──────────────────────────┐  │
│  │  FastAPI Backend         │  │  React Frontend           │  │
│  │                          │  │                           │  │
│  │  SQLite FTS5             │  │  MiniSearch               │  │
│  │  ├─ Unified search index │  │  ├─ File tree filtering   │  │
│  │  ├─ BM25 ranking         │  │  ├─ JSON data filtering   │  │
│  │  ├─ Snippet extraction   │  │  ├─ Auto-suggest          │  │
│  │  └─ Highlight support    │  │  └─ Command palette       │  │
│  │                          │  │                           │  │
│  │  watchfiles              │  │  mark.js                  │  │
│  │  └─ File change events   │  │  └─ Highlight in rendered │  │
│  │     → incremental index  │  │     markdown content      │  │
│  └─────────────────────────┘  └──────────────────────────┘  │
│                                                              │
│  Dependencies added:                                         │
│  ├─ Server: watchfiles (pip) — only new dependency           │
│  ├─ Client: minisearch (npm, ~5KB)                           │
│  └─ Client: mark.js (npm, ~8KB)                              │
│                                                              │
│  Zero new deps for search itself — FTS5 is built into Python │
└─────────────────────────────────────────────────────────────┘
```

### Key Properties

1. **Minimal dependencies**: SQLite FTS5 is built-in. Only `watchfiles` is new on the server side.
2. **Single source of truth**: One SQLite file holds all search data and metadata.
3. **Instant queries**: FTS5 + BM25 returns ranked, highlighted results in <10ms.
4. **Incremental updates**: File changes are detected and indexed within 500ms.
5. **Cross-tool search**: All tools share one index, queryable via a single API.
6. **Client-side responsiveness**: MiniSearch handles instant UI-layer filtering.
7. **Rebuildable**: The index can always be deleted and rebuilt from source files.

---

## Sources

### Client-Side Libraries
- [Lunr.js GitHub](https://github.com/olivernn/lunr.js) — Lunr.js large index issue #222
- [FlexSearch GitHub](https://github.com/nextapps-de/flexsearch) — benchmarks, persistent index docs
- [MiniSearch GitHub](https://github.com/lucaong/minisearch) — API docs, features
- [Fuse.js](https://www.fusejs.io/) — fuzzy search documentation
- [Pagefind](https://pagefind.app/) — static search, Node.js API
- [npm-compare: JS search libraries](https://npm-compare.com/elasticlunr,flexsearch,fuse.js,minisearch) — download stats, comparison
- [npm trends: flexsearch vs fuse.js vs lunr](https://npmtrends.com/flexsearch-vs-fuse.js-vs-lunr) — popularity trends
- [Top 6 JS Search Libraries](https://byby.dev/js-search-libraries) — overview

### Server-Side / SQLite FTS5
- [SQLite FTS5 Official Documentation](https://www.sqlite.org/fts5.html) — comprehensive reference
- [FTS5 in Practice (TheLinuxCode)](https://thelinuxcode.com/sqlite-full-text-search-fts5-in-practice-fast-search-ranking-and-real-world-patterns/) — real-world patterns
- [SQLite FTS5 + FastAPI (Stackademic)](https://blog.stackademic.com/instant-semantic-search-api-sqlite-fts5-python-fastapi-3298c6776935) — FastAPI integration
- [Using SQLite FTS with Python (Charles Leifer)](https://charlesleifer.com/blog/using-sqlite-full-text-search-with-python/) — Python patterns
- [Simon Willison on Full-Text Search](https://simonwillison.net/tags/full-text-search/) — search relevance algorithms
- [FTS Benchmark (GitHub)](https://github.com/VADOSWARE/fts-benchmark) — comparison framework

### File Watching
- [watchfiles (GitHub)](https://github.com/samuelcolvin/watchfiles) — Rust-backed Python file watcher
- [chokidar (GitHub)](https://github.com/paulmillr/chokidar) — Node.js file watching

### Search Highlighting
- [mark.js](https://markjs.io/) — JavaScript keyword highlighting
- [CSS Custom Highlight API](https://marmelab.com/blog/2024/04/23/highlight-search-query.html) — browser-native highlighting
- [Whoosh-Reloaded (GitHub)](https://github.com/Sygil-Dev/whoosh-reloaded) — maintained Whoosh fork
- [Tantivy (GitHub)](https://github.com/quickwit-oss/tantivy) — Rust full-text search engine

### Other
- [Pagefind Node.js API](https://pagefind.app/docs/node-api/) — programmatic indexing
- [VitePress Search](https://vitepress.dev/reference/default-theme-search) — MiniSearch integration example
