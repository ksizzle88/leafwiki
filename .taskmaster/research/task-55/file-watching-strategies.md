# File Watching Strategies for Dev Toolkit in Containers

**Research Date**: 2026-03-13
**Context**: Claudio Dev Toolkit (Issues #55, #56, #57, #59, #60) needs file watching for hot reload, markdown browser live updates, permissions gateway artifact detection, and agent builder live preview — all running inside Docker devcontainers.

---

## Environment Constraints

- **Claudio base image**: Ubuntu 24.04, Node.js 22, Python 3.12, npm
- **Primary host**: WSL2 on Windows (Linux 6.6 kernel)
- **Mount type**: Bind mounts with `cached` consistency mode (`.:/workspace:cached`)
- **inotify limits**: `max_user_watches=1048576`, `max_user_instances=8192` (generous defaults)
- **Container resources**: 2 CPU / 4GB RAM limit, 1 CPU / 2GB reservation
- **Must support**: Multiple watchers for different tools running simultaneously
- **Port**: Dev toolkit server on fixed port (8080), forwarded by devcontainer

---

## Docker/Container File Watching — Critical Gotchas

### The Fundamental Problem

File watching behavior depends entirely on **how the filesystem is mounted** and **which host OS** is running:

| Host OS | Mount Type | inotify Events? | Performance | Notes |
|---------|-----------|-----------------|-------------|-------|
| **Linux native** | bind mount | **Yes** | Excellent | inotify works natively, events propagate correctly |
| **WSL2 (files in WSL fs)** | bind mount | **Yes** | Good | WSL2 runs real Linux kernel; inotify works for files in the Linux filesystem |
| **WSL2 (files on Windows /mnt/c)** | bind mount | **No** | Poor | Cross-filesystem boundary; inotify does NOT fire. Must poll |
| **macOS (Docker Desktop, virtiofs)** | bind mount | **Partial** | Varies | CREATE, MODIFY, ATTRIB events work; **DELETE events are missing** (known Docker issue #7246) |
| **macOS (Docker Desktop, gRPC FUSE)** | bind mount | **Unreliable** | Poor | Older backend, events frequently missed |
| **macOS (Docker Desktop, osxfs)** | bind mount | **Unreliable** | Worst | Legacy, deprecated |
| **Any OS** | Docker volume | **Yes** | Best | Volume lives inside the VM; inotify works perfectly |

### Claudio-Specific Situation

Claudio's primary mount is `.:/workspace:cached` — a bind mount. The current dev runs on **WSL2 with files in the Linux filesystem**, where inotify works correctly. However, the Claudio image is designed to be portable, and users on macOS with Docker Desktop will hit the virtiofs/gRPC FUSE limitations.

**Key insight**: The `/workspace` bind mount is where project files live (the watched directory for hot reload, markdown browsing, agent definitions). The shared volumes (`claudio-shared`, per-container volumes) are Docker volumes where inotify works reliably. The permissions gateway's `.agent-runtime/actions/` directory would be inside the workspace bind mount.

### Recommended Strategy: inotify-first with Polling Fallback

1. **Default to native inotify watching** (no polling) — works for Linux and WSL2-native
2. **Detect when inotify fails** and fall back to polling with a configurable interval
3. **Expose an environment variable** (`DEV_TOOLKIT_POLL=true` or `DEV_TOOLKIT_POLL_INTERVAL=1000`) for macOS users
4. **Log a warning** when polling fallback activates so users understand the CPU trade-off

---

## Library Comparison

### Node.js Libraries

| Criteria | **chokidar v5** | **@parcel/watcher** | **Node.js fs.watch** | **nsfw** |
|----------|----------------|--------------------|--------------------|---------|
| **Architecture** | Pure JS, wraps fs.watch/fs.watchFile | Native C++ (prebuilt binaries) | Node.js core | Native C++ (node-gyp) |
| **Recursive Linux** | Yes (walks dirs, sets per-dir watchers) | Yes (native backend) | **No** (not supported on Linux) | Yes (native) |
| **inotify support** | Via fs.watch (indirect) | Direct inotify backend | Direct | Direct |
| **Polling fallback** | Built-in (`usePolling: true`, configurable interval) | No built-in polling | `fs.watchFile` (polling variant) | No |
| **Debouncing** | Not built-in (use wrapper) | Throttled in C++ layer | Not built-in | Not built-in |
| **Event types** | add, change, unlink, addDir, unlinkDir, ready, error | create, update, delete | change, rename (unreliable) | created, modified, deleted, renamed |
| **Glob filtering** | Removed in v4+ (use external filter) | Built-in ignore patterns | None | None |
| **Dependencies** | 1 (readdirp) since v4 | 0 (prebuilt native binaries) | 0 (built-in) | Native compilation required |
| **npm weekly downloads** | ~125M | ~21M | N/A (built-in) | ~2M |
| **Docker compat** | Excellent (pure JS, no native compilation) | Good (prebuilt for glibc; **fails on Alpine/musl**) | Built-in | Requires build tools |
| **Container CPU (idle)** | <1% (inotify mode), 5-50%+ (polling mode) | <1% | <1% (fs.watch), varies (fs.watchFile) | <1% |
| **Min Node.js** | v20 (v5) | v12+ | Any | v12+ |
| **ESM support** | ESM-only (v5) | CJS + ESM | Built-in | CJS |
| **Maturity** | 12 years, ~30M repos | 4 years, used by Tailwind/Nx/VSCode | Core Node.js | 8 years |

### Python Libraries

| Criteria | **watchfiles** | **watchdog** | **inotify-simple** |
|----------|---------------|-------------|-------------------|
| **Architecture** | Rust (rust-notify) with Python bindings | Pure Python + optional C extensions | Thin ctypes wrapper around inotify |
| **Backend (Linux)** | inotify (via rust-notify) | inotify (InotifyObserver) | Direct inotify syscalls |
| **Recursive watching** | Yes | Yes | Manual (must add watches per dir) |
| **Polling fallback** | Yes (rust-notify falls back to polling) | Yes (PollingObserver) | No (Linux-only) |
| **Debouncing** | Built-in (Rust-level, configurable) | Not built-in | Not built-in |
| **Async support** | Native (`awatch()`) | Via threads only | Via threads only |
| **API style** | Generator (yields change sets) | Observer/handler pattern | Low-level (read events) |
| **Used by** | uvicorn, FastAPI dev mode | Many Python projects | Niche/embedded |
| **PyPI monthly downloads** | ~15M | ~25M | ~1M |
| **Performance** | Excellent (Rust core) | Good (C extensions) | Excellent (minimal overhead) |
| **Docker compat** | Good (wheels available for manylinux) | Good (pure Python fallback) | Linux-only |
| **Python min** | 3.9+ | 3.6+ | 3.x |

### System-Level Tools

| Criteria | **inotifywait** | **entr** | **watchexec** |
|----------|----------------|---------|-------------|
| **Language** | C (inotify-tools) | C | Rust |
| **Installation** | `apt install inotify-tools` | `apt install entr` | Binary download or cargo |
| **Recursive** | Yes (`-r` flag) | Via piped file list | Yes (default) |
| **Debouncing** | Manual (script logic) | Built-in | Built-in (50ms default) |
| **Glob filtering** | Manual | Via piped input | Built-in (`-e`, `--exts`) |
| **Smart ignores** | No | No | Yes (.git, node_modules, etc.) |
| **Process restart** | Manual | Built-in (`-r` flag) | Built-in (`-r` flag) |
| **Cross-platform** | Linux only | Linux, macOS, BSD | Linux, macOS, Windows |
| **In base image** | No (installable) | No (installable) | No (installable) |
| **Use case** | Shell scripts, one-off watches | Simple "run on change" | Dev server restart, build triggers |
| **Polling fallback** | No | No | Yes (`--poll`) |

---

## Use Cases and Recommended Libraries

### 1. Hot Reload (Issue #56 — Core Framework)

**Need**: Watch plugin source files (JS/TS/Python), restart or HMR on change.
**Characteristics**: Moderate file count (50-500 files), needs debouncing, needs process restart.

**If Node.js server (recommended by other research)**:
- **Primary**: **chokidar v5** — proven, no native compilation needed, polling fallback for macOS
- **Alternative**: **@parcel/watcher** — faster for large projects but adds native dependency complexity
- **Integration**: Pair with `nodemon` or custom restart logic. Vite/tsx use chokidar internally.

**If Python server (FastAPI)**:
- **Primary**: **watchfiles** — already used by uvicorn (`uvicorn --reload` uses watchfiles internally)
- **Integration**: `uvicorn --reload` handles this out of the box. Zero additional setup.

### 2. Markdown Browser (Issue #57)

**Need**: Watch `.md` files across workspace, update rendered view when files change externally.
**Characteristics**: Potentially large file count (hundreds of .md files across `/workspace`, `~/.claude`, `.taskmaster/`), needs real-time updates, cross-directory watching.

**Recommendation**: Same library as the server framework (chokidar for Node, watchfiles for Python). Key considerations:
- Watch multiple root directories simultaneously
- Filter to `.md` extension at the watcher level to reduce noise
- Debounce to ~200ms (markdown files are often saved rapidly during editing)
- Push changes to frontend via WebSocket

### 3. Permissions Gateway (Issue #59)

**Need**: Watch `.agent-runtime/actions/` for new/changed request artifacts. This is security-critical — missed events mean missed approval requests.
**Characteristics**: Small, focused directory. Low file count but HIGH reliability requirement. Events must not be missed.

**Recommendation**: **Dual strategy** — inotify watcher + periodic polling verification:
- Use the same library as the main server for primary watching
- Add a periodic poll (every 5-10 seconds) as a safety net to catch any missed inotify events
- Hash-verify file contents on detection (as specified in the PRD)
- This directory is within the workspace bind mount, so all container-mount caveats apply

**Alternative for standalone CLI mode**: `inotifywait` (already available via apt) for a pure shell implementation:
```bash
inotifywait -m -r -e create,modify,moved_to .agent-runtime/actions/ | while read event; do
  # Process new/changed request artifacts
done
```

### 4. Agent Builder (Issue #60)

**Need**: Watch agent definition files for live preview updates (`.claude/agents/`, `.claude/commands/`, settings files).
**Characteristics**: Small file count (<50 files), needs fast updates for live preview, watches across config hierarchy.

**Recommendation**: Same library as the server framework. Key considerations:
- Watch multiple config directories: `/workspace/.claude/`, `~/.claude/`, `.taskmaster/`
- Filter to `.md`, `.json`, `.sh` extensions
- Debounce to ~100ms for snappy preview updates

---

## Performance Considerations

### How Many Files Can You Watch?

| Library | Comfortable Range | Degradation Point | Notes |
|---------|------------------|-------------------|-------|
| chokidar (inotify) | 10,000-50,000 | >100,000 files | One inotify watch per directory; system limit is 1M watches |
| @parcel/watcher | 50,000-200,000 | >500,000 files | Native, more efficient than chokidar |
| watchfiles | 10,000-100,000 | >200,000 files | Rust core handles the heavy lifting |
| inotifywait | 10,000-50,000 | >8,192 dirs (default) | Limited by `max_user_instances` |

**Claudio context**: A typical dev workspace will have 5,000-20,000 files. With `node_modules` ignored, active watch targets are usually <5,000 files — well within comfortable range for all libraries.

### Debouncing Strategy

Recommended debounce windows for each use case:
- **Hot reload**: 100-300ms (balance between responsiveness and avoiding spurious restarts)
- **Markdown preview**: 150-250ms (fast enough to feel live, slow enough to batch rapid saves)
- **Permissions gateway**: 0ms (no debounce — every event matters, verify by hash anyway)
- **Agent builder preview**: 100-200ms (snappy preview updates)

### CPU Impact of Polling Fallback

| Polling Interval | Files Watched | Approx CPU Usage | Responsiveness |
|-----------------|--------------|-------------------|----------------|
| 100ms (default) | 1,000 | 2-5% | Near-instant |
| 100ms | 10,000 | 15-50% | Near-instant |
| 500ms | 1,000 | <1% | Half-second delay |
| 1,000ms | 10,000 | 2-5% | One-second delay |
| 5,000ms | 10,000 | <1% | Five-second delay |

**Recommendation for polling fallback**: 1,000ms (1 second) as default. Configurable via env var. This balances CPU usage against acceptable delay for dev tool use cases.

---

## Recommended Architecture: Shared File Watcher Service

Rather than each plugin creating its own watcher, the Dev Toolkit should provide a **centralized file watcher service** at the framework level:

```
┌──────────────────────────────────────────────────┐
│                Dev Toolkit Server                  │
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │          FileWatcherService (singleton)        │ │
│  │                                                │ │
│  │  - Manages all watches across plugins          │ │
│  │  - Deduplicates overlapping watch paths        │ │
│  │  - Handles inotify → polling fallback          │ │
│  │  - Exposes subscribe(path, glob, callback)     │ │
│  │  - Configurable debounce per subscription      │ │
│  │  - Emits events to subscribers via EventEmitter│ │
│  └──────────────────────────────────────────────┘ │
│        │           │            │           │      │
│   Hot Reload   Markdown    Permissions   Agent     │
│   Plugin       Browser     Gateway       Builder   │
│                                                    │
│   Watches:     Watches:    Watches:      Watches:  │
│   src/**/*.ts  **/*.md     .agent-       .claude/  │
│   plugins/     ~/.claude/  runtime/      agents/   │
│                .taskmaster actions/      commands/  │
└──────────────────────────────────────────────────┘
```

Benefits:
- **Single inotify overhead** for shared paths (e.g., `/workspace` root)
- **Consistent fallback behavior** — one env var controls all plugins
- **Resource management** — centralized watch count monitoring
- **Plugin simplicity** — plugins just subscribe, don't manage watchers

---

## Final Recommendation

### Primary Choice: **chokidar v5** (for Node.js server)

**Why chokidar over alternatives:**

1. **No native compilation** — Pure JS, works everywhere including Alpine (unlike @parcel/watcher)
2. **Built-in polling fallback** — Critical for macOS Docker Desktop users
3. **Battle-tested** — 12 years old, ~125M weekly downloads, used by webpack, Vite, nodemon, etc.
4. **Already in Node.js ecosystem** — Zero friction with the Node.js 22 in the base image
5. **Minimal dependencies** — Only 1 dependency (readdirp) since v4
6. **Sufficient performance** — For a dev toolkit watching <10,000 files, chokidar's performance is more than adequate

**Why NOT @parcel/watcher:**
- Native C++ compilation adds Docker build complexity
- Fails on Alpine/musl (limits future base image changes)
- No built-in polling fallback
- Marginal performance advantage irrelevant at our scale

**Why NOT native fs.watch:**
- No recursive watching on Linux
- Unreliable event types
- No polling fallback
- Would need to reimplement most of what chokidar provides

### Secondary Choice: **watchfiles** (if Python/FastAPI server)

If the server framework decision goes with FastAPI/Python:
- **watchfiles is already used by uvicorn** — hot reload works out of the box
- Rust core provides excellent performance
- Built-in debouncing
- Native async support fits well with FastAPI/Starlette

### For Standalone CLI Tools (Permissions Gateway)

If the permissions gateway CLI needs to work independently of the web server:
- **inotifywait** for simple shell-based watching (add to base image with `apt install inotify-tools`)
- Wrap in a bash script with a periodic polling safety net
- Or use the same Node/Python watcher library if the CLI is written in those languages

---

## Implementation Notes

### Ignore Patterns (Apply Globally)

These should be ignored by all watchers to avoid noise and performance waste:

```javascript
const GLOBAL_IGNORES = [
  '**/node_modules/**',
  '**/.git/**',
  '**/.venv/**',
  '**/venv/**',
  '**/__pycache__/**',
  '**/dist/**',
  '**/build/**',
  '**/.next/**',
  '**/target/**',        // Rust, dbt
  '**/*.pyc',
  '**/.DS_Store',
  '**/thumbs.db',
];
```

### Environment Variables

```bash
# Force polling mode (for macOS Docker Desktop users)
DEV_TOOLKIT_POLL=true

# Set polling interval in ms (default: 1000)
DEV_TOOLKIT_POLL_INTERVAL=1000

# Enable verbose watcher logging (debug)
DEV_TOOLKIT_WATCH_DEBUG=true
```

### Container Detection

The toolkit should auto-detect the container environment to set sensible defaults:

```javascript
function detectWatchMode() {
  // Check if running in Docker
  const inDocker = fs.existsSync('/.dockerenv') || fs.existsSync('/run/.containerenv');

  // Check if workspace is a bind mount (vs Docker volume)
  // On bind mounts from macOS, inotify may be unreliable
  // Let the user override via env var
  if (process.env.DEV_TOOLKIT_POLL === 'true') {
    return { usePolling: true, interval: parseInt(process.env.DEV_TOOLKIT_POLL_INTERVAL || '1000') };
  }

  // Default: use inotify (works on Linux, WSL2 with Linux fs)
  return { usePolling: false };
}
```

---

## Sources

- [chokidar GitHub](https://github.com/paulmillr/chokidar)
- [@parcel/watcher GitHub](https://github.com/parcel-bundler/watcher)
- [@parcel/watcher npm](https://www.npmjs.com/package/@parcel/watcher)
- [watchfiles documentation](https://watchfiles.helpmanual.io/)
- [watchfiles GitHub](https://github.com/samuelcolvin/watchfiles)
- [Docker for Mac: Missing DELETE inotify event with VirtioFS (Issue #7246)](https://github.com/docker/for-mac/issues/7246)
- [Docker for Mac: Missing file system events on mounts (Issue #2216)](https://github.com/docker/for-mac/issues/2216)
- [Docker for Win: INOTIFY Events not supported in WSL2 (Issue #12898)](https://github.com/docker/for-win/issues/12898)
- [Docker Desktop WSL2 Best Practices](https://www.docker.com/blog/docker-desktop-wsl-2-best-practices/)
- [watchexec: Modern file watching](https://tech.stonecharioteer.com/posts/2025/til-watchexec/)
- [chokidar: High CPU usage in Docker (Issue #1057)](https://github.com/paulmillr/chokidar/issues/1057)
- [Vite: Use fs.watch instead of chokidar (Issue #12495)](https://github.com/vitejs/vite/issues/12495)
- [Eleventy: Switch from chokidar to @parcel/watcher (Issue #3149)](https://github.com/11ty/eleventy/issues/3149)
- [npm trends: @parcel/watcher vs chokidar vs nsfw](https://npmtrends.com/@parcel/watcher-vs-chokidar-vs-filespy-vs-nsfw)
- [inotifywait man page](https://man7.org/linux/man-pages/man1/inotifywait.1.html)
