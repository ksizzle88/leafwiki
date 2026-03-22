# Web Server Framework Comparison for Dev Toolkit

**Research Date**: 2026-03-13
**Context**: Claudio Dev Toolkit (Issue #55/#56) needs a backend server framework for a localhost dev tool server running inside Docker devcontainers.

---

## Environment Constraints

- **Claudio base image** already includes: Node.js 22, Python 3.12, npm 10.9
- **Target**: Localhost-only dev tool server, no auth, 4-5 plugin tools
- **Must support**: Hot reload, WebSockets, static file serving, plugin route groups
- **Docker**: Runs inside devcontainers; startup time and image size impact DX

---

## Framework Comparison Table

| Criteria | FastAPI (Python) | Starlette (Python) | Flask (Python) | Express (Node) | Fastify (Node) | Hono (Node) | Go (Gin) | Rust (Axum) |
|---|---|---|---|---|---|---|---|---|
| **Startup time** | ~500ms-2s (uvicorn) | ~300ms-1s | ~200ms-500ms | ~100-300ms | ~100-300ms | ~50-200ms | ~10-50ms | ~5-20ms |
| **Req/sec (hello world)** | ~15-25k | ~20-30k | ~5-10k | ~15-25k | ~70-80k | ~50-70k | ~100k+ | ~150k+ |
| **Hot reload** | Native (`fastapi dev` / `uvicorn --reload`) | `uvicorn --reload` | `FLASK_DEBUG=1` | nodemon / tsx watch | nodemon / tsx watch | nodemon / tsx watch | Air (3rd party) | cargo-watch (3rd party) |
| **WebSocket support** | Native (built-in) | Native (built-in) | Flask-SocketIO (3rd party) | ws / socket.io (3rd party) | @fastify/websocket (official plugin) | @hono/node-ws (official adapter) | gorilla/websocket (3rd party) | axum::extract::ws (built-in) |
| **Static file serving** | StaticFiles mount (Starlette) | StaticFiles (built-in) | send_from_directory | express.static (built-in) | @fastify/static (official plugin) | @hono/node-server/serve-static | http.FileServer (stdlib) | tower-http::services::ServeDir |
| **Plugin/route grouping** | APIRouter + mount sub-apps | Router + mount | Blueprints | express.Router() | register() + encapsulated plugins | app.route() + sub-apps | gin.Group() | Router::nest() |
| **Type safety** | Pydantic v2 (excellent) | Manual | Manual | TypeScript (opt-in) | JSON Schema + TypeScript | TypeScript-first | Go types (strong) | Rust types (strongest) |
| **Ecosystem** | Large (Python ML/data) | Small (niche) | Huge (Python web) | Massive | Large (growing) | Growing (newer) | Large (Go) | Growing (Rust) |
| **Container footprint** | 0 MB (Python already in image) | 0 MB (Python already in image) | 0 MB (Python already in image) | ~5-15 MB (npm packages) | ~15-25 MB (npm packages) | ~2-5 MB (minimal deps) | +200-500 MB (Go toolchain) | +500MB+ (Rust toolchain) |
| **Dev familiarity (Claudio)** | High (reference docs exist) | Medium | High | High (Node in image) | Medium | Low | None | None |

---

## Detailed Analysis by Framework

### 1. FastAPI (Python) -- RECOMMENDED

**Strengths:**
- **Native to the stack**: Python 3.12 already in the Claudio base image; zero additional runtime footprint
- **Best plugin architecture for this use case**: Sub-application mounting via `app.mount("/tool-name", tool_app)` maps perfectly to the "each tool is a plugin" requirement. Each plugin is a complete FastAPI sub-application with its own routes, static files, and OpenAPI docs
- **WebSocket support is first-class**: Built on Starlette's ASGI WebSocket handling; no third-party library needed
- **Auto-generated OpenAPI docs**: Each plugin gets interactive API docs at `/docs` for free -- valuable for a dev tool
- **Pydantic v2 validation**: Strong type safety and data validation without TypeScript compilation step
- **Hot reload**: `fastapi dev` or `uvicorn --reload` with configurable watch directories; works out of the box
- **Existing reference docs**: Claudio already has `.claude/reference/fastapi-best-practices.md` with project structure patterns
- **Static files**: `StaticFiles` mount works per-plugin, so each tool can serve its own frontend assets
- **Dependency injection**: Built-in DI system allows plugins to declare dependencies on shared services (e.g., file watchers)

**Weaknesses:**
- **Startup time**: ~500ms-2s is slower than Node.js alternatives. For a dev tool that starts once and runs continuously, this is acceptable but noticeable
- **Frontend hot reload**: uvicorn only reloads Python modules; static/frontend files need a separate watcher (e.g., a lightweight Vite dev server or livereload WebSocket)
- **Pydantic v2 import time**: Can add 1-3s to cold start for apps with many models. Mitigated by lazy imports
- **Async complexity**: While async is powerful, it adds complexity vs synchronous Flask for simple CRUD operations

**Plugin Architecture Pattern:**
```python
# main.py
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

app = FastAPI(title="Dev Toolkit")

# Auto-discover and mount plugins
from plugins.markdown_browser import app as markdown_app
from plugins.jtbl import app as jtbl_app

app.mount("/tools/markdown", markdown_app)
app.mount("/tools/jtbl", jtbl_app)
app.mount("/static", StaticFiles(directory="static"), name="static")
```

### 2. Fastify (Node.js) -- STRONG ALTERNATIVE

**Strengths:**
- **Best plugin system of any framework evaluated**: Encapsulated plugin contexts with `register()`, decorators, and a DAG-based inheritance model. Plugins are truly isolated -- one crashing does not affect others
- **Performance leader (Node.js)**: 70-80k req/sec, 2-3x faster than Express
- **JSON Schema validation**: Built-in schema-based validation similar to Pydantic
- **Official plugin ecosystem**: @fastify/websocket, @fastify/static, @fastify/cors are well-maintained
- **TypeScript support**: First-class with typed route handlers and schema inference

**Weaknesses:**
- **Larger npm footprint**: ~15-25MB of node_modules added to image. Not terrible but non-zero
- **Plugin complexity**: The encapsulation model, while powerful, has a learning curve (fastify-plugin to break encapsulation)
- **Hot reload is bolted on**: Requires nodemon/tsx-watch; not as seamless as `uvicorn --reload`
- **No auto-generated API docs**: Needs @fastify/swagger plugin (additional setup vs FastAPI's built-in)
- **Vite integration fragile**: Some compatibility issues reported between @fastify/websocket and @fastify/vite

### 3. Hono (Node.js) -- LIGHTWEIGHT OPTION

**Strengths:**
- **Ultra-lightweight**: ~14kB, zero dependencies. Minimal container footprint (~2-5MB installed)
- **Fastest cold start** of all Node.js options
- **TypeScript-first**: Designed for TypeScript from the ground up
- **Multi-runtime**: Works on Node, Deno, Bun -- future flexibility
- **Clean routing API**: `app.route()` for grouped routes is ergonomic

**Weaknesses:**
- **Immature ecosystem**: Fewer plugins and middleware than Express/Fastify
- **WebSocket support requires adapter**: @hono/node-ws works but is less battle-tested
- **Static file serving**: @hono/node-server/serve-static works but lacks advanced features
- **No built-in plugin encapsulation**: Route groups exist but no isolation model like Fastify's
- **Newer framework**: Less production experience, smaller community for troubleshooting
- **No developer familiarity in Claudio stack**: Would be a new technology to learn

### 4. Express (Node.js) -- SAFE BUT DATED

**Strengths:**
- **Most battle-tested**: 14+ years, massive ecosystem, everyone knows it
- **Simple mental model**: Middleware chain is easy to understand
- **express.Router()**: Clean route grouping per plugin
- **express.static()**: Built-in static file serving

**Weaknesses:**
- **Performance**: 15-25k req/sec, slowest of the Node.js options
- **No native WebSocket**: Requires ws or socket.io
- **No built-in validation**: Need express-validator or similar
- **No TypeScript-first design**: Types are bolted on via @types/express
- **Synchronous by default**: Callback/promise patterns less elegant than async/await-native alternatives
- **Maintainer situation**: Express 5 has been in development for years

### 5. Starlette (Python) -- TOO MINIMAL

**Strengths:**
- Near-zero overhead; FastAPI is built on it
- Same ASGI foundation, slightly faster for raw routing

**Weaknesses:**
- No auto-validation, no OpenAPI docs, no dependency injection
- Essentially FastAPI minus its best features. For a dev tool that benefits from auto-docs and validation, Starlette offers pain without gain

**Verdict**: Use FastAPI instead. The overhead is negligible and the DX benefits are substantial.

### 6. Flask (Python) -- WRONG PARADIGM

**Strengths:**
- Simple, familiar, huge ecosystem
- Blueprints for route grouping

**Weaknesses:**
- **Synchronous/WSGI**: No native async, no native WebSocket. This is a dealbreaker for the live-update/file-watching requirement
- **Flask-SocketIO**: Works but adds complexity and a Gevent/Eventlet dependency
- **No auto API docs**: Needs flask-restx or apiflask

**Verdict**: Flask is the wrong choice for a real-time dev tool. WebSocket and async are core requirements, not nice-to-haves.

### 7. Go (Gin/Echo) -- OVERKILL

**Strengths:**
- Fastest startup (10-50ms), highest throughput (100k+ req/sec)
- Single static binary, tiny Docker images (~10-50MB)
- Strong typing

**Weaknesses:**
- **Go toolchain not in base image**: Would add 200-500MB to Docker image or require a multi-stage build with a separate build step
- **No hot reload**: Air exists but is third-party and less reliable than uvicorn --reload or nodemon
- **Compilation step**: Every code change requires a recompile. For a rapid-iteration dev tool, this slows the feedback loop
- **No developer familiarity**: Claudio's stack is Python + Node.js. Adding Go introduces a third language

**Verdict**: The performance is irrelevant for a localhost dev tool. The DX cost of adding Go to the stack outweighs any benefits.

### 8. Rust (Axum) -- MASSIVE OVERKILL

**Strengths:**
- Best raw performance of anything evaluated
- Smallest runtime binary (~5-20MB)
- Memory safety guarantees

**Weaknesses:**
- **Rust toolchain adds 500MB+ to Docker image**
- **Compile times**: 30s-2min for incremental builds. Hot reload via cargo-watch is slow
- **Steep learning curve**: Async Rust with lifetimes is complex
- **No Rust anywhere in the Claudio stack**

**Verdict**: Axum is exceptional for high-performance production APIs. It is completely wrong for a localhost dev tool in a Python/Node.js stack.

---

## Performance Context: Why It Doesn't Matter Much Here

This server is:
- **Localhost only**: Zero network latency
- **Single user**: No concurrent load concerns
- **Dev tool**: Users interact at human speed (clicks, not API calls)
- **Long-running**: Starts once, runs for hours

The difference between 15k and 150k req/sec is irrelevant. What matters is:
1. **Startup time**: Sub-second preferred (all candidates except Go/Rust compilation achieve this)
2. **Hot reload speed**: How fast do file changes reflect? (Python/Node both sub-second with watch mode)
3. **Developer velocity**: How fast can new plugins be built? (FastAPI and Fastify lead here)

---

## Recommendation: FastAPI

### Primary: FastAPI with Uvicorn

**Rationale:**

1. **Zero additional container footprint**: Python 3.12 is already in the Claudio base image. `pip install fastapi uvicorn` adds ~20MB of Python packages vs ~15-25MB of node_modules for Fastify. But critically, the Python runtime is already there -- the marginal cost is packages only.

2. **Best plugin model for this use case**: FastAPI's sub-application mounting (`app.mount()`) maps 1:1 to the requirement that "each tool is a plugin with routes, frontend component, nav entry." Each plugin is a complete FastAPI app with its own routes, static files, WebSocket endpoints, and auto-generated API docs.

3. **WebSocket is built-in**: No plugins needed. Starlette's ASGI WebSocket handling is production-grade and handles the file-watching/live-updates requirement natively.

4. **Auto-generated API docs per plugin**: Every mounted sub-application gets its own `/docs` endpoint. For a dev tool, this is invaluable -- developers can explore each tool's API interactively.

5. **Existing team knowledge**: Claudio already has `fastapi-best-practices.md` reference documentation, indicating FastAPI is a known quantity in this project's ecosystem.

6. **Dependency injection**: FastAPI's `Depends()` system allows plugins to declare dependencies on shared services (file watchers, WebSocket broadcasters, database connections) without tight coupling.

7. **Hot reload works**: `uvicorn --reload --reload-dir=plugins/` watches plugin directories. For frontend hot reload, a lightweight livereload WebSocket injected into pages handles the gap.

### Backup: Fastify

If the team prefers a Node.js-first approach, Fastify is the clear second choice. Its encapsulated plugin system is arguably better than FastAPI's for isolation guarantees, and its performance is excellent. The main reason FastAPI wins is the zero-runtime-cost advantage (Python is already installed) and the existing FastAPI best practices documentation in the Claudio reference library.

### What NOT to Choose

- **Express**: Slower, no native WebSocket, no validation. Fastify is strictly better for this use case.
- **Hono**: Too new, too minimal. Good for edge/serverless, wrong for a plugin-heavy dev tool server.
- **Flask**: No async, no native WebSocket. Wrong paradigm for real-time dev tools.
- **Go/Rust**: Wrong language for this stack. The performance benefits are irrelevant for a single-user localhost tool.

---

## Recommended Stack Summary

| Component | Choice | Rationale |
|---|---|---|
| **Backend framework** | FastAPI 0.115+ | Sub-app mounting, WebSocket, auto-docs, zero runtime cost |
| **ASGI server** | Uvicorn | Native hot reload, async support |
| **Validation** | Pydantic v2 | Built into FastAPI, type-safe schemas |
| **WebSocket** | Starlette WebSocket (via FastAPI) | Built-in, no dependencies |
| **Static files** | Starlette StaticFiles | Per-plugin static mounts |
| **Frontend** | To be decided separately | HTMX+Alpine.js or React/Svelte (separate research topic) |
| **Hot reload (backend)** | uvicorn --reload | Watches Python files natively |
| **Hot reload (frontend)** | livereload WebSocket or Vite proxy | Separate concern, lightweight |
| **Process manager (dev)** | Single uvicorn process | Keep it simple for dev |

---

## Installation Footprint Estimate

```bash
# Added to Dockerfile.base or plugin layer:
pip install fastapi uvicorn[standard] websockets python-multipart

# Approximate size: ~20-25MB
# No new runtime (Python 3.12 already installed)
# No new build tools needed
```

Compare with Node.js alternative:
```bash
npm install fastify @fastify/websocket @fastify/static @fastify/cors

# Approximate size: ~15-25MB of node_modules
# Node.js runtime already installed, but TypeScript compilation adds complexity
```

---

## Open Questions for the Planner

1. **Frontend framework**: This research covers the backend only. The frontend choice (HTMX vs React vs Svelte) is a separate decision that affects the hot reload strategy.
2. **Process management**: Should the dev toolkit be a single process or should each plugin be independently restartable?
3. **Port configuration**: The issue mentions port 8080 as default. Should plugins have sub-paths (`/tools/markdown`) or separate ports?
4. **Auto-start mechanism**: `postCreateCommand` in devcontainer.json vs docker-compose service vs manual `dev-toolkit serve`?
