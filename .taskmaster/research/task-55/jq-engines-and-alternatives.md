# jq Engines, Alternatives & Integration Strategy

Research for jtbl 2.0 (Issue #58) — jq integration, query language alternatives, fallback strategies, PEP 723, and Web UI editor considerations.

---

## 1. jq Integration Approaches

### 1.1 Subprocess to `jq` Binary (Recommended Primary)

**How it works**: Shell out to the `jq` binary via `subprocess.run()`, passing JSON on stdin and reading results from stdout.

```python
proc = subprocess.run(
    ["jq", "-c", expr],
    input=json.dumps(data),
    capture_output=True, text=True
)
```

**Pros**:
- Full jq language support (jq 1.8.1 has the complete expression language)
- Battle-tested correctness — jq is the reference implementation
- No C compilation required at install time
- Streaming support via `--stream` flag for large files
- Simple error handling: check `returncode`, read `stderr`

**Cons**:
- **Startup overhead**: jq 1.7+ fixed the accidentally-quadratic builtin binding that made jq 1.5/1.6 slow (~50ms startup on older versions; jq 1.7+ is much faster at ~5-10ms). However, spawning a subprocess per query still has OS-level overhead (fork/exec).
- **Serialization cost**: Data must be serialized to JSON string for stdin, then parsed back from stdout.
- **Availability**: jq must be installed separately. Not available by default on all systems (though common on Linux/macOS).

**Performance characteristics**:
- Small JSON (<1KB): subprocess overhead dominates (~5-15ms per call)
- Medium JSON (1MB): jq processing is fast, total ~20-50ms
- Large JSON (100MB+): jq excels here, especially with `--stream` flag
- Per-row column evaluation (N rows × M columns): spawns N×M subprocesses unless batched

**Optimization: Batch evaluation**. Instead of one subprocess per row per column, construct a single jq expression that evaluates all columns at once:

```python
# Instead of N*M subprocess calls:
# jq '.id' per row + jq '.name' per row + ...

# Single call that extracts all columns:
# jq '[.id, .name, .meta.team]' per row
# Or even better, for all rows at once:
# jq '[.[] | {id: .id, name: .name, team: .meta.team}]'
```

This reduces subprocess calls from N×M to 1-2 for the entire dataset.

### 1.2 Python Native Bindings: `jq` (PyPI package, jq.py)

**Package**: [`jq`](https://pypi.org/project/jq/) v1.11.0 (January 2026)
**Binds to**: jq 1.8.1 C library via Cython
**Repository**: https://github.com/mwilliamson/jq.py

**API**:
```python
import jq

# Compile once, run many times
program = jq.compile(".items[] | {id, name}")
results = program.input_value(data).all()

# One-shot convenience
jq.first(".name", {"name": "alice"})  # "alice"
jq.all(".[] + 1", [1, 2, 3])          # [2, 3, 4]

# With variables
program = jq.compile("$a + $b + .", args={"a": 100, "b": 20})
program.input_value(3).first()  # 123
```

**Pros**:
- No subprocess overhead — direct C library calls via Cython
- Compile-once, run-many pattern (ideal for per-row column evaluation)
- Pre-built wheels for Linux and macOS (Python 3.8-3.14, CPython and PyPy)
- Full jq 1.8.1 language support
- BSD-2-Clause license

**Cons**:
- Adds a compiled dependency (C extension) — heavier than pure Python
- No Windows wheels (must compile from source on Windows)
- Adds ~5MB to the dependency footprint
- Cannot be used in browser/WebAssembly context

**Performance**: Eliminates subprocess fork/exec overhead entirely. For per-row column evaluation (the hot path in jtbl), this is significantly faster:
- Compiled jq program reuse avoids re-parsing expressions
- No JSON serialization/deserialization through pipes
- Estimated 10-100x faster than subprocess for many small queries

### 1.3 JQpy (Subprocess Wrapper)

**Package**: [`jqpy`](https://pypi.org/project/jqpy/) by baterflyrity
**Repository**: https://github.com/baterflyrity/jqpy

**What it is**: A thin Python wrapper around the `jq` binary that works cross-platform (including Windows) without requiring C compilation. Internally uses subprocess but provides a Pythonic API.

**Relevance**: Useful reference for how to wrap subprocess jq cleanly, but doesn't solve the performance problem since it still shells out.

### 1.4 pyjq (Legacy — Not Recommended)

**Package**: [`pyjq`](https://pypi.org/project/pyjq/) v2.6.0
**Status**: Inactive — no new releases in 12+ months, lower weekly downloads than `jq`

Not recommended due to lack of maintenance and incompatibility with the `jq` PyPI package.

---

## 2. Alternative Query Languages

### 2.1 JMESPath

**Website**: https://jmespath.org/
**Python package**: [`jmespath`](https://pypi.org/project/jmespath/)
**Used by**: AWS CLI, Azure CLI

**Strengths**:
- Formal specification with consistent behavior across all implementations
- Libraries in Python, JavaScript, Go, Java, PHP, Ruby, Lua, .NET, Rust
- Simpler learning curve than jq for basic queries
- Pure Python implementation (no C deps)

**Weaknesses**:
- Significantly slower than jq. Benchmarks show JMESPath Rust at ~13,800ms vs JSONPath Rust at ~9,240ms for complex filtering queries
- Limited transformation capabilities (query-focused, not transform-focused)
- No joins, no computed expressions, no user-defined functions
- Cannot do things like `(.wins / .games * 100 | floor)` — lacks arithmetic

**Verdict**: NOT suitable as primary query language for jtbl 2.0. The design requires computed column expressions, which JMESPath cannot do. However, could work as a simpler fallback syntax for basic path access.

### 2.2 JSONPath

**Spec**: RFC 9535 (standardized 2024)
**Python packages**: `jsonpath-ng`, `python-jsonpath`, `jsonpath-rfc9535`
**JavaScript packages**: `jsonpath-plus`, `JSONPath`

**Strengths**:
- XPath-like syntax familiar to many developers
- Recently standardized (RFC 9535)
- Multiple implementations in every language

**Weaknesses**:
- Inconsistent implementations across libraries (pre-RFC9535)
- Query-only — no transformation or arithmetic
- More verbose than jq for common operations

**Verdict**: NOT suitable as primary query language. Same limitation as JMESPath — no computed expressions. The RFC 9535 standardization is nice but doesn't add the features jtbl needs.

### 2.3 JSONata

**Website**: https://jsonata.org/
**JavaScript library**: `jsonata`
**Python**: No mature implementation

**Strengths**:
- Powerful transformation language (comparable to jq)
- First-class in JavaScript/Node.js
- Used in Node-RED, IBM Cloud

**Weaknesses**:
- JavaScript-only ecosystem (no good Python implementation)
- Different syntax from jq — users would need to learn a new language
- Smaller community than jq

**Verdict**: NOT suitable. jtbl 2.0 is Python-based, and JSONata has no Python implementation.

### 2.4 DuckDB SQL

**What it is**: An in-process analytical database that can query JSON files with SQL.

**Strengths**:
- SQL is universally known
- Extremely fast for analytical queries (columnar engine, vectorized execution)
- Can query JSON, Parquet, CSV directly
- Python package available (`duckdb`)

**Weaknesses**:
- Overkill for jtbl 2.0's use case
- SQL syntax for JSON traversal is verbose: `json_extract(data, '$.items[0].name')`
- Heavy dependency (~50MB)
- Different paradigm from the jq-centric design

**Verdict**: NOT suitable as primary query language. Could be interesting for post-MVP analytics features, but fundamentally conflicts with jtbl's "jq is the query language" principle.

### 2.5 Summary: Why jq is the Right Choice

| Feature | jq | JMESPath | JSONPath | JSONata | DuckDB SQL |
|---------|----|---------|---------|---------|----|
| Arithmetic expressions | Yes | No | No | Yes | Yes |
| String functions | Yes | Limited | No | Yes | Yes |
| User-defined functions | Yes | No | No | Yes | Yes |
| Streaming large files | Yes | No | No | No | Yes |
| Python native library | Yes (jq.py) | Yes | Yes | No | Yes |
| JavaScript/WASM | Yes (jq-web) | Yes | Yes | Yes | No |
| Learning resources | Excellent | Good | Good | Fair | Excellent |
| CLI tool available | Yes | Limited | No | No | Yes |

jq is the only language that satisfies all of jtbl 2.0's requirements: computed expressions, streaming, available in both Python and browser, and already the standard for JSON processing on the command line.

---

## 3. Fallback Strategy: When jq Binary is Unavailable

### 3.1 Dot-Path Walker (Pure Python, Zero Dependencies)

The design doc specifies a `extract_path()` fallback. This should support a subset of jq syntax:

**Supported subset**:
```
.key              → obj["key"]
.key1.key2        → obj["key1"]["key2"]
.key[0]           → obj["key"][0]
.key[]            → iterate obj["key"]
.key[].name       → [item["name"] for item in obj["key"]]
.key[0:5]         → obj["key"][0:5]  (slice)
```

**NOT supported** (requires full jq):
```
select(.active)           → filtering
.a + .b                   → arithmetic
(.wins / .games)          → computed expressions
map(...)                  → higher-order functions
test("regex")             → regex matching
if-then-else              → conditionals
```

**Implementation approach**: Parse the expression into a sequence of path segments (key access, array index, array iteration), then walk the Python object. This is ~50-80 lines of Python.

### 3.2 Python Libraries for Enhanced Fallback

#### glom

**Package**: [`glom`](https://pypi.org/project/glom/) v25.12.0
**Repository**: https://github.com/mahmoud/glom

**API**:
```python
from glom import glom

data = {"a": {"b": [{"name": "x"}, {"name": "y"}]}}
glom(data, "a.b")           # [{"name": "x"}, {"name": "y"}]
glom(data, ("a.b", ["name"]))  # ["x", "y"]
glom(data, "a.b.0.name")   # "x"
```

**Strengths**: Declarative transformation, good error messages, Python-native
**Weaknesses**: Different syntax from jq, adds a dependency
**Verdict**: Could work as enhanced fallback, but the syntax divergence from jq is confusing. Users would need to learn two syntaxes.

#### dpath

**Package**: [`dpath`](https://pypi.org/project/dpath/)

**API**:
```python
import dpath
dpath.get(data, "a/b/0/name")      # "x"
dpath.search(data, "a/b/*/name")   # glob matching
```

**Strengths**: Glob-style path matching, familiar `/` separator
**Weaknesses**: Different syntax from jq (uses `/` not `.`), no array iteration syntax
**Verdict**: Not a good fit — syntax is too different from jq.

#### jmespath (as fallback engine)

**API**:
```python
import jmespath
jmespath.search("a.b[*].name", data)  # ["x", "y"]
jmespath.search("a.b[0].name", data)  # "x"
```

**Strengths**: Clean syntax somewhat similar to jq dot-paths, pure Python, well-maintained
**Weaknesses**: Cannot do arithmetic or computed expressions
**Verdict**: Reasonable as a fallback engine for path access, but the syntax differences (e.g., `[*]` vs `[]`) may confuse users.

### 3.3 Recommended Fallback Strategy

**Primary**: Custom dot-path walker (pure Python, zero dependencies, ~50-80 lines)
- Covers the 80% case: `.key`, `.key.subkey`, `.key[]`, `.key[0]`
- Exactly matches jq syntax for these patterns
- Clear warning when a jq-only feature is used

**Why not add a library**: The fallback should cover simple path access with zero additional dependencies (supporting the "single file, zero install" principle). Adding glom or jmespath as a fallback engine introduces a dependency that most users won't need (most systems have jq).

**Detection**:
```python
import shutil

def has_jq():
    return shutil.which("jq") is not None
```

---

## 4. Performance Benchmarks & Recommendations

### 4.1 JSON Parsing Libraries (Python)

From benchmarks on a 13MB conda-forge metadata file:

| Library | Time | Strategy |
|---------|------|----------|
| msgspec | 45ms | Schema-based pre-parsing |
| simdjson | 62ms | SIMD + lazy object creation |
| orjson | 105ms | Optimized C parser |
| json (stdlib) | 114ms | Standard CPython parser |
| ujson | 122ms | C parser |

**Relevance**: jtbl uses `json.loads()` for parsing. For MVP, stdlib json is fine. For large files (>10MB), consider orjson as an optional optimization (it's a drop-in replacement).

### 4.2 jq Subprocess vs Native Binding

| Scenario | Subprocess jq | jq.py (native) | Notes |
|----------|--------------|-----------------|-------|
| Single query, 1KB | ~10-15ms | ~0.1ms | Subprocess overhead dominates |
| Single query, 1MB | ~20-50ms | ~5-10ms | jq processing time matters |
| Single query, 100MB | ~500ms-2s | ~400ms-1.5s | I/O dominates, similar perf |
| 100 rows × 5 cols (naive) | ~5-7.5s | ~5ms | 500 subprocess calls vs 500 C calls |
| 100 rows × 5 cols (batched) | ~15-50ms | ~5ms | Batching to 1-2 calls |
| Streaming, 1GB | jq --stream | N/A | jq binary wins for streaming |

**Key insight**: For per-row column evaluation (the hot path), the naive subprocess approach is 1000x slower than native bindings. **Batching** the subprocess calls is essential if using subprocess jq.

### 4.3 jq Streaming Mode

jq's `--stream` flag is critical for large files:

- **Regular parsing**: Loads entire JSON into memory. 10M-item array ≈ 5.5GB RAM.
- **Streaming parsing**: Emits path-value pairs. Same 10M-item array ≈ 2MB RAM.
- **Tradeoff**: Streaming is slower per-item but uses constant memory.

**When to use streaming**:
- Files > 100MB: Consider streaming
- Files > 1GB: Streaming is mandatory
- Files < 10MB: Regular parsing is fine

### 4.4 Recommended Performance Strategy for jtbl

1. **MVP**: Subprocess to `jq` binary with **batch evaluation** (single jq call for all columns)
2. **Optimization**: Add `jq` (PyPI) as an optional dependency for 10-100x faster per-row evaluation
3. **Large files**: Use subprocess `jq --stream` (streaming cannot be replicated with the Python jq binding easily)
4. **Fallback**: Pure Python dot-path walker (no performance concerns for simple paths)

```python
# Priority order:
# 1. jq Python binding (if installed) — fastest for column evaluation
# 2. jq binary subprocess (if available) — full jq, good for streaming
# 3. Pure Python dot-path walker — zero deps, limited syntax
```

---

## 5. Web UI: jq Editor Component

### 5.1 Browser-Side jq Execution

**jq-web** (npm: `jq-web`)
- Compiles jq C library to WebAssembly via Emscripten
- Full jq language support in the browser
- API: `jq.json(data, filter)` → JS object, `jq.raw(jsonString, filter)` → string
- Bundle size: ~500KB-1MB (WASM binary)
- GitHub: https://github.com/fiatjaf/jq-web (361 stars)
- Latest: v0.6.1 (February 2025)

**jq-wasm** (npm: `jq-wasm`)
- Alternative WASM compilation of jq
- Used by the official jq playground (play.jqlang.org)
- No native dependencies
- GitHub: https://github.com/pboutes/jq-wasm

**Recommendation for jtbl Web UI**: Since jtbl's web UI is Streamlit-based (Python server-side), jq execution happens on the server via subprocess — not in the browser. The Web UI does NOT need jq-web/jq-wasm. The Streamlit server calls jq just like the CLI does.

However, if a future version adds a standalone web UI (React/Next.js), jq-web would enable fully client-side jq execution.

### 5.2 Syntax Highlighting for jq Expressions

**For Streamlit (current plan)**:
- `streamlit-ace` provides the Ace editor component
- Ace does not have a built-in jq mode, but can use a custom mode or fall back to "text" mode
- For MVP, plain text with manual line coloring is sufficient

**For a standalone web UI (future)**:
- **CodeMirror 6**: Has a community jq mode. The official jq playground (play.jqlang.org) uses CodeMirror for its editor.
- **Monaco Editor**: VS Code's editor. No built-in jq mode but extensible via TextMate grammars.
- **Ace Editor**: Used in many web tools. Can define custom modes.

**Recommendation**: For MVP with Streamlit, use `streamlit-ace` without jq-specific syntax highlighting (it adds complexity with minimal user benefit at this stage). For a future standalone web UI, use CodeMirror 6 with the jq community language mode.

### 5.3 Official jq Playground Architecture

The official jq playground at play.jqlang.org:
- **Framework**: Next.js with TypeScript
- **jq execution**: jq-wasm (WebAssembly, runs entirely in browser)
- **Editor**: CodeMirror-based (with jq syntax highlighting)
- **Sharing**: PostgreSQL stores shared snippets; queries run locally
- **Deployment**: Docker + Fly.io
- **Source**: https://github.com/jqlang/playground

---

## 6. PEP 723 and `uv run`

### 6.1 What is PEP 723?

PEP 723 (Inline Script Metadata) defines a standardized way to embed dependency metadata directly in single-file Python scripts. This lets tools like `uv`, `hatch`, and `pdm` automatically manage dependencies when running the script.

**Format**:
```python
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "pandas>=2.0",
#     "tabulate>=0.9",
# ]
# ///
```

The block uses TOML syntax inside Python comments. It starts with `# /// script` and ends with `# ///`.

### 6.2 How `uv run` Uses PEP 723

When you run `uv run script.py`:

1. **Parse metadata**: `uv` reads the `# /// script` block
2. **Check Python version**: Verifies `requires-python` constraint is met
3. **Create isolated environment**: Creates a cached virtual environment (stored in `~/.cache/uv/environments-v2/`)
4. **Install dependencies**: Installs listed packages if not already cached
5. **Execute script**: Runs the script in the isolated environment

**Caching**: The environment folder name is a hash of Python version + dependency versions + script name. Re-running the script reuses the cached environment unless dependencies change.

**Lock files**: `uv lock --script script.py` creates a `.lock` file that pins all direct and indirect dependency versions for reproducible runs.

### 6.3 Shebang Pattern

For Unix-like systems, scripts can be made directly executable:

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pandas>=2.0", "tabulate>=0.9"]
# ///

import pandas as pd
# ... script code
```

Then:
```bash
chmod +x jtbl.py
./jtbl.py '.items' data.json
```

For Windows: `#!/usr/bin/env uv run --script` (omit `-S`)

### 6.4 Adding Dependencies via CLI

```bash
uv add --script jtbl.py "pandas>=2.0"
uv add --script jtbl.py "tabulate>=0.9"
```

This modifies the `# /// script` block in the file.

### 6.5 Production Tools Using PEP 723

| Tool | Support | Notes |
|------|---------|-------|
| uv | Full | Primary use case |
| Hatch | Full | Author of PEP 723 |
| PDM | Full | `pdm run script.py` |
| pip/pipx | Requested | Issue #12891 open |
| Ruff | Metadata reading | For tool configuration |
| Mypy | Metadata reading | For type checking context |
| Dependabot | Requested | Issue #11946 open |

### 6.6 Relevance to jtbl 2.0

jtbl 2.0's packaging model is designed around PEP 723:

- `jtbl.py` — CLI + core logic, declares `pandas` and `tabulate`
- `jtbl-ui.py` — Streamlit launcher, adds `streamlit` and `streamlit-ace`

Users run: `uv run jtbl.py '.items' data.json` — no virtualenv, no requirements.txt, no setup. Dependencies are resolved automatically.

**Key benefit**: The "single file, zero install" principle. A user can download one `.py` file and run it with `uv run`. The inline metadata tells `uv` exactly what to install.

**Optional jq binding**: The `jq` PyPI package could be listed in dependencies for performance. However, since it requires C compilation on some platforms, it should be **optional** — listed in a `[tool.uv.optional-dependencies]` section or detected at runtime:

```python
try:
    import jq as jq_native
    JQ_ENGINE = "native"
except ImportError:
    JQ_ENGINE = "subprocess" if shutil.which("jq") else "fallback"
```

---

## 7. Recommended Integration Strategy

### 7.1 Architecture

```
                   ┌─────────────────────────────┐
                   │       jtbl Query Engine      │
                   ├─────────────────────────────┤
                   │                               │
                   │  try:                         │
                   │    1. jq Python binding        │  ← Fastest (compile-once)
                   │       (import jq)             │
                   │                               │
                   │  except ImportError:           │
                   │    2. jq subprocess            │  ← Full jq, good streaming
                   │       (shutil.which("jq"))    │
                   │                               │
                   │  fallback:                    │
                   │    3. Dot-path walker          │  ← Zero deps, limited syntax
                   │       (built-in)              │
                   └─────────────────────────────┘
```

### 7.2 MVP Implementation

For MVP, use **subprocess jq only** with batch evaluation:

1. **Index query**: Single subprocess call with the user's jq expression
2. **Column evaluation**: Construct a single jq expression that evaluates all columns at once, run once per row set (not per row)
3. **Where filter**: Single subprocess call with `select(...)` wrapper
4. **Fallback**: Pure Python dot-path walker (~50-80 lines)

This keeps dependencies minimal (no `jq` PyPI package needed) and follows the design doc's decision: "Shell out to `jq` binary, dot-path fallback."

### 7.3 Post-MVP Optimization

Add `jq` (PyPI) as an optional dependency:
- Compile column expressions once
- Run against each row without subprocess overhead
- 10-100x faster for datasets with many rows and columns
- Still fall back to subprocess for streaming mode

### 7.4 Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Primary engine | Subprocess jq | Simplest, full language, matches design doc |
| Fallback engine | Pure Python dot-path | Zero deps, exact jq syntax for common paths |
| Optional optimization | jq PyPI binding | 10-100x faster per-row eval, opt-in |
| Web UI jq execution | Server-side (same as CLI) | Streamlit is server-rendered |
| Batch vs per-row subprocess | Batch | Critical for performance with subprocess |
| Alternative query language | None (jq only) | jq is the only language with computed expressions + streaming + Python + JS support |
| PEP 723 packaging | Yes | Core design principle (single file, zero install) |

---

## 8. References

### Python jq Libraries
- jq.py (PyPI `jq`): https://pypi.org/project/jq/ — v1.11.0, binds jq 1.8.1, Cython/C
- pyjq: https://pypi.org/project/pyjq/ — v2.6.0, inactive
- JQpy: https://github.com/baterflyrity/jqpy — subprocess wrapper, cross-platform

### Query Language Documentation
- jq manual: https://jqlang.org/manual/
- JMESPath: https://jmespath.org/
- JSONPath RFC 9535: https://www.rfc-editor.org/rfc/rfc9535
- JSONata: https://jsonata.org/

### Web/WASM jq
- jq-web (Emscripten): https://github.com/fiatjaf/jq-web — npm `jq-web`
- jq-wasm: https://github.com/pboutes/jq-wasm
- Official jq playground: https://play.jqlang.org/ (source: https://github.com/jqlang/playground)

### Python Data Access Libraries
- glom: https://github.com/mahmoud/glom — declarative nested data access
- dpath: https://pypi.org/project/dpath/ — glob-style path matching
- jmespath (Python): https://github.com/jmespath/jmespath.py

### PEP 723 & uv
- PEP 723 specification: https://peps.python.org/pep-0723/
- uv scripts guide: https://docs.astral.sh/uv/guides/scripts/
- Python packaging spec: https://packaging.python.org/en/latest/specifications/inline-script-metadata/

### Performance Research
- JSON parsing benchmarks: https://gist.github.com/jcrist/de29815389eaed4eaf5b24fbcfdab5f0
- jq startup time issue: https://github.com/jqlang/jq/issues/1411
- Large JSON processing: https://thenybble.de/posts/json-analysis/
- jq streaming guide: https://devblog.songkick.com/parsing-ginormous-json-files-via-streaming-be6561ea8671

### JSON Query Language Comparisons
- 10 Best JSON Query Languages: https://jsoneditoronline.org/indepth/query/10-best-json-query-languages/
- jq vs yq vs jsonpath vs jmespath: https://ritza.co/articles/gen-articles/jq-vs-yq-vs-jsonpath-vs-jmespath-vs-sed-vs-awk/
- JMESPath limits and alternatives: https://medium.com/@juliocesarbonon/stop-using-jmespath-everywhere-dca0bf5b75af
