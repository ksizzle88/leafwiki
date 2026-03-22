# Hot Reload & Live Refresh Patterns for Dev Toolkit

**Research Date**: 2026-03-13
**Context**: Claudio Dev Toolkit (Epic #55, Core Framework #56) needs hot reload for both backend (Python/FastAPI) and frontend (React/Vite) running inside Docker devcontainers on WSL2.

---

## 1. Executive Summary

**Recommended Architecture: Vite Dev Server (frontend HMR) + uvicorn --reload (backend) + Vite proxy to FastAPI**

This is the standard full-stack pattern used by the FastAPI + React ecosystem. Vite handles frontend HMR with ~50ms latency via WebSocket. Uvicorn handles backend reload with ~300-500ms latency via process restart. The Vite dev server proxies `/api/*` requests to the FastAPI backend, avoiding CORS issues and providing a single development URL. For plugin hot reload specifically, use `importlib.reload()` with a file watcher to dynamically load/unload plugins without full server restart.

---

## 2. Backend Hot Reload

### 2.1 uvicorn --reload (RECOMMENDED for Development)

**How it works**: Uvicorn's `--reload` flag uses the `watchfiles` library (Rust-based, backed by the `notify` crate) to monitor the filesystem via inotify (Linux). When a `.py` file changes, uvicorn kills the worker process and spawns a new one.

**Latency profile**:
- File change detection: ~50-100ms (inotify) or ~250ms (polling interval, the default check delay)
- Process restart: ~300-500ms for a small FastAPI app (Python interpreter restart + imports)
- Total save-to-ready: **~500ms-1s** for a typical dev toolkit-sized app

**Configuration**:
```bash
# Standard development mode
uvicorn main:app --reload --reload-dir /workspace/dev-toolkit/backend

# FastAPI 0.100+ shorthand
fastapi dev main.py

# With explicit file patterns
uvicorn main:app --reload --reload-include "*.py" --reload-include "*.yaml"
```

**Strengths**:
- Zero-config: comes free with `uvicorn[standard]` (which includes `watchfiles`)
- Battle-tested: the standard Python ASGI reload mechanism
- Configurable watch directories and file patterns (critical for limiting scope)
- Works well with FastAPI's dependency injection (state is re-initialized cleanly)

**Weaknesses**:
- Full process restart: re-imports ALL modules, including heavy dependencies
- Cold start penalty grows with app size (Pydantic v2 models add 1-3s import time)
- Only watches Python files by default; template/config changes need explicit `--reload-include`

### 2.2 uvicorn-hmr (EMERGING — Worth Watching)

**How it works**: Drop-in replacement for `uvicorn --reload`. Uses the `hmr` Python library for fine-grained module reloading. The main process never restarts — only changed modules and their dependents are re-executed.

**Key advantage**: Variable-level fine-grained reloading. The codebase behaves like a dependency graph; when you modify a file, HMR only re-runs affected modules from the modified file up to the entry point.

**Usage**:
```bash
# Drop-in replacement
uvicorn-hmr main:app

# With browser auto-refresh
uvicorn-hmr main:app --refresh

# With terminal clear
uvicorn-hmr main:app --clear
```

**Latency profile**:
- No process restart overhead (stays in same process)
- Re-executes only changed modules
- Estimated: **~100-300ms** for typical changes (no published benchmarks)

**Strengths**:
- Much faster than full restart for large apps
- Watches non-Python files too (templates, configs)
- Optional `--refresh` flag auto-reloads browser pages via `fastapi-reloader`
- Preserves application state across reloads

**Weaknesses**:
- Relatively new library (pypi shows recent releases)
- Module reloading in Python has inherent edge cases (dangling references, class instances, closures)
- Not thread-safe (uses `importlib.reload()` under the hood)
- Limited community testing compared to standard uvicorn --reload

**Verdict**: Monitor for maturity. For v1 of the Dev Toolkit, stick with standard `uvicorn --reload`. Consider uvicorn-hmr for v2 if the cold restart penalty becomes painful.

### 2.3 jurigged (Hot Patching)

**How it works**: Modifies Python code objects in-place without restart. Functions are swapped atomically — running invocations continue with old code, new invocations use new code.

**Usage**:
```bash
# Run with hot patching enabled
jurigged -v script.py

# Loop on a specific function (re-run on every change)
jurigged --loop my_function script.py
```

**Latency profile**: Near-instant (~10-50ms) since no module reimport occurs.

**Strengths**:
- Fastest possible Python hot reload
- Preserves ALL state (no restart, no reimport)
- Great for iterative development of specific functions

**Weaknesses**:
- Cannot handle structural changes (new classes, changed module-level code)
- Not designed for ASGI server integration
- Edge cases with closures, decorators, and metaclasses
- Not production-safe; strictly a development convenience

**Verdict**: Not suitable as the primary reload mechanism for a web server. Could be useful for plugin development workflows where you want to hot-patch individual handler functions.

### 2.4 watchfiles (The Underlying Watcher)

`watchfiles` is the Rust-based file watching library used by uvicorn, uvicorn-hmr, and available as a standalone tool. It wraps the Rust `notify` crate.

**Performance characteristics**:
- Uses inotify on Linux (native kernel file event API)
- Debounce: default 50ms (groups rapid changes)
- GIL released during sleep iterations (doesn't block Python)
- Falls back to polling when inotify is unavailable

**Docker/Container behavior**:
- **Linux host → Linux container**: inotify works natively via bind mounts on the same filesystem
- **WSL2 → Docker container**: inotify works IF the source is on the Linux filesystem (not `/mnt/c/`)
- **macOS → Docker**: inotify via VirtioFS works; gRPC FUSE requires polling fallback
- **Windows → Docker**: inotify does NOT work; must use polling

**Forcing polling** (when inotify fails):
```bash
export WATCHFILES_FORCE_POLLING=true
# Or in Python:
# watchfiles.watch(..., force_polling=True)
```

### 2.5 General-Purpose File Watchers

| Tool | Language | Mechanism | Debounce | Use Case |
|------|----------|-----------|----------|----------|
| **watchexec** | Rust | notify (inotify/FSEvents) | 50ms default | Run arbitrary command on file change |
| **entr** | C | kqueue/inotify | None (immediate) | Pipe file list, run command |
| **nodemon** | Node.js | chokidar (inotify/polling) | configurable | Node.js process restarter |
| **tsx watch** | Node.js | native Node fs.watch | ~100ms | TypeScript execution with watch |

**watchexec** is the best general-purpose option: it auto-ignores `.git/`, `node_modules/`, debounces by default, and handles process restart properly with `-r`. Useful for restarting non-Python processes (e.g., a sidecar service).

**entr** is the simplest: `find . -name "*.py" | entr -r uvicorn main:app`. But it requires piping a file list and doesn't handle new files.

---

## 3. Frontend Hot Reload (HMR)

### 3.1 Vite HMR (RECOMMENDED)

**Architecture**:
1. Vite dev server watches source files via chokidar (inotify/FSEvents)
2. On file change, Vite traverses its in-memory **module graph** to find all affected modules
3. It looks for **HMR boundaries** — modules that call `import.meta.hot.accept()`
4. If a boundary is found, only those modules are sent to the browser via WebSocket
5. The browser dynamically imports the updated modules and runs acceptance callbacks
6. React Fast Refresh integrates here: component state is preserved, only the component tree re-renders

**WebSocket Protocol** (JSON over WS):
```
Server → Client: { type: "update", updates: [{ type: "js-update", path: "/src/App.tsx", ... }] }
Server → Client: { type: "full-reload" }  // When no HMR boundary found
Server → Client: { type: "connected" }     // Initial handshake
Server → Client: { type: "error", err: { ... } }  // Compilation error overlay
```

**Latency profile**:
- File detection: ~10-50ms (chokidar/inotify)
- Module graph traversal + transform: ~10-30ms
- WebSocket transmission: ~1-5ms (localhost)
- Browser module re-import + React reconciliation: ~10-30ms
- **Total: ~30-100ms save-to-visible-change** (typically quoted as ~50ms)

**Key optimization**: CSS updates bypass JavaScript entirely, directly updating `<link>` tags for instant visual feedback.

**Configuration for Dev Toolkit** (`vite.config.ts`):
```typescript
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
      '/ws': {
        target: 'ws://localhost:8080',
        ws: true,
      },
    },
  },
});
```

### 3.2 Webpack HMR

**How it works**: Similar module graph approach but with heavier bundling. The entire dependency chunk is re-bundled on change.

**Latency**: ~200ms-2s depending on project size (significantly slower than Vite).

**Verdict**: Legacy. No reason to use over Vite for a new project.

### 3.3 Parcel HMR

**How it works**: Zero-config bundler with built-in HMR. Uses a Rust-based transformer (SWC).

**Latency**: ~50-200ms (competitive with Vite for small projects).

**Verdict**: Viable but smaller ecosystem. Vite is the community standard.

### 3.4 HTMX + Server-Sent Events

**How it works**: Server pushes HTML fragments to the browser via SSE. The browser swaps DOM elements in-place using `hx-swap`. No client-side JavaScript framework needed.

**Pattern for live reload**:
```html
<!-- Listen for file change events -->
<div hx-ext="sse" sse-connect="/events/reload">
  <div sse-swap="content-update">
    <!-- Server pushes new HTML here -->
  </div>
</div>
```

**Latency**: ~100-300ms (server detects change, re-renders template, pushes via SSE).

**Strengths**:
- No build step, no JavaScript bundler
- Server-driven: backend controls all UI updates
- Very simple mental model

**Weaknesses**:
- Full HTML re-render per change (no fine-grained component updates)
- Cannot handle complex interactive UIs (DAG editors, data tables, code editors)
- No component state preservation
- Doesn't scale to the rich UI requirements of the Dev Toolkit

**Verdict**: Not suitable for the Dev Toolkit's requirements (rich interactive components). HTMX is excellent for simpler tools but the toolkit needs React's component ecosystem.

### 3.5 LiveReload / BrowserSync

**How it works**: File watcher triggers full page reload via WebSocket injection or proxy server.

**BrowserSync** additionally syncs scroll position, form inputs, and clicks across multiple browsers/devices.

**Latency**: ~500ms-2s (full page reload, all state lost).

**Verdict**: Too primitive. Vite HMR is strictly superior for React development.

---

## 4. Full-Stack Hot Reload Patterns

### 4.1 Separate Servers with Vite Proxy (RECOMMENDED)

```
┌──────────────┐         ┌──────────────┐
│  Vite Dev    │ ──/api──▶  FastAPI      │
│  Server      │         │  (uvicorn)   │
│  :3000       │         │  :8080       │
│              │◀──WS────│              │
│  React HMR   │         │  Backend API  │
└──────────────┘         └──────────────┘
      │                        │
      │  HMR WebSocket         │  File watcher (watchfiles)
      ▼                        ▼
   Browser              Python files
```

**How it works**:
1. **Vite dev server** runs on port 3000, serves React app with HMR
2. **FastAPI** runs on port 8080 with `uvicorn --reload`
3. Vite proxies `/api/*` requests to FastAPI (configured in `vite.config.ts`)
4. Browser connects to Vite's HMR WebSocket for frontend updates
5. Backend changes restart uvicorn; frontend changes hot-patch via Vite

**Startup command** (using a process manager or two terminals):
```bash
# Terminal 1: Backend
uvicorn dev_toolkit.main:app --reload --reload-dir backend/ --port 8080

# Terminal 2: Frontend
cd frontend && npm run dev  # vite --port 3000
```

Or with a single command using a process manager:
```bash
# Using concurrently (npm package)
npx concurrently \
  "uvicorn dev_toolkit.main:app --reload --port 8080" \
  "cd frontend && vite --port 3000"
```

**Latency**:
- Frontend change: ~50ms (Vite HMR)
- Backend change: ~500ms-1s (uvicorn restart)
- Both: independent, no interference

**Strengths**:
- Industry standard pattern (used by every FastAPI + React tutorial)
- Frontend and backend reload independently
- No CORS issues (Vite proxy makes everything same-origin)
- In production, just build frontend to static files and serve from FastAPI

**Weaknesses**:
- Two processes to manage
- Two ports (though only port 3000 is user-facing in dev)

### 4.2 Single Server Serves Everything

**How it works**: FastAPI serves both the API and frontend static files. In development, use `fastapi-reloader` to inject a script that auto-refreshes the browser when Python files change.

**Verdict**: Works for simple apps but loses Vite's sub-50ms HMR for frontend changes. Not recommended when the frontend is a React SPA.

### 4.3 WebSocket Bridge (Custom)

**How it works**: Backend watches files and pushes custom events via WebSocket. Frontend subscribes and updates accordingly.

**Use case**: Plugin hot reload notifications. When a plugin's Python files change and uvicorn restarts, the frontend needs to know to re-fetch plugin metadata.

**Implementation sketch**:
```python
# Backend: FastAPI WebSocket endpoint
@app.websocket("/ws/reload")
async def reload_ws(websocket: WebSocket):
    await websocket.accept()
    # After uvicorn restart, clients reconnect automatically
    await websocket.send_json({"type": "server_restarted", "timestamp": time.time()})
    # Keep alive
    while True:
        await asyncio.sleep(30)
        await websocket.send_json({"type": "ping"})
```

```typescript
// Frontend: Auto-reconnecting WebSocket
const ws = new WebSocket('ws://localhost:3000/ws/reload');
ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  if (data.type === 'server_restarted') {
    // Refetch plugin list, invalidate caches
    queryClient.invalidateQueries(['plugins']);
  }
};
```

---

## 5. Plugin Hot Reload

This is the most interesting design challenge for the Dev Toolkit. Plugins should be addable/removable without restarting the server.

### 5.1 File-Convention Plugin Discovery

**Pattern**: Scan a `plugins/` directory on startup. Each subdirectory with a `__init__.py` and `plugin.py` is auto-registered.

```
dev-toolkit/
  plugins/
    markdown-browser/
      __init__.py
      plugin.py        # Defines routes, frontend entry
      frontend/        # React components
    jtbl/
      __init__.py
      plugin.py
      frontend/
```

**Hot reload via uvicorn --reload**: When any file in `plugins/` changes, uvicorn restarts and re-scans the directory. New plugins are discovered; removed plugins are gone.

**Latency**: Same as backend hot reload (~500ms-1s).

**Strengths**: Simple, reliable, no edge cases.
**Weaknesses**: Full server restart for any plugin change.

### 5.2 Dynamic Module Loading (importlib)

**Pattern**: Use `importlib.import_module()` and `importlib.reload()` to load/unload plugins at runtime without restarting the server.

```python
import importlib
import sys

def load_plugin(name: str):
    module = importlib.import_module(f"plugins.{name}.plugin")
    return module.create_app()

def reload_plugin(name: str):
    module_name = f"plugins.{name}.plugin"
    if module_name in sys.modules:
        module = importlib.reload(sys.modules[module_name])
        return module.create_app()
    return load_plugin(name)
```

**Strengths**:
- No server restart
- Other plugins keep running
- Near-instant reload (~50-100ms)

**Weaknesses**:
- `importlib.reload()` is NOT thread-safe
- Dangling references: existing route handlers may still reference old module objects
- Class instances created before reload don't update
- FastAPI/Starlette route tables are not designed for runtime modification

**Verdict**: Too fragile for route-level hot reload. But useful for reloading plugin **configuration** and **data transformations** (non-route code).

### 5.3 Recommended Plugin Reload Strategy

**Use uvicorn --reload for development** (simple, reliable, ~500ms-1s per change). The full restart approach is the most robust:

1. File watcher detects change in `plugins/`
2. Uvicorn restarts the process
3. Plugin discovery re-scans the directory
4. All plugins are re-registered
5. Frontend receives `server_restarted` WebSocket event
6. Frontend re-fetches plugin manifest and updates navigation

For **frontend plugin assets**: Each plugin's `frontend/` directory is watched by Vite. Changes trigger HMR updates with ~50ms latency. No server restart needed.

---

## 6. Container-Specific Considerations

### 6.1 File Watching in Docker (Claudio Environment)

The Claudio devcontainer runs on WSL2 (Linux 6.6.x kernel) with bind mounts from the WSL filesystem.

**Current mount configuration** (from `devcontainer.local.json`):
```json
"source=/home/kschepis/workspaces/...,target=/workspace/...,type=bind,consistency=cached"
```

**inotify behavior by mount type**:

| Source → Target | inotify Works? | Notes |
|---|---|---|
| WSL2 filesystem → container | **YES** | Native bind mount, same kernel, inotify events propagate |
| Windows `/mnt/c/` → container | **NO** | Cross-filesystem, no inotify. Must use polling. |
| Docker volume → container | **YES** | Same filesystem |
| macOS (VirtioFS) → container | **YES** | VirtioFS supports inotify relay |
| macOS (gRPC FUSE) → container | **NO** | Must use polling |

**For Claudio**: The workspace is mounted from the WSL2 Linux filesystem (`/home/kschepis/...`), so **inotify works natively**. No polling fallback needed.

### 6.2 Performance Implications

**Watch scope matters**: watchfiles/chokidar watch recursively. In a container with many files (node_modules, .git, Python venvs), unconstrained watching causes:
- High inotify watch count (Linux default: 8192, may need increase)
- CPU overhead from event processing
- Memory overhead from watch handles

**Mitigations**:
```bash
# Increase inotify watch limit (in container or WSL2)
echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Uvicorn: watch only relevant directories
uvicorn main:app --reload --reload-dir /workspace/dev-toolkit/backend

# Vite: exclude heavy directories (automatic by default for node_modules)
# vite.config.ts server.watch.ignored already excludes node_modules
```

### 6.3 Docker `cached` Mount Mode

The `consistency=cached` flag in the devcontainer mount config means:
- Host writes propagate to container with slight delay (acceptable)
- Container writes propagate to host immediately
- inotify events are still delivered (cached doesn't affect event delivery)
- Slightly better performance than `consistent` mode for read-heavy workloads

This is the correct setting for development; no changes needed.

### 6.4 Port Forwarding

The devcontainer already forwards ports 8080 and 8081. For the recommended two-server setup:
- Port 8080: FastAPI backend
- Port 3000 (add to `forwardPorts`): Vite dev server (user-facing in development)

In production, only port 8080 is needed (FastAPI serves built static files).

---

## 7. Latency Comparison Summary

| Approach | Save-to-Visible Latency | State Preserved? | Complexity |
|---|---|---|---|
| **Vite HMR (frontend)** | ~30-100ms | Yes (React Fast Refresh) | Low (built-in) |
| **uvicorn --reload (backend)** | ~500ms-1s | No (full restart) | Low (built-in) |
| **uvicorn-hmr (backend)** | ~100-300ms (est.) | Partial (module-level) | Low (drop-in) |
| **jurigged (backend)** | ~10-50ms | Yes (in-place patch) | Medium (integration) |
| **importlib.reload (plugins)** | ~50-100ms | Partial (module only) | High (edge cases) |
| **HTMX + SSE (frontend)** | ~100-300ms | No (full re-render) | Low |
| **BrowserSync (frontend)** | ~500ms-2s | No (full page reload) | Low |
| **Webpack HMR (frontend)** | ~200ms-2s | Yes | Medium |

---

## 8. Recommended Architecture for Dev Toolkit

### Development Mode

```
┌─────────────────────────────────────────────────┐
│                 Docker Container                 │
│                                                  │
│  ┌──────────────┐        ┌──────────────┐       │
│  │  Vite Dev    │──/api──▶  FastAPI      │       │
│  │  Server      │        │  (uvicorn)   │       │
│  │  :3000       │        │  :8080       │       │
│  │              │◀──WS───│              │       │
│  │  React HMR   │        │  /ws/reload  │       │
│  └──────┬───────┘        └──────┬───────┘       │
│         │                       │                │
│    chokidar                watchfiles            │
│    (inotify)               (inotify)             │
│         │                       │                │
│  frontend/src/           backend/plugins/         │
│  *.tsx, *.css             *.py                    │
│                                                  │
└─────────────────────────────────────────────────┘
```

**Single startup command**:
```bash
dev-toolkit serve  # Starts both Vite and uvicorn, uses concurrently or a Makefile
```

### Production Mode

```
┌─────────────────────────────┐
│      Docker Container       │
│                             │
│  ┌───────────────────────┐  │
│  │  FastAPI (uvicorn)    │  │
│  │  :8080                │  │
│  │                       │  │
│  │  /api/* → routes      │  │
│  │  /* → static files    │  │
│  │  (Vite build output)  │  │
│  └───────────────────────┘  │
│                             │
└─────────────────────────────┘
```

**Build step**: `vite build` outputs to `frontend/dist/`, FastAPI serves it via `StaticFiles`.

### Key Design Decisions

1. **Two servers in dev, one in prod**: Vite dev server provides HMR in development; in production, pre-built static files are served by FastAPI. This is the standard pattern.

2. **Vite proxy eliminates CORS**: All requests go through port 3000 in development. The browser sees a single origin.

3. **uvicorn --reload for backend**: Simple, reliable, well-tested. Upgrade to uvicorn-hmr later if restart penalty becomes an issue.

4. **Plugin discovery via directory convention**: Drop a module in `plugins/`, it's auto-registered on next restart. No runtime dynamic loading needed for v1.

5. **WebSocket bridge for reload notification**: After uvicorn restarts, the frontend auto-reconnects and refetches plugin metadata. This handles the "backend changed" → "frontend updates" flow.

6. **inotify works in Claudio**: WSL2 Linux filesystem mounts propagate inotify events natively. No polling fallback needed. Increase `fs.inotify.max_user_watches` to 524288 in the base image.

7. **Watch scope restriction**: Both uvicorn and Vite should watch only their respective source directories, not the entire `/workspace`. This prevents CPU waste from watching `node_modules`, `.git`, etc.

---

## 9. Open Questions for the Planner

1. **Process manager**: Should `dev-toolkit serve` use `concurrently`, `overmind`, `honcho`, a Makefile, or a custom script to manage the two dev servers?

2. **Port allocation**: Is port 3000 (Vite) + 8080 (FastAPI) acceptable, or should we use a single port with a reverse proxy?

3. **Plugin frontend**: Should each plugin bundle its own React components (loaded via dynamic `import()`), or should all plugin frontends be part of a single Vite build?

4. **inotify limit**: Should we bake `fs.inotify.max_user_watches=524288` into the Dockerfile.base, or handle it in the entrypoint script?

5. **Auto-start**: Should the dev toolkit auto-start in development mode via `postCreateCommand`, or require explicit `dev-toolkit serve`?

---

## 10. Sources

- [Uvicorn Settings (reload configuration)](https://uvicorn.dev/settings/)
- [Vite HMR API](https://vite.dev/guide/api-hmr)
- [Vite HMR Architecture (DeepWiki)](https://deepwiki.com/vitejs/vite/3.3-hot-module-replacement-(hmr))
- [Vite Backend Integration](https://vite.dev/guide/backend-integration)
- [watchfiles (Rust-based Python file watcher)](https://github.com/samuelcolvin/watchfiles)
- [uvicorn-hmr (Fine-grained Python HMR)](https://pypi.org/project/uvicorn-hmr/)
- [jurigged (Python hot patching)](https://github.com/breuleux/jurigged)
- [watchexec (Rust file watcher CLI)](https://tech.stonecharioteer.com/posts/2025/til-watchexec/)
- [Docker file watching issues](https://syntackle.com/blog/the-issue-of-watching-file-changes-in-docker/)
- [WSL2 Docker best practices](https://docs.docker.com/desktop/features/wsl/best-practices/)
- [HTMX SSE Extension](https://htmx.org/extensions/sse/)
- [FastAPI + React + Vite full-stack pattern](https://dev.to/stamigos/modern-full-stack-setup-fastapi-reactjs-vite-mui-with-typescript-2mef)
- [FastAPI on-demand hot reload discussion](https://github.com/fastapi/fastapi/discussions/13192)
- [Docker hot reloading setup guide (2026)](https://oneuptime.com/blog/post/2026-01-06-docker-hot-reloading/view)
- [Optimizing WSL2 for dev containers](https://endjin.com/blog/2025/07/supercharge-dev-containers-on-windows)
