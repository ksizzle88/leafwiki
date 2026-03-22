# JSON Table Tooling & Data Exploration Landscape

Research for jtbl 2.0 (Issue #58) — JSON Exploration & Table Tool

---

## 1. Existing CLI JSON Tools — Comparison

### 1.1 jtbl (Original)

- **What it is**: CLI tool that converts JSON/JSON Lines to terminal tables. Companion to `jc`.
- **Strengths**: Dead-simple pipe interface (`cat data.json | jq '.items' | jtbl`). Handles flat JSON arrays well.
- **Weaknesses**: Only works with already-flat data. No query language, no column selection, no filtering. Data must be rectangular before it reaches jtbl.
- **Relevance to jtbl 2.0**: jtbl 2.0 is a fundamentally different tool. The original jtbl is a *renderer* for pre-processed data. jtbl 2.0 is a *query + render* workbench. They share the name but not the architecture.
- **GitHub**: https://github.com/kellyjonbrazil/jtbl

### 1.2 jq

- **What it is**: The standard JSON processor. C-based, fast, streaming, powerful expression language.
- **Strengths**: Universal install base. Handles arbitrarily complex transformations. Streaming mode for large files. Excellent performance (C implementation).
- **Weaknesses**: Steep learning curve. Output is raw JSON — no table formatting. Composing complex pipelines requires deep jq knowledge.
- **Relevance to jtbl 2.0**: jq is the **query engine** for jtbl 2.0, not a competitor. jtbl 2.0 shells out to `jq` for row selection and column expressions. The design doc explicitly chose subprocess over WASM/native for correctness and simplicity.

### 1.3 jless

- **What it is**: Terminal JSON viewer written in Rust. TUI with vim-like navigation.
- **Strengths**: Excellent for exploring unknown JSON structure. Syntax highlighting, collapse/expand, regex search. Very fast rendering.
- **Weaknesses**: Read-only viewer — no transformation, no table output, no export. macOS/Linux only.
- **Relevance to jtbl 2.0**: jless solves the "what is in this JSON?" problem that jtbl 2.0's Tree Explorer tab also addresses. However, jless cannot project JSON into tables. The two tools are complementary: use jless to understand structure, jtbl 2.0 to extract and present it.
- **GitHub**: https://github.com/PaulJuliusMartinez/jless

### 1.4 fx

- **What it is**: Terminal JSON viewer & processor written in Go. Interactive TUI with JavaScript expression support.
- **Strengths**: Interactive exploration. JavaScript-based transformation (familiar syntax). Streaming support. Mouse support. Auto-completion. Single binary distribution.
- **Weaknesses**: JavaScript expressions, not jq — different ecosystem. No table output format. More of a viewer than an analytical tool.
- **Relevance to jtbl 2.0**: fx's interactive exploration model influenced the Tree Explorer concept, but fx uses JavaScript where jtbl 2.0 uses jq. They target different workflows: fx for ad-hoc terminal exploration, jtbl 2.0 for structured table presentation.
- **Website**: https://fx.wtf/

### 1.5 gron

- **What it is**: Flattens JSON into discrete assignment statements for grep.
- **Strengths**: Brilliant simplicity — makes JSON greppable with standard Unix tools. Reversible (`--ungron`). Supports HTTP fetching. Streaming mode.
- **Weaknesses**: Output is assignment format, not table. No filtering or transformation beyond what grep provides. Not suitable for structured analysis.
- **Relevance to jtbl 2.0**: gron solves a different problem (discovery via grep). jtbl 2.0's jq preview sidebar serves a similar discovery role but with richer structure awareness.
- **GitHub**: https://github.com/tomnomnom/gron

### 1.6 Miller (mlr)

- **What it is**: Like awk/sed/sort for name-indexed data (CSV, TSV, JSON, YAML). Written in Go.
- **Strengths**: Streaming — operates on single records, handles files larger than RAM. Multi-format input/output. DSL with `put` verb for expressions. Zero runtime dependencies. Extremely fast.
- **Weaknesses**: Designed for already-rectangular data. JSON support assumes records are flat or need flattening first. No interactive UI. Learning curve for the DSL.
- **Relevance to jtbl 2.0**: Miller is the closest CLI competitor in the "structured data processing" space. However, Miller assumes data is already record-shaped. jtbl 2.0's key differentiator is the jq-based row selection that extracts records from arbitrary nested JSON before processing.
- **GitHub**: https://github.com/johnkerl/miller

### 1.7 qsv (fork of xsv)

- **What it is**: Blazing-fast CSV data-wrangling toolkit written in Rust. 50+ commands.
- **Strengths**: Extremely fast (Rust, indexing, multi-threading). JSON-to-CSV conversion. SQL-like operations. Luau scripting. 520MB file indexes in 466ms.
- **Weaknesses**: CSV-centric — JSON is an import format, not a first-class citizen. No interactive UI. No jq integration.
- **Relevance to jtbl 2.0**: qsv's CSV export could complement jtbl 2.0's `--fmt csv` output. Not a competitor — different paradigm (CSV-first vs JSON-first).
- **GitHub**: https://github.com/dathere/qsv

### 1.8 DuckDB CLI

- **What it is**: Embeddable SQL OLAP database with CLI. Queries JSON/CSV/Parquet directly via SQL.
- **Strengths**: SQL is universally known. Columnar storage + vectorized execution = extreme performance. Handles multi-GB files. Type inference from JSON. Cross-format joins.
- **Weaknesses**: SQL is verbose for simple JSON extraction. Default 16MB JSON document limit (configurable). Heavier dependency than jq. Not designed for interactive exploration.
- **Relevance to jtbl 2.0**: DuckDB is a potential **alternative query engine** to jq. Blog posts like "DuckDB as the New jq" show growing adoption. For jtbl 2.0, DuckDB could serve as a power-user backend for SQL-oriented workflows, but jq should remain the primary engine (lighter, more JSON-native). DuckDB is a strong post-MVP consideration.
- **Docs**: https://duckdb.org/docs/stable/data/json/json_type

### 1.9 jnv

- **What it is**: Interactive JSON filter using jq. TUI with live preview. Written in Rust.
- **Strengths**: Embedded jq (via jaq) — no external jq binary needed. Filter auto-completion. Live preview of jq results. Beautiful TUI.
- **Weaknesses**: No table output. No column projection. No export formats. Read-only exploration.
- **Relevance to jtbl 2.0**: jnv is the closest tool to jtbl 2.0's "jq preview sidebar" concept. The key difference is jtbl 2.0 goes further — it projects the jq result into a table with columns, sort, filter, and export. jnv stops at showing the raw jq result.
- **GitHub**: https://github.com/ynqa/jnv

### Competitive Landscape Summary

| Tool | Query Language | Table Output | Web UI | Interactive | JSON-First |
|------|--------------|-------------|--------|-------------|------------|
| **jtbl (orig)** | None (pipe) | Yes (terminal) | No | No | Yes |
| **jq** | jq | No (raw JSON) | No | No | Yes |
| **jless** | Search only | No | No | Yes (TUI) | Yes |
| **fx** | JavaScript | No | No | Yes (TUI) | Yes |
| **gron** | grep | No | No | No | Yes |
| **Miller** | DSL | Yes (multi-fmt) | No | No | Multi-format |
| **qsv** | Commands/Luau | Yes (CSV) | No | No | CSV-first |
| **DuckDB** | SQL | Yes (terminal) | No | Yes (CLI) | Multi-format |
| **jnv** | jq | No | No | Yes (TUI) | Yes |
| **jtbl 2.0** | jq | Yes (multi-fmt) | Yes (Streamlit) | Yes (web) | Yes |

**jtbl 2.0's unique position**: The only tool combining jq-based row selection + table projection + web UI + CLI in one package. No existing tool covers this full workflow.

---

## 2. Web-Based Data Explorers — Comparison

### 2.1 Datasette

- **What it is**: Web UI for exploring and publishing structured data (SQLite-backed). By Simon Willison.
- **Strengths**: Beautiful web UI for data exploration. Every row has a URL. SQL query interface. JSON API. Plugin ecosystem. Faceted search.
- **Weaknesses**: SQLite-centric — JSON must be imported first. Not designed for ad-hoc JSON exploration. Server-based (not single-file).
- **Relevance to jtbl 2.0**: Datasette's "explore first, query second" philosophy aligns with jtbl 2.0's Tree Explorer. However, Datasette requires importing data into SQLite. jtbl 2.0 works directly on JSON files with zero import step.

### 2.2 Others (Superset, Retool, Evidence.dev, Observable)

These are enterprise/team data exploration platforms. They are not relevant competitors — jtbl 2.0 is a **developer tool** for ad-hoc JSON inspection, not a dashboarding or reporting platform. Including them in the competitive analysis would be misleading.

---

## 3. Recommended Libraries for Each Layer

### 3.1 CLI Data Processing

**Recommendation: pandas (MVP) with polars as post-MVP upgrade path**

| Library | Performance | JSON Support | DataFrame Ops | Bundle Size | Ecosystem |
|---------|------------|-------------|--------------|------------|-----------|
| **pandas** | Good (<1M rows) | `json_normalize()` | Complete | ~30MB | Massive |
| **polars** | 3-10x faster | Native JSON read | Complete | ~15MB | Growing |
| **tabulate** | Fast | N/A (formatter) | N/A | Tiny | Mature |
| **rich** | Moderate | N/A (formatter) | N/A | ~2MB | Growing |

**Rationale**: The design doc already chose pandas + tabulate. This is correct for MVP:
- pandas is the design doc's choice and already proven in the jtable prototype
- tabulate is lightweight and handles markdown/grid/plain formats well
- polars is a post-MVP upgrade if performance on large datasets (10K+ rows) becomes an issue — it's 3-10x faster due to Rust backend, columnar storage, and multi-threading
- rich is unnecessary — tabulate + pandas cover all CLI formatting needs

### 3.2 jq Execution Strategy

**Recommendation: subprocess to `jq` binary (primary) + dot-path fallback (no jq) + pyjq as optional post-MVP enhancement**

| Approach | Performance | Correctness | Install Burden | Complexity |
|----------|-----------|------------|---------------|-----------|
| **subprocess to jq** | Excellent (C) | Perfect (it IS jq) | Requires jq binary | Low |
| **pyjq** (C binding) | Good | Good (jq 2.5) | Pip install, C compile | Medium |
| **jq PyPI** (C binding) | Good | Good (jq 1.8.1) | Pip install, wheels | Medium |
| **dot-path fallback** | N/A | Limited (no expressions) | None | Low |

**Performance analysis**:
- jq subprocess: Overhead is ~5-10ms per invocation (process spawn). For single index queries, negligible. For per-row column evaluation (N rows x M columns), this becomes O(N*M) subprocess calls.
- **Key optimization**: Batch column evaluation into a single jq call per row: `jq '{col1: (.expr1), col2: (.expr2)}'`. This reduces to O(N) calls.
- **Further optimization**: For the index query + where filter, compose into one jq call: `jq '[.items[] | select(.active)]'`. This is a single subprocess call regardless of row count.
- For MVP, subprocess is the right choice. If profiling shows subprocess overhead is a bottleneck for large datasets (unlikely for <10K rows), add pyjq as an optional backend.

**Fallback strategy when jq unavailable**:
1. Check for `jq` binary on PATH at startup
2. If missing, warn and fall back to dot-path walker (`extract_path()`)
3. Dot-path covers `.foo.bar[0]` patterns but not `select()`, `map()`, or computed expressions
4. Clear error message: "Install jq for full query support"

### 3.3 Web Table Components (if migrating from Streamlit)

**Recommendation for Streamlit MVP: `st.dataframe()` (built-in)**
**Recommendation for post-MVP React migration: TanStack Table + react-window**

| Component | Virtual Scroll | Sort/Filter | Row Click | Bundle | License |
|-----------|---------------|------------|----------|--------|---------|
| **st.dataframe()** | Yes (built-in) | Sort (auto) | No (limited) | N/A (Streamlit) | Apache 2.0 |
| **AG Grid Community** | Yes (100K+ rows) | Yes | Yes | ~200KB | MIT |
| **TanStack Table** | With react-window | Headless (DIY) | Headless (DIY) | ~30KB total | MIT |
| **Tabulator** | Yes | Yes | Yes | ~100KB | MIT |

**For Streamlit MVP**: Use `st.dataframe()`. It handles virtual scrolling natively, sorts columns automatically, and requires zero configuration. Limitations: no row click events (needed for row inspector), no column resize. The row inspector can be implemented via `st.selectbox` or a workaround.

**For post-MVP (if React migration happens)**: TanStack Table + react-window is the right choice. It's headless (full UI control), lightweight (30KB), and handles 10K+ rows with virtualization. AG Grid is overkill for this use case — jtbl 2.0 doesn't need enterprise features like cell editing, row grouping, or server-side models.

**Streamlit large data limits**: `st.dataframe()` disables column sorting above ~150K rows. For jtbl 2.0's target of "explore JSON files," this is unlikely to be a bottleneck. If users need 100K+ row analysis, that's a DuckDB use case.

### 3.4 JSON Tree Components

**Recommendation for Streamlit MVP: Custom Streamlit component using `st.json()` + breadcrumb navigation**
**Recommendation for post-MVP React: react-json-view-lite**

| Component | Expand/Collapse | Edit | Performance | Bundle |
|-----------|----------------|------|------------|--------|
| **st.json()** | Yes (built-in) | No | Good | N/A |
| **react-json-view** | Yes | Yes | Moderate | ~50KB |
| **react-json-view-lite** | Yes | No | Excellent | ~5KB |
| **react-json-tree** | Yes | No | Good | ~15KB |

**For Streamlit MVP**: `st.json()` provides expandable JSON display natively. Combine with a text input for the jq path and breadcrumb display. This covers the Tree Explorer tab without custom components.

**For React migration**: react-json-view-lite is the best fit — tiny, fast, TypeScript, no dependencies. jtbl 2.0 doesn't need editing (react-json-view's main advantage), so the lighter component wins.

