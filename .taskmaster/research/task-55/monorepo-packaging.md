# Monorepo Structure & Plugin Packaging for the Dev Toolkit

**Research for**: Dev Toolkit (Epic #55, Core Framework #56)
**Date**: 2026-03-13
**Researcher**: task-55-researcher-monorepo

---

## 1. Executive Summary

**Recommended approach: Single-package flat monorepo with a uv-managed Python project, plugins as sub-packages, frontend built with Vite, everything baked into the Claudio Docker image as a single installable unit.**

This is the right choice for the Dev Toolkit because:
- 4-5 plugins is too few to justify workspace/multi-package overhead
- Everything ships in one Docker image anyway (no independent publishing)
- The existing Claudio codebase already uses a flat structure (see `cli/` directory)
- Python + FastAPI is the established backend choice (per web-framework-comparison.md research)
- uv provides fast dependency resolution without the complexity of workspaces
- A unified version number for the toolkit + all plugins is the pragmatic choice

---

## 2. Monorepo Approach Comparison

### Option A: Single-Package Flat Structure (RECOMMENDED)

```
dev-toolkit/
├── pyproject.toml              # Single project: "dev-toolkit"
├── uv.lock                     # Lockfile
├── src/
│   └── dev_toolkit/
│       ├── __init__.py
│       ├── __main__.py         # CLI entry: `python -m dev_toolkit` or `dev-toolkit`
│       ├── app.py              # FastAPI app factory, plugin discovery
│       ├── config.py           # Toolkit configuration
│       ├── plugin.py           # Plugin base class / interface
│       ├── static/             # Compiled frontend assets (production)
│       └── plugins/
│           ├── __init__.py
│           ├── markdown_browser/
│           │   ├── __init__.py
│           │   ├── plugin.py   # Plugin manifest + routes
│           │   ├── routes.py   # FastAPI APIRouter
│           │   ├── service.py  # Business logic
│           │   └── frontend/   # Plugin-specific React components (dev)
│           ├── jtbl/
│           │   ├── __init__.py
│           │   ├── plugin.py
│           │   ├── jtbl.py     # Core CLI logic (standalone-capable)
│           │   ├── routes.py
│           │   └── frontend/
│           ├── permissions_gateway/
│           │   ├── __init__.py
│           │   ├── plugin.py
│           │   ├── routes.py
│           │   ├── watcher.py  # File watcher for .agent-runtime/
│           │   ├── ledger.py   # Hash-chained ledger
│           │   └── frontend/
│           └── agent_builder/
│               ├── __init__.py
│               ├── plugin.py
│               ├── routes.py
│               ├── resolver.py # Config resolution logic
│               └── frontend/
├── frontend/                   # Shared React app (Vite)
│   ├── package.json
│   ├── vite.config.ts
│   ├── src/
│   │   ├── App.tsx             # Shell, sidebar, routing
│   │   ├── components/         # Shared UI components
│   │   └── plugins/            # Plugin frontend entry points
│   │       ├── markdown-browser/
│   │       ├── jtbl/
│   │       ├── permissions-gateway/
│   │       └── agent-builder/
│   └── dist/                   # Built → copied to src/dev_toolkit/static/
├── tests/
│   ├── test_core/
│   ├── test_markdown_browser/
│   ├── test_jtbl/
│   ├── test_permissions_gateway/
│   └── test_agent_builder/
└── scripts/
    ├── dev.sh                  # Start dev mode (uvicorn + vite)
    └── build.sh                # Build frontend, package for Docker
```

**Pros:**
- **Simplest setup**: One `pyproject.toml`, one lockfile, one build command
- **Shared dependencies**: All plugins share the same FastAPI, Pydantic, etc. No version conflicts
- **Easy imports**: Plugins can import from each other (`from dev_toolkit.plugins.jtbl import ...`) without workspace protocol
- **Single test run**: `pytest` runs everything. No orchestration needed
- **Docker-friendly**: One `pip install .` in Dockerfile installs everything
- **Matches Claudio patterns**: The existing `cli/` directory uses this same flat approach
- **Plugin discovery**: Simple — scan `dev_toolkit/plugins/` for directories with `plugin.py`

**Cons:**
- Plugins can't have conflicting dependency versions (unlikely with 4-5 in-house plugins)
- All plugins must be installed even if not needed (acceptable since they ship in the base image)
- No independent versioning per plugin (unnecessary for bundled delivery)

### Option B: uv Workspaces (Python Monorepo)

```
dev-toolkit/
├── pyproject.toml              # Root workspace
├── uv.lock                     # Shared lockfile
├── packages/
│   ├── core/
│   │   └── pyproject.toml      # "dev-toolkit-core"
│   ├── plugin-markdown-browser/
│   │   └── pyproject.toml      # "dev-toolkit-markdown-browser"
│   ├── plugin-jtbl/
│   │   └── pyproject.toml      # "dev-toolkit-jtbl"
│   ├── plugin-permissions-gateway/
│   │   └── pyproject.toml
│   └── plugin-agent-builder/
│       └── pyproject.toml
└── frontend/
    └── package.json
```

**Pros:**
- Each plugin declares its own dependencies
- Could publish plugins independently to PyPI
- Cleaner dependency graphs (each plugin declares only what it needs)

**Cons:**
- **Overhead disproportionate to scale**: uv workspaces add configuration complexity for 4-5 packages. The `una` tool exists specifically because uv workspaces can't build workspace members with inter-dependencies into distributable packages without extra tooling.
- **Cross-plugin imports require workspace protocol**: `dev-toolkit-jtbl` depends on `dev-toolkit-core` via `workspace:` protocol, which adds boilerplate.
- **Docker build complexity**: Need to either `pip install -e` each package or use a build tool like `una` to flatten for production.
- **Testing complexity**: Need to configure pytest to discover tests across packages, or run per-package.
- **Premature abstraction**: Independent versioning and publishing are not needed — everything ships as one Docker image.

**Verdict**: **Not recommended** for the Dev Toolkit's current scale. Would reconsider if: (a) plugins grew to 10+, (b) external contributors needed to develop plugins in isolation, or (c) plugins needed independent release cycles.

### Option C: pnpm/npm Workspaces (Node.js Monorepo)

```
dev-toolkit/
├── package.json                # Root workspace
├── pnpm-workspace.yaml
├── packages/
│   ├── server/                 # Express/Fastify backend
│   │   └── package.json
│   ├── frontend/               # React/Vite app
│   │   └── package.json
│   ├── plugin-markdown-browser/
│   │   └── package.json
│   └── plugin-jtbl/
│       └── package.json        # Would need Python subprocess for jq
└── turbo.json                  # Optional: Turborepo for build orchestration
```

**Pros:**
- Mature ecosystem (pnpm workspaces well-proven in 2025-2026)
- Turborepo adds fast cached builds with minimal config (~20 lines)
- Unified frontend and backend language
- React SSR/streaming possible natively

**Cons:**
- **Language mismatch**: jtbl is Python (PEP 723, jq+pandas). Agent Builder has a working Python prototype (`/workspace/mpulse/agent-build-tool/`). Permissions Gateway needs Python file watching libraries. Forcing Node.js means rewriting existing Python work or running Python subprocesses from Node.
- **Heavier in Docker**: Node.js packages are larger than Python equivalents. Current image has both runtimes, but Python packages are more space-efficient.
- **FastAPI already chosen**: Prior research (web-framework-comparison.md) selected FastAPI. Switching to Express/Fastify contradicts established decisions.
- **Two package managers**: Would still need Python (uv/pip) for jtbl's pandas, jq, etc.

**Verdict**: **Not recommended**. The toolkit is fundamentally Python-centric given the existing tools and established backend choice.

### Option D: Nx/Turborepo Orchestration Layer

**When it's worth it:**
- 10+ packages with complex dependency graphs
- CI needs to run only affected tests
- Multiple teams contributing independently
- Build caching across CI runs

**When it's overkill:**
- 4-5 packages with a single maintainer (our case)
- Everything ships as one artifact (Docker image)
- Simple `pytest` and `vite build` cover all builds

Research from multiple sources confirms that for projects with <5 packages, the setup overhead of Nx (200+ lines of config) or even Turborepo (simpler but still an extra tool) is not justified. A Makefile or shell scripts provide equivalent orchestration at this scale.

**Verdict**: **Not recommended** now. If the toolkit grows to 10+ plugins with multiple contributors, revisit Turborepo (not Nx — too heavy for this project's philosophy).

---

## 3. Comparison Summary

| Factor | Flat (A) | uv Workspaces (B) | pnpm Workspaces (C) | Nx/Turbo (D) |
|--------|----------|-------------------|---------------------|--------------|
| **Setup complexity** | Minimal | Medium | Medium-High | High |
| **Cross-plugin imports** | Direct Python imports | Workspace protocol | Workspace protocol | Workspace protocol |
| **Docker packaging** | `pip install .` | `una build` or `pip install -e` each | `pnpm install --frozen-lockfile` | Same as C |
| **Polyglot support** | Python-native, Node for frontend only | Python only | Node-native, Python as subprocess | Language-agnostic |
| **Independent versioning** | No (single version) | Yes | Yes | Yes |
| **Test orchestration** | `pytest` | `uv run --package X pytest` | `pnpm -r test` / `turbo test` | `nx affected:test` |
| **Right for 4-5 plugins?** | **Yes** | Overkill | Wrong language | Overkill |

---

## 4. Plugin Distribution Model

### Recommended: Bundled Core + Extension Point for Future External Plugins

**Phase 1 (Now): All plugins bundled in the Docker image**

All 4 plugins ship as part of the `dev-toolkit` Python package, installed in the Claudio base image. Every Claudio container gets every plugin. Users can disable plugins they don't need via configuration.

```python
# dev_toolkit/config.py
DEFAULT_CONFIG = {
    "plugins": {
        "markdown_browser": {"enabled": True},
        "jtbl": {"enabled": True},
        "permissions_gateway": {"enabled": True},
        "agent_builder": {"enabled": True},
    },
    "server": {
        "host": "0.0.0.0",
        "port": 5565,
    }
}
```

**Why bundled now:**
- Zero setup for users (principle #5 from issue #55: "Container-native. Ships in the Claudio base image. Zero setup for users.")
- 4 plugins add negligible image size vs. the complexity of an install mechanism
- All plugins are first-party — no version compatibility matrix to manage
- Simplifies testing (one image to test, not N combinations)

**Phase 2 (Future): Extension point for external plugins**

Design the plugin interface so that external plugins CAN be loaded from a configurable directory (e.g., `~/.claudio/dev-toolkit-plugins/` or via the shared volume). This doesn't require implementation now — just ensuring the plugin discovery mechanism scans configurable directories, not just the built-in `plugins/` package.

```python
# Future: scan additional plugin directories
PLUGIN_DIRS = [
    Path(__file__).parent / "plugins",          # Built-in (bundled)
    Path.home() / ".claudio" / "toolkit-plugins",  # User-installed
]
```

This follows the Grafana model: core plugins bundled in the distribution, external plugins loaded from a configurable directory at runtime.

### Models NOT Recommended for Phase 1

**pip-installable plugins** (`pip install dev-toolkit-plugin-foo`): Adds PyPI publishing overhead, version compatibility matrix, and dependency management complexity. Not needed when all plugins are first-party and ship in one image.

**Container-layer plugins** (separate Docker layers per plugin): Docker layer caching doesn't help here — all plugins change together and are built from the same source. Multiple layers add complexity to the Dockerfile without benefit.

---

## 5. Docker Image Packaging Strategy

### How the Dev Toolkit Fits into Dockerfile.base

The dev-toolkit should be installed as a new layer in `Dockerfile.base`, after the existing tooling but before the user configuration layers:

```dockerfile
# Current Layer 13: Claudio CLI
COPY cli/ /usr/local/lib/claudio/
...

# NEW Layer 14: Dev Toolkit
# Copy the dev-toolkit source and install
COPY dev-toolkit/ /opt/dev-toolkit/
RUN cd /opt/dev-toolkit && pip install --break-system-packages . \
    && rm -rf /opt/dev-toolkit

# This installs the `dev-toolkit` CLI command globally and all plugin code
# The frontend is pre-built (dist/ already in the package's static/ dir)

# Current Layer 14→15: Initialization scripts and entrypoint
...
```

### Build Pipeline

```
Developer workflow:
1. Edit Python backend code in dev-toolkit/src/
2. Edit React frontend code in dev-toolkit/frontend/
3. For development: `./scripts/dev.sh` (runs uvicorn --reload + vite dev)
4. For Docker build:
   a. `cd frontend && npm run build`  → outputs to frontend/dist/
   b. `cp -r frontend/dist/ src/dev_toolkit/static/`  → bundle into Python package
   c. `./build-base.sh`  → Docker image includes built frontend
```

### Development Mode vs Production Mode

**Development mode** (inside a running container):
```bash
# Terminal 1: Backend with hot reload
cd /workspace/dev-toolkit
uvicorn dev_toolkit.app:create_app --factory --reload --reload-dir src --port 5565

# Terminal 2: Frontend with HMR
cd /workspace/dev-toolkit/frontend
npm run dev -- --port 3000
# Vite proxies /api/* to localhost:5565
```

The dev-toolkit source is available at `/workspace/dev-toolkit/` via the bind mount (`.:/workspace:cached`). Editing source files on the host triggers hot reload automatically.

**Production mode** (in built Docker image):
```bash
# Single process serves everything
dev-toolkit serve
# FastAPI serves the built React app from static/ directory
# No Vite, no hot reload — just the built artifacts
```

### Layer Optimization

The dev-toolkit install should be a **single Docker layer** that:
1. Copies source
2. Installs Python dependencies
3. Includes pre-built frontend static assets
4. Cleans up source directory (keeps only installed package)

This is preferred over multiple layers because:
- All components change together (backend + frontend + plugins)
- One layer means one cache invalidation point (simpler)
- Cleanup in the same layer reduces image size

### Image Size Impact Estimate

| Component | Size Estimate | Notes |
|-----------|---------------|-------|
| FastAPI + uvicorn + deps | ~30-50 MB | Installed via pip |
| Frontend built assets | ~2-5 MB | Minified React app |
| Plugin Python code | ~1-2 MB | Pure Python, minimal deps |
| Plugin-specific deps (pandas, tabulate) | ~50-80 MB | Mainly for jtbl |
| **Total** | **~85-140 MB** | On top of current ~2GB image |

This is acceptable for a dev tool that runs in a development container. The jtbl plugin's pandas dependency is the largest contributor — if image size becomes a concern, pandas could be made an optional dependency (`pip install dev-toolkit[jtbl]`).

---

## 6. Versioning Strategy

### Recommended: Unified Version Number

All plugins share a single version number that tracks the dev-toolkit release. When you release dev-toolkit 1.2.0, all plugins are at 1.2.0.

**Why:**
- Everything ships as one artifact (Docker image tag)
- Users never need to think about "which version of the markdown browser works with which version of the core framework"
- Simplifies changelog and release notes
- Matches the existing Claudio versioning approach (one image tag = one version of everything)

**Implementation:**
```toml
# pyproject.toml
[project]
name = "dev-toolkit"
version = "0.1.0"

# Plugins read version from the package:
# from dev_toolkit import __version__
```

The Docker image tag is the authoritative version identifier:
- `ghcr.io/ksizzle88/claudio:latest` includes dev-toolkit at whatever version is in that build
- `ghcr.io/ksizzle88/claudio:v2.2.0` includes dev-toolkit 0.1.0 (or whatever ships with that Claudio release)

### Why NOT Independent Versioning

Independent versioning makes sense for Grafana (thousands of third-party plugins, independent release cadences) but not for:
- 4 first-party plugins maintained by the same team
- A single delivery mechanism (Docker image)
- No external consumers of individual plugins

---

## 7. Handling the Polyglot Nature

### The Challenge

The Dev Toolkit has mixed language requirements:
- **Core + most plugins**: Python (FastAPI, file watching, YAML/JSON processing)
- **jtbl**: Python (PEP 723 standalone script, pandas, jq subprocess)
- **Agent Builder**: Existing Python prototype (`/workspace/mpulse/agent-build-tool/`)
- **Frontend**: TypeScript/React (Vite)
- **Possible future**: Go/Rust for performance-critical CLI tools

### The Solution: Python Backend, React Frontend, CLI Wrappers

```
Language Boundary
─────────────────
Python (FastAPI):  Core framework, plugin backends, CLI
React (Vite):      All frontend UI
Shell scripts:     Dev/build orchestration, CLI wrappers
jq binary:         Called as subprocess from Python (jtbl)
```

**Python handles ALL backend logic.** This is the right call because:
1. FastAPI is already the chosen framework
2. Both existing prototypes (jtbl design, agent-build-tool) are Python
3. Python's subprocess module handles calling `jq`, `git`, etc.
4. Python is already in the Docker image at zero cost
5. The reference docs in `.claude/reference/` already cover FastAPI best practices

**React handles ALL frontend rendering.** One React app, one build step, one set of UI components shared across plugins.

**Shell scripts for dev workflow only.** `dev.sh` starts both dev servers, `build.sh` builds frontend and packages everything.

### What About PEP 723 (jtbl Standalone)?

Issue #58 specifies jtbl should work as a standalone PEP 723 script (`uv run jtbl.py`). This is compatible with the flat monorepo — the standalone script IS the core logic, and the plugin wrapper simply imports it and adds FastAPI routes:

```python
# dev_toolkit/plugins/jtbl/jtbl.py
# This file IS the PEP 723-compatible standalone script
# It can be run directly: `uv run dev_toolkit/plugins/jtbl/jtbl.py`
# OR imported by the plugin: from dev_toolkit.plugins.jtbl.jtbl import process_json

# /// script
# requires-python = ">=3.10"
# dependencies = ["pandas", "tabulate"]
# ///

def process_json(data, index_query, columns=None, ...):
    """Core jtbl logic — works standalone or as import."""
    ...

if __name__ == "__main__":
    # Standalone CLI mode
    ...
```

```python
# dev_toolkit/plugins/jtbl/routes.py
from .jtbl import process_json
from fastapi import APIRouter

router = APIRouter()

@router.post("/query")
async def query_json(request: JtblQueryRequest):
    result = process_json(request.data, request.index_query, ...)
    return result
```

This dual-mode pattern (standalone script + plugin import) keeps jtbl independently runnable while integrating cleanly into the toolkit.

---

## 8. Relationship to Existing Code

### agent-build-tool (`/workspace/mpulse/agent-build-tool/`)

This existing Python package is a working prototype for what will become the Agent Builder plugin (#60). Key observations:

- **Already uses**: setuptools, Jinja2, PyYAML, python-frontmatter
- **Has**: CLI with build/validate/diff commands, YAML config loading, template rendering
- **Should be migrated into**: `dev_toolkit/plugins/agent_builder/`
- **Migration path**: Copy core logic (config.py, renderer.py, validator.py, differ.py), wrap with plugin manifest and FastAPI routes, add frontend

### Claudio CLI (`/workspace/cli/`)

The existing Claudio CLI is a shell-script-based management tool. The dev-toolkit is a SEPARATE tool, not a replacement:
- **Claudio CLI**: Container management, verification, initialization
- **Dev Toolkit**: Development workspace tools (markdown browser, JSON explorer, etc.)

They coexist. The Claudio CLI manages the container; the dev-toolkit runs inside it.

---

## 9. Recommended pyproject.toml

```toml
[build-system]
requires = ["setuptools>=68.0"]
build-backend = "setuptools.build_meta"

[project]
name = "dev-toolkit"
version = "0.1.0"
description = "Local-first IDE toolkit for agent development in Claudio devcontainers"
requires-python = ">=3.12"
dependencies = [
    # Core framework
    "fastapi>=0.115",
    "uvicorn[standard]>=0.30",
    # Shared plugin dependencies
    "pyyaml>=6.0",
    "watchfiles>=1.0",
    "pydantic>=2.0",
    "jinja2>=3.1",
    "python-frontmatter>=1.1",
]

[project.optional-dependencies]
jtbl = [
    "pandas>=2.0",
    "tabulate>=0.9",
]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=0.24",
    "httpx>=0.27",  # For testing FastAPI
    "ruff>=0.5",
]
all = [
    "dev-toolkit[jtbl]",
    "dev-toolkit[dev]",
]

[project.scripts]
dev-toolkit = "dev_toolkit.__main__:main"

[tool.setuptools.packages.find]
where = ["src"]

[tool.setuptools.package-data]
dev_toolkit = ["static/**/*"]

[tool.pytest.ini_options]
testpaths = ["tests"]
asyncio_mode = "auto"

[tool.ruff]
target-version = "py312"
line-length = 100
```

---

## 10. Decision Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Monorepo structure** | Single-package flat | 4-5 plugins, single artifact, minimal overhead |
| **Package manager** | uv (no workspaces) | Fast, Python-native, no workspace complexity needed |
| **Plugin distribution** | Bundled in Docker image | Zero-setup for users, all first-party |
| **Versioning** | Unified (single version) | Single delivery artifact, no compat matrix |
| **Backend language** | Python (FastAPI) | Already decided, existing prototypes in Python |
| **Frontend** | React (Vite), single app | One build, shared components |
| **Build orchestration** | Makefile / shell scripts | <5 packages, no need for Turbo/Nx |
| **Docker integration** | Single layer in Dockerfile.base | Co-located with existing tooling |
| **jtbl standalone** | Dual-mode (standalone script + plugin import) | PEP 723 compatibility preserved |

---

## 11. Sources

### Monorepo Tooling
- [pnpm Workspaces Documentation](https://pnpm.io/workspaces)
- [Complete Monorepo Guide: pnpm + Workspace + Changesets (2025)](https://jsdev.space/complete-monorepo-guide/)
- [Nx vs Turborepo Comparison](https://www.wisp.blog/blog/nx-vs-turborepo-a-comprehensive-guide-to-monorepo-tools)
- [Why I Chose Turborepo Over Nx](https://dev.to/saswatapal/why-i-chose-turborepo-over-nx-monorepo-performance-without-the-complexity-1afp)

### Python Monorepo / uv Workspaces
- [uv Workspaces Documentation](https://docs.astral.sh/uv/concepts/projects/workspaces/)
- [Python Workspaces (Monorepos) with uv](https://tomasrepcik.dev/blog/2025/2025-10-26-python-workspaces/)
- [una - Build Python monorepos with uv](https://github.com/carderne/una)
- [uv Monorepo Example](https://github.com/JasperHG90/uv-monorepo)

### Plugin Systems
- [Grafana Plugin System Architecture](https://deepwiki.com/grafana/grafana/11-plugin-system)
- [Grafana Plugin Monorepo POC](https://github.com/grafana/plugin-monorepo-poc/blob/main/docker-compose.yaml)
- [Backstage App Structure](https://backstage.spotify.com/learn/standing-up-backstage/standing-up-backstage/3-app-structure/)

### FastAPI Architecture
- [FastAPI Modular Monolith Starter Kit](https://github.com/arctikant/fastapi-modular-monolith-starter-kit)
- [FastAPI Bigger Applications - Multiple Files](https://fastapi.tiangolo.com/tutorial/bigger-applications/)
- [FastAPI in Containers - Docker](https://fastapi.tiangolo.com/deployment/docker/)

### Docker Packaging
- [Grafana Docker Image Documentation](https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/)
- [FastAPI Vertical Monorepo Architecture (LSST)](https://sqr-075.lsst.io/)
