# PEP 723 Inline Metadata, uv run, and Single-File Python Packaging

Research for jtbl 2.0 (Issue #58) — Packaging Strategy

---

## 1. PEP 723 — Inline Script Metadata

### 1.1 What Is It?

PEP 723 ([accepted October 2023](https://peps.python.org/pep-0723/)) specifies a metadata format embedded in single-file Python scripts. It allows scripts to declare their dependencies and Python version requirements directly, without external files like `requirements.txt` or `pyproject.toml`.

PEP 723 replaces the rejected PEP 722, which used a different, less structured comment format for the same purpose.

### 1.2 Syntax

The metadata block uses commented TOML wrapped in `# /// script` delimiters:

```python
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "pandas>=2.0",
#   "tabulate>=0.9",
# ]
# ///
```

**Rules:**
- Starting line: `# /// script` (exactly — no trailing content)
- Ending line: `# ///` (exactly)
- Each line between delimiters must start with `#` followed by a space (or just `#` for blank lines)
- The embedded content, after stripping the `# ` prefix, must be valid TOML
- Only one `script` metadata block per file (tools must error on duplicates)
- Unclosed blocks are silently ignored

### 1.3 Supported Fields

| Field | Type | Description |
|-------|------|-------------|
| `dependencies` | List of strings | PEP 508 dependency specifiers (same syntax as pyproject.toml) |
| `requires-python` | String | PEP 440 Python version constraint |
| `[tool]` | TOML table | Tool-specific configuration (mirrors pyproject.toml semantics) |

The `[tool]` table enables tool-specific configuration. For uv, this includes:

```python
# /// script
# requires-python = ">=3.10"
# dependencies = ["pandas>=2.0"]
#
# [tool.uv]
# exclude-newer = "2025-01-01"
# ///
```

The `exclude-newer` field limits uv to only considering distributions released before the specified date — useful for reproducibility.

### 1.4 Parsing

PEP 723 provides a canonical regex for metadata extraction:

```
(?m)^# /// (?P<type>[a-zA-Z0-9-]+)$\s(?P<content>(^#(| .*)$\s)+)^# ///
```

Reference Python implementations for reading, modifying, and streaming metadata blocks are included in the PEP. Tools read the metadata, parse the TOML content, and use the dependency list and Python version to configure the execution environment.

### 1.5 Comparison with Alternatives

| Approach | Format | Scope | Tool Support | Status |
|----------|--------|-------|-------------|--------|
| **PEP 723** | Commented TOML in script | Dependencies, Python version, tool config | uv, PDM, Hatch, pipx | **Accepted standard** |
| **PEP 722** (predecessor) | Natural-language comments | Dependencies only | Limited | **Rejected** in favor of 723 |
| **pyproject.toml** | TOML file | Full project metadata | All major tools | Standard for projects |
| **requirements.txt** | Plain text file | Dependencies only | pip | Legacy, not for scripts |
| **pipx run** | `--spec` flag | Dependencies | pipx | Ad-hoc, not embedded |

**Why PEP 723 won over PEP 722:**
- TOML is a well-defined format with existing validators; PEP 722's custom comment format was error-prone
- IDE tooling (syntax highlighting, validation) works with TOML; custom formats need custom support
- `[tool]` table enables tool-specific configuration not possible with PEP 722
- Consistent with pyproject.toml conventions — users learn one format

---

## 2. uv Tool Capabilities

### 2.1 `uv run` with PEP 723 Scripts

When `uv run script.py` encounters PEP 723 metadata:

1. Reads inline metadata from the script
2. Resolves dependencies (using uv's fast Rust-based resolver)
3. Creates an ephemeral virtual environment with the resolved packages
4. Executes the script in that environment
5. The environment is cleaned up after execution

**Key behavior:** When inline metadata is present, project dependencies are **ignored** — even when running inside a project directory with pyproject.toml. This ensures script isolation.

### 2.2 Ephemeral Environments and Caching

uv creates "environments on-demand instead of using a long-lived virtual environment." However, **packages are cached** between runs.

**Performance data from real-world benchmarks:**
- 5 packages installed: ~12ms
- 7 packages installed: ~10ms  
- 9 packages installed: ~24ms (cold) / ~207ms (with more packages)

First run downloads and caches packages. Subsequent runs reuse cached wheels, making environment creation nearly instant (typically <1 second even for many packages).

**Cache location:** `~/.cache/uv/` by default. Can be configured via `UV_CACHE_DIR` or `--cache-dir`.

### 2.3 `uv run` vs `uv tool run` (uvx)

| Feature | `uv run` | `uvx` / `uv tool run` |
|---------|----------|----------------------|
| **Use case** | Scripts, project code | Published CLI tools |
| **Environment** | Project-aware or script-specific | Always isolated from project |
| **Project deps** | Included (unless `--no-project` or PEP 723) | Never included |
| **Local imports** | Script directory on sys.path | Not available |
| **Alias** | None | `uvx` = `uv tool run` |

**For jtbl:** `uv run jtbl.py` is the correct invocation. `uvx` is for PyPI-published tools.

### 2.4 Lock Files for Scripts

uv supports lockfiles for PEP 723 scripts (added ~January 2025):

```bash
# Create lock file
uv lock --script jtbl.py
# Creates jtbl.py.lock (same format as uv.lock)

# Subsequent runs respect the lock
uv run jtbl.py  # uses locked versions

# Export locked dependencies
uv export --script jtbl.py
```

The lock file is created adjacent to the script (e.g., `jtbl.py.lock`). If no lockfile exists, uv resolves freely.

**Pre-PEP for inline locks:** There is an active discussion ([discuss.python.org](https://discuss.python.org/t/pre-pep-locking-a-pep-723-single-file-script/98034)) about embedding lock metadata directly inside scripts using a `# /// pylock` block. This would enable single-file reproducibility without a separate `.lock` file. Currently in pre-PEP discussion phase; uv's existing `.lock` file approach is the production-ready solution.

### 2.5 Dependency Management Commands

```bash
# Initialize a script with PEP 723 metadata
uv init --script jtbl.py --python 3.10

# Add dependencies (modifies inline metadata)
uv add --script jtbl.py 'pandas>=2.0' 'tabulate>=0.9'

# Show dependency tree
uv tree --script jtbl.py

# Lock dependencies
uv lock --script jtbl.py
```

### 2.6 Running Scripts from URLs

uv can execute scripts directly from HTTP(S) URLs:

```bash
# From raw GitHub URL
uv run https://raw.githubusercontent.com/user/repo/main/jtbl.py '.items' data.json

# From GitHub Gist (uv resolves the raw URL automatically)
uv run https://gist.github.com/user/abc123
```

This enables zero-install distribution — share a URL, anyone with uv can run it.

---

## 3. Design Patterns for Single-File Tools

### 3.1 Dual-Use: CLI Tool and Importable Module

The standard Python `if __name__ == "__main__"` pattern enables a file to function as both:

```python
# /// script
# requires-python = ">=3.10"
# dependencies = ["pandas>=2.0", "tabulate>=0.9"]
# ///

"""jtbl — JSON table tool."""

__version__ = "2.0.0"

import pandas as pd
import json
import sys

# --- Core library functions ---
def jq_query(data, expr):
    """Run jq against JSON data."""
    ...

def project_columns(rows, columns):
    """Project rows into columns."""
    ...

def render_table(df, fmt="table"):
    """Render DataFrame in requested format."""
    ...

# --- CLI entry point ---
def main(argv=None):
    """CLI entry point."""
    ...

if __name__ == "__main__":
    main()
```

When executed via `uv run jtbl.py`, `__name__` is `"__main__"` and the CLI runs. When imported by another script (`import jtbl`), only the functions are available.

### 3.2 Conditional Imports for Optional Dependencies

For features that require heavy dependencies (like Streamlit for web UI), use try/except:

```python
# In jtbl.py — core tool
try:
    import streamlit as st
    HAS_STREAMLIT = True
except ImportError:
    HAS_STREAMLIT = False

# Only used if running in web mode
if HAS_STREAMLIT and is_web_mode():
    run_web_ui()
```

However, for the jtbl design this is **not recommended**. The design doc correctly separates CLI and web UI into two files with different dependency lists. This avoids loading Streamlit for CLI usage.

### 3.3 Making Scripts Directly Executable (Shebang)

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pandas>=2.0"]
# ///

# ... script code ...
```

After `chmod +x jtbl.py`, the script can be run directly: `./jtbl.py '.items' data.json`

The `-S` flag in the shebang lets `env` split the arguments. The `--script` flag is **critical** on the shebang line — without it, uv may misinterpret the invocation.

### 3.4 Versioning Single-File Scripts

PEP 723 does not include a `version` field in the `script` metadata type. For single-file tools, the standard pattern is:

```python
__version__ = "2.0.0"
```

This is accessible both when the script is imported as a module and from the CLI (`jtbl --version`). Version bumps are manual edits to this line.

### 3.5 Testing PEP 723 Scripts

Two approaches:

**Approach A: Import and test functions directly**

```python
# test_jtbl.py
# /// script
# requires-python = ">=3.10"
# dependencies = ["pytest", "pandas>=2.0", "tabulate>=0.9"]
# ///

import importlib.util
import sys

# Load jtbl.py as a module
spec = importlib.util.spec_from_file_location("jtbl", "./jtbl.py")
jtbl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(jtbl)

def test_auto_infer_columns():
    rows = [{"id": 1, "name": "alice"}, {"id": 2, "name": "bob"}]
    result = jtbl.infer_columns(rows)
    assert result == ["id", "name"]
```

**Approach B: Simpler — if the script uses `if __name__ == "__main__"`, just import it**

```python
# test_jtbl.py
import sys
sys.path.insert(0, ".")
import jtbl  # imports without running main()

def test_jq_query():
    result = jtbl.jq_query({"x": 1}, ".x")
    assert result == [1]
```

Run with: `uv run --with pytest -- pytest test_jtbl.py`

---

## 4. The Dual-File Pattern for jtbl

### 4.1 Design

The jtbl design doc specifies two files:

```
jtbl.py          # CLI + core logic (PEP 723: pandas, tabulate)
jtbl-ui.py       # Streamlit web launcher (PEP 723: pandas, tabulate, streamlit, streamlit-ace)
```

### 4.2 Can One PEP 723 Script Import from Another?

**Yes, with caveats.** When `uv run jtbl-ui.py` is executed:

1. uv creates an ephemeral environment with `jtbl-ui.py`'s dependencies (which include streamlit)
2. Python runs `jtbl-ui.py` with the script's directory on `sys.path`
3. `jtbl-ui.py` can do `import jtbl` — this imports `jtbl.py` from the same directory
4. `jtbl.py`'s own PEP 723 metadata is **ignored** during this import (it's only read by uv when `jtbl.py` is the entry point)
5. `jtbl.py`'s dependencies must be included in `jtbl-ui.py`'s dependency list

**This means:**
- `jtbl-ui.py` must declare **all** dependencies (its own + jtbl.py's)
- The import works because Python's standard module import checks `sys.path`, and the script's directory is on it
- Both files must live in the same directory

**Recommended jtbl-ui.py structure:**

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "pandas>=2.0",
#   "tabulate>=0.9",
#   "streamlit>=1.30",
#   "streamlit-ace>=0.1.1",
# ]
# ///

import jtbl  # imports from same directory — core logic
import streamlit as st
from streamlit_ace import st_ace

def main():
    st.set_page_config(page_title="jtbl", layout="wide")
    # ... web UI code using jtbl.jq_query(), jtbl.project_columns(), etc.

if __name__ == "__main__":
    main()
```

### 4.3 Running the Web UI

```bash
# Option A: via uv run (uv handles deps, then streamlit runs the app)
uv run streamlit run jtbl-ui.py

# Option B: if jtbl-ui.py includes streamlit.run() internally
uv run jtbl-ui.py
```

Note: Streamlit apps are typically launched with `streamlit run script.py`, not `python script.py`. The jtbl-ui.py script may need to handle this by detecting the launch mode.

---

## 5. Distribution and Publishing

### 5.1 Single-File Distribution (Primary for jtbl)

The simplest distribution model — share the files:

| Method | Command |
|--------|---------|
| **Local file** | `uv run jtbl.py '.items' data.json` |
| **From URL** | `uv run https://raw.githubusercontent.com/user/repo/main/jtbl.py '.items' data.json` |
| **From Gist** | `uv run https://gist.github.com/user/abc123 '.items' data.json` |
| **Direct execution** | `chmod +x jtbl.py && ./jtbl.py '.items' data.json` |

No packaging, no publishing, no installation. Just share the file.

### 5.2 PyPI Publishing (Future Option)

If jtbl later needs PyPI distribution (for `uvx jtbl` or `pip install jtbl`):

1. Create a `pyproject.toml` with the same dependencies
2. Add `[project.scripts]` to define CLI entry points
3. Build and publish with `uv build && uv publish`
4. Users install with `uv tool install jtbl` or `uvx jtbl`

This is a **separate step** — the PEP 723 script continues to work independently. You can maintain both: the single-file script for lightweight distribution and a proper package for PyPI.

### 5.3 Lock File Distribution

For reproducible deployments:

```bash
# Developer creates lock
uv lock --script jtbl.py

# Distribute both files:
#   jtbl.py       (script)
#   jtbl.py.lock  (locked dependencies)

# Users get exact same versions
uv run jtbl.py  # respects jtbl.py.lock if present
```

---

## 6. Integration with Dev Toolkit

### 6.1 Standalone First, Plugin Later

The jtbl design correctly prioritizes standalone functionality. The tool works independently via `uv run jtbl.py` before any plugin framework exists.

### 6.2 Plugin Import Pattern

When the Dev Toolkit (issue #56) establishes a plugin system, jtbl can be integrated via Python's `importlib`:

```python
# In the Dev Toolkit plugin loader
import importlib.util

def load_plugin(path):
    spec = importlib.util.spec_from_file_location("jtbl", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

jtbl = load_plugin("/path/to/jtbl.py")
result = jtbl.jq_query(data, ".items")
```

**Key consideration:** When loaded as a plugin, the PEP 723 metadata is irrelevant — the host application (Dev Toolkit) manages dependencies. The plugin's dependencies must be available in the host's environment.

### 6.3 Should Plugins Use PEP 723?

**For self-contained dependency management:** PEP 723 metadata in plugins serves as **documentation** of what the plugin needs. The host application can parse it to check if dependencies are satisfied before loading.

**For actual dependency resolution:** The host application (Dev Toolkit) should manage all dependencies centrally. Having each plugin run in its own ephemeral uv environment would be wasteful and create import isolation barriers.

**Recommended approach:**
- Plugins declare dependencies via PEP 723 metadata (documentation + standalone usage)
- The Dev Toolkit reads plugin metadata at registration time to resolve the union of all plugin dependencies
- At runtime, all plugins share the host environment

---

## 7. Real-World Examples and Patterns

### 7.1 Simon Willison's One-Shot Tools

Simon Willison popularized the PEP 723 + uv pattern for building single-file Python utilities. His approach:

- Scripts declare dependencies via PEP 723 inline metadata
- Uses Click for CLI interfaces
- Distributes via GitHub Gists or raw URLs
- Users run directly: `uv run https://gist.github.com/.../script.py`

Examples include S3 debugging tools, HTML strippers, and web scrapers — all as single files.

**Key insight from Willison:** LLMs (like Claude) can generate complete, self-contained tools when given a short PEP 723 example in their system prompt. This makes the pattern ideal for agent-generated tools.

### 7.2 Trey Hunner's "Lazy Self-Installing Scripts"

Trey Hunner documented the shebang pattern for making scripts self-installing:

```python
#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["httpx"]
# ///
```

The script behaves like a native command — no `uv run` prefix needed after `chmod +x`.

### 7.3 MCP Server Distribution

PEP 723 scripts are emerging as a distribution format for Model Context Protocol (MCP) servers. A single `.py` file can define an MCP server with all its dependencies, runnable via `uv run`.

---

## 8. Recommendations for jtbl Packaging Strategy

### 8.1 File Structure (Confirmed)

The design doc's two-file approach is correct:

```
jtbl.py          # CLI + core logic
jtbl-ui.py       # Streamlit launcher (imports jtbl)
```

### 8.2 Metadata Blocks

**jtbl.py:**
```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "pandas>=2.0",
#   "tabulate>=0.9",
# ]
# ///
```

**jtbl-ui.py:**
```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "pandas>=2.0",
#   "tabulate>=0.9",
#   "streamlit>=1.30",
#   "streamlit-ace>=0.1.1",
# ]
# ///
```

Note: `jtbl-ui.py` must duplicate `jtbl.py`'s dependencies because the PEP 723 metadata in `jtbl.py` is only read when `jtbl.py` is the entry point.

### 8.3 Invocation Patterns

```bash
# CLI (primary)
uv run jtbl.py '.items' data.json

# CLI (direct execution after chmod +x)
./jtbl.py '.items' data.json

# CLI (from URL)
uv run https://raw.githubusercontent.com/.../jtbl.py '.items' data.json

# Web UI
uv run streamlit run jtbl-ui.py

# As a Dev Toolkit plugin (future)
# Loaded via importlib by the host application
```

### 8.4 Lock File Strategy

- **Do not** include lock files by default — jtbl is a tool, not a production deployment
- **Do** support `uv lock --script jtbl.py` for users who need reproducibility
- Consider adding `[tool.uv] exclude-newer = "2025-XX-XX"` for release snapshots

### 8.5 Future PyPI Path

If demand warrants, jtbl can be published to PyPI alongside the single-file distribution:

```bash
# Create pyproject.toml from PEP 723 metadata
# Build and publish
uv build && uv publish

# Users then run via:
uvx jtbl '.items' data.json
# or
uv tool install jtbl
jtbl '.items' data.json
```

This is additive — the PEP 723 single-file pattern continues to work independently.

### 8.6 Testing Strategy

Use the import pattern for unit tests:

```bash
# Run tests
uv run --with pytest -- pytest test_jtbl.py

# Or with a test file that has its own PEP 723 metadata
uv run test_jtbl.py
```

The test file imports `jtbl` as a module (the `if __name__ == "__main__"` guard prevents the CLI from running on import).

---

## 9. Risks and Considerations

### 9.1 jq Binary Dependency

jq is external to PEP 723 — it cannot be declared as a Python dependency. The design doc's fallback to a dot-path walker is the correct mitigation.

### 9.2 Streamlit Launch Mode

Streamlit apps need `streamlit run script.py`, not `python script.py`. The `jtbl-ui.py` launcher may need to either:
- Include logic to re-launch itself via `streamlit run` if invoked directly
- Document the correct invocation: `uv run streamlit run jtbl-ui.py`

### 9.3 Cross-Script Import Fragility

The dual-file import pattern (jtbl-ui imports jtbl) works when both files are in the same directory. If the user moves files to different locations, the import breaks. This should be documented clearly.

### 9.4 Dependency Duplication

jtbl-ui.py must duplicate all of jtbl.py's dependencies. Version constraints must be kept in sync manually. A CI check or test could verify consistency.

### 9.5 `uv` Adoption

The pattern assumes users have `uv` installed. While uv is gaining rapid adoption (5M+ downloads/month), fallback instructions should be provided:

```bash
# Without uv (requires manual dep installation)
pip install pandas tabulate
python jtbl.py '.items' data.json
```

---

## Sources

- [PEP 723 — Inline Script Metadata (Official)](https://peps.python.org/pep-0723/)
- [uv Running Scripts Guide](https://docs.astral.sh/uv/guides/scripts/)
- [uv Using Tools Guide](https://docs.astral.sh/uv/guides/tools/)
- [Simon Willison: Building Python Tools with uv run and Claude](https://simonwillison.net/2024/Dec/19/one-shot-python-tools/)
- [Python Developer Tooling Handbook: PEP 723](https://pydevtools.com/handbook/explanation/what-is-pep-723/)
- [Python Developer Tooling Handbook: Self-Contained Scripts](https://pydevtools.com/handbook/how-to/how-to-write-a-self-contained-script/)
- [Python Developer Tooling Handbook: uv run vs uvx](https://pydevtools.com/handbook/explanation/when-to-use-uv-run-vs-uvx/)
- [Pre-PEP: Locking a PEP 723 Single-File Script](https://discuss.python.org/t/pre-pep-locking-a-pep-723-single-file-script/98034)
- [Fun with uv and PEP 723](https://www.cottongeeks.com/articles/2025-06-24-fun-with-uv-and-pep-723)
- [Share Python Scripts Like a Pro: uv and PEP 723](https://thisdavej.com/share-python-scripts-like-a-pro-uv-and-pep-723-for-easy-deployment/)
- [uv GitHub Repository](https://github.com/astral-sh/uv)
- [PEP 722/723 Decision Discussion](https://discuss.python.org/t/pep-722-723-decision/36763)
- [Remote Single-File Python Scripts with uv](https://joshcannon.me/2025/04/24/remote-single-file-scripts.html)