### 3.5 Code Editor for jq Queries

**Recommendation: streamlit-ace (already chosen in design doc)**

| Editor | Streamlit Integration | jq Highlighting | Bundle | Mobile |
|--------|----------------------|----------------|--------|--------|
| **streamlit-ace** | Native component | sh mode (close enough) | Small | Limited |
| **CodeMirror 6** | Custom component needed | Custom mode needed | ~300KB | Excellent |
| **Monaco** | Custom component needed | Custom mode needed | ~5-10MB | Poor |

**Rationale**: streamlit-ace is already the design doc's choice and works in the jtable prototype. Ace doesn't have a native jq mode, but `sh` highlighting is close enough (quotes, dots, pipes). Building a custom Streamlit component for CodeMirror 6 would delay MVP for minimal benefit. If the project migrates to React, CodeMirror 6 is the clear winner (modular, lightweight, excellent mobile support).

---

## 4. Performance Considerations for Large Datasets

### 4.1 What "large" means for jtbl 2.0

| Scale | Rows | File Size | Expected Performance |
|-------|------|-----------|---------------------|
| Small | <1K | <1MB | Instant (<100ms) |
| Medium | 1K-10K | 1-50MB | Fast (<1s) |
| Large | 10K-100K | 50-500MB | Acceptable (<5s) |
| Very Large | 100K+ | 500MB+ | Out of scope for MVP |

### 4.2 Bottleneck Analysis

1. **jq subprocess for index query**: Single call, jq handles large files efficiently (C, streaming). Not a bottleneck.
2. **jq subprocess for per-row column evaluation**: O(N) calls if batched per-row. At 10K rows, ~10K subprocess calls × ~5ms = ~50s. **This is the main bottleneck.**
3. **pandas DataFrame operations**: Sort, filter, limit on 10K rows is <100ms. Not a bottleneck.
4. **Streamlit rendering**: `st.dataframe()` uses virtual scrolling. 10K rows renders fine. 150K+ rows disables sorting.
5. **JSON serialization**: Python `json.dumps`/`json.loads` for subprocess I/O. At 10K rows of moderate size (~1KB each), ~10MB total. Fast enough.

### 4.3 Optimization Strategy

**For per-row column evaluation (the main bottleneck)**:

Option A: **Batch all rows into a single jq call** (recommended for MVP)
```bash
# Instead of N calls to: jq '{id: .id, name: .name}' <<< row_json
# One call: jq '[.[] | {id: .id, name: .name}]' <<< all_rows_json
```
This reduces N subprocess calls to 1. Performance: single jq call on 10K rows × 5 columns ≈ <1s.

Option B: **Use pyjq/jq Python binding** (post-MVP if needed)
Eliminates subprocess overhead entirely. ~10x faster for per-row evaluation.

Option C: **Use DuckDB for large datasets** (post-MVP)
SQL query on 100K+ rows is DuckDB's sweet spot.

### 4.4 Web UI Performance

- **Debounce**: Add 300ms debounce on command editor changes before re-running the pipeline
- **Caching**: Use `@st.cache_data` for file loading (already in prototype)
- **Pagination**: For result sets >10K rows, default to `--limit 1000` with option to increase
- **Lazy inspector**: Only render row inspector JSON when a row is actually clicked

---

## 5. Key Design Questions — Answers

### Q: How does jq subprocess performance compare to native Python JSON processing?

**A**: jq (C) is significantly faster than Python's `json` module for complex queries on large data. For simple path traversal on small data (<1K rows), the subprocess overhead (~5ms per call) can dominate. The solution is batching: compose jq expressions to process all rows in a single subprocess call. With batching, jq subprocess performance is excellent up to 100K+ rows.

### Q: What's the best jq fallback strategy when the binary isn't available?

**A**: The design doc's approach is correct:
1. Check `shutil.which('jq')` at startup
2. If missing, set a flag and warn
3. For simple paths (`.foo.bar[0]`), use `extract_path()` dot-walker
4. For complex expressions (`select()`, computed columns), fail with clear message pointing to jq install instructions
5. Do NOT attempt to implement a jq subset in Python — it will be incomplete and misleading

### Q: Can we use DuckDB as an alternative query engine?

**A**: Yes, DuckDB is a strong alternative for SQL-oriented users and large datasets. However, it should be a **post-MVP addition**, not a replacement for jq:
- jq is lighter (single binary, ~2MB vs DuckDB's ~50MB)
- jq is more JSON-native (designed for JSON, not tabular data)
- The design doc's entire query model (index expressions, column expressions, where/having) maps naturally to jq
- DuckDB makes sense as an opt-in backend: `--engine duckdb` flag that translates the query model to SQL
- Blog posts "DuckDB as the New jq" show demand for this, but the audiences are different (SQL-literate vs jq-literate)

### Q: What table component handles 10K+ rows without choking?

**A**: For Streamlit: `st.dataframe()` handles 10K+ rows natively via built-in virtualization. It only renders visible rows. Disables sorting at ~150K rows.

For React (post-MVP): AG Grid Community handles 100K+ rows with DOM virtualization. TanStack Table + react-window handles 10K-50K rows well. For jtbl 2.0's use case (JSON exploration, not enterprise dashboards), TanStack Table is sufficient and much lighter.

### Q: How to do virtual scrolling for large datasets?

**A**: Both Streamlit and AG Grid handle this automatically:
- **Streamlit**: `st.dataframe()` uses HTML canvas rendering with built-in virtualization. Only visible rows are drawn.
- **AG Grid**: DOM virtualization — renders only visible rows plus a configurable buffer (default 10 rows above/below viewport).
- **TanStack Table + react-window**: Manual setup but well-documented. `react-window`'s `FixedSizeList` renders only visible items.

The key insight: virtual scrolling is a solved problem in all recommended components. It does not require custom implementation.

---

## 6. Existing Prototype: jtable

The existing jtable prototype at `/workspace/mpulse/hxi-infra/analysis/jtable.py` validates the core concept. Key observations from the gap analysis (`jqtbl_vs_jtable.md`):

**What works well (keep)**:
- PEP 723 / `uv run` zero-install pattern
- Shared `parse_cli_args()` between CLI and Streamlit
- `@st.cache_data` for file loading
- Tab-based result display (Interactive, Fixed Width, Markdown, CSV)
- CLI command caption in web UI

**What needs replacement (jtbl 2.0)**:
- `extract_path()` dot-walker → jq subprocess engine
- Positional column args → `--col name expr` syntax
- Regex filter/exclude → jq `--where` / `--having`
- No inferred columns → auto-detect from top-level keys
- No row inspector → click row to see original JSON
- Silent failures → stage-aware error messages

---

## 7. Technology Stack Recommendation (Summary)

| Layer | MVP Choice | Post-MVP Upgrade | Rationale |
|-------|-----------|-----------------|-----------|
| Query engine | `jq` subprocess | + pyjq binding, + DuckDB opt-in | Correctness first, optimize later |
| Data processing | pandas | polars | pandas is proven, polars is faster |
| CLI table rendering | tabulate | (none needed) | Lightweight, multi-format |
| Web framework | Streamlit | React (if Streamlit blocks) | Fast iteration for MVP |
| Web table | `st.dataframe()` | TanStack Table + react-window | Built-in virtualization |
| Code editor | streamlit-ace | CodeMirror 6 | Already working in prototype |
| JSON tree | `st.json()` + custom nav | react-json-view-lite | Native Streamlit for MVP |
| Packaging | PEP 723 + `uv run` | (none needed) | Zero-install, proven pattern |
