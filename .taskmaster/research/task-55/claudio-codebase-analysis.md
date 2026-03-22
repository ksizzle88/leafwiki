# Claudio Codebase Analysis: Integration Points for the Dev Toolkit

**Researcher**: codebase-analysis
**Date**: 2026-03-13
**Epic**: #55 (Dev Toolkit)

---

## 1. What's Already There: Technologies and Stack

### Base Image (`Dockerfile.base`)
The Claudio base image is built on `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` and includes:

| Technology | Version | Path/Notes |
|-----------|---------|------------|
| **Node.js** | 22.x | `/usr/bin/node`, via NodeSource |
| **Python** | 3.12 (Ubuntu native) | `/usr/bin/python3`, aliases to `python` |
| **npm** | via Node.js | Global prefix: `/usr/local/share/npm-global` |
| **pip** | system pip | `--break-system-packages` flag used |
| **GitHub CLI** | latest | `/usr/bin/gh` |
| **AWS CLI v2** | latest | Installed from official ZIP |
| **Doppler CLI** | latest | Installed from official script |
| **Claude Code CLI** | latest | `/usr/local/share/npm-global/bin/claude` |
| **Codex CLI** | latest | `/usr/local/share/npm-global/bin/codex` |
| **task-master-ai** | latest | `/usr/local/share/npm-global/bin/task-master` |
| **jq** | system | `/usr/bin/jq` |
| **tmux** | system | Used for Agent Teams split-pane mode |
| **fzf** | system | Fuzzy finder for CLI |
| **build-essential** | system | For native module compilation |
| **libpq-dev** | system | PostgreSQL client library |
| **iptables/ipset** | system | For firewall feature |

**Key takeaway**: Both Node.js 22 and Python 3.12 are available. The toolkit can use either or both. pip requires `--break-system-packages` or a venv. npm globals go to `/usr/local/share/npm-global`.

### User Configuration
- Default user: `dev` (UID 1000, GID 1000)
- Home directory: `/home/dev`
- Default shell: zsh (with Oh My Zsh, fzf, git plugins)
- Password: `dev` (configurable via build arg)

---

## 2. Docker Setup: Services and Composition

### `docker-compose.yml` — Service Structure

Three services:

1. **`claudio-standalone`**: Base service with all runtime config. Can run independently without VS Code.
2. **`devcontainer`**: Extends `claudio-standalone`. VS Code attaches here. Adds port forwarding and extra mounts.
3. **`devcontainer-test`**: Extends `claudio-standalone`. For testing devcontainer changes without disrupting the main container.

**Current port allocation**:
- `5565:5565` — Currently exposed on the `devcontainer` service. Purpose not documented in compose file but appears to be reserved.

**Network**: Bridge network named `dev-network`.

**Resource limits**: 2 CPUs, 4GB memory (2 reserved).

**Security capabilities**: `NET_ADMIN`, `NET_RAW` (for firewall feature).

### `devcontainer.json` — VS Code Integration

Key configuration:
- `initializeCommand`: `.devcontainer/generate-build-env.sh` (runs before build to inject BUILD_* provenance)
- `features`: Docker-outside-of-docker
- `remoteUser`: `dev`
- `mounts`: Per-container volumes via `${devcontainerId}`, SSH keys, GPG keys
- `remoteEnv`: SSH agent forwarding
- VS Code extensions: Claude Code, Docker, GitLens

**No `postCreateCommand` is set** in devcontainer.json — initialization is handled by the Docker entrypoint.

---

## 3. Initialization Flow: Where Dev Toolkit Startup Fits

### Container Startup Sequence

```
1. docker-compose build (Dockerfile.base layers)
2. devcontainer.json initializeCommand → generate-build-env.sh
3. Container starts → ENTRYPOINT: /usr/local/bin/docker-entrypoint.sh (as root)
   a. Fix volume permissions (chown dev:dev on .config, .local, .cache, .claude, .claudio)
   b. Copy SSH keys from read-only mount, fix permissions
   c. Optionally run init-firewall.sh (if CLAUDIO_FIREWALL=true)
   d. Drop to dev user → run: init-claudio && sleep infinity
4. init-claudio (/usr/local/bin/init-claudio, from cli/scripts/init-claudio.sh)
   a. Phase 1: First-run setup (copy defaults, overlay project settings)
   b. Phase 2: Sync with shared volume (credentials, plugins, caches)
   c. Phase 3: Setup symlinks (~/.claude → $CLAUDIO_HOME/claude)
   d. Phase 4: Setup shell history
   e. Phase 5: Verify (print status)
5. sleep infinity (keeps container alive)
```

### Integration Point for Dev Toolkit

The toolkit server should start **after `init-claudio` completes** but **before `sleep infinity`**. Options:

**Option A** — Modify `docker-entrypoint.sh` to start the toolkit:
```sh
exec runuser -u dev -- sh -c 'init-claudio && dev-toolkit serve --daemon && exec sleep infinity'
```

**Option B** — Add a `postStartCommand` in `devcontainer.json`:
```json
"postStartCommand": "dev-toolkit serve --daemon"
```

**Option C** — Add a dedicated startup script to `init-claudio.sh` Phase 5+:
```sh
# Phase 6: Start dev toolkit (if installed)
if command -v dev-toolkit &> /dev/null; then
    dev-toolkit serve --daemon --port "${DEV_TOOLKIT_PORT:-8080}"
fi
```

**Recommendation**: Option C (inside `init-claudio.sh`) is the most consistent with the existing architecture. It follows the same pattern as other initializations, works for both standalone and devcontainer modes, and keeps the startup sequence centralized. The entrypoint change (Option A) would also work but modifies a more critical file.

---

## 4. CLI Architecture: Patterns to Follow

### Claudio CLI (`/usr/local/lib/claudio/`)

Structure:
```
cli/
├── claudio              # Main entry point (bash)
├── commands/            # Subcommands
│   ├── doctor.sh        # Diagnose issues
│   ├── help.sh          # Show help
│   ├── migrate.sh       # Volume migration
│   ├── verify.sh        # Verify setup
│   └── version.sh       # Show version
├── lib/                 # Shared libraries
│   ├── common.sh        # Utilities, colors, flag parsing
│   └── output.sh        # Formatting (headers, tables, checks, spinners, JSON)
├── scripts/             # Standalone scripts
│   ├── create-volumes.sh    # Volume creation
│   ├── init-claudio.sh      # Container initialization
│   └── task-master-wrapper.sh  # Task-master CLI wrapper
└── templates/           # Integration templates for external repos
    ├── simple-image/
    ├── extended-dockerfile/
    ├── docker-compose/
    └── local-overrides/
```

**Patterns**:
- Each command is a separate `.sh` file sourced by the main entry point
- Commands define `cmd_<name>()` functions
- Common flags (`--quiet`, `--verbose`, `--json`, `--no-color`) parsed by `parse_common_flags()` in `lib/common.sh`
- Output formatting centralized in `lib/output.sh` (colors, check marks, tables, spinners)
- Version: `CLAUDIO_VERSION="1.0.0"` in `lib/common.sh`
- CLI installed at image build time: `COPY cli/ /usr/local/lib/claudio/` + symlink to `/usr/local/bin/claudio`

**Dev toolkit CLI integration options**:

1. **Subcommand of `claudio`**: Add `cli/commands/toolkit.sh` (e.g., `claudio toolkit serve`)
2. **Separate binary**: Install `dev-toolkit` at `/usr/local/bin/dev-toolkit` alongside `claudio`
3. **Both**: `dev-toolkit` as standalone binary, `claudio toolkit` as alias/shortcut

**Recommendation**: Separate binary (`dev-toolkit`) is better for independence and avoids bloating the Claudio CLI. The toolkit has its own lifecycle, commands, and complexity. The Claudio CLI can add a thin `claudio toolkit` alias if desired.

---

## 5. Volume Architecture: Where Dev Toolkit State Lives

### Current Volume Layout

**Per-container (isolated via `${devcontainerId}`):**
```
claudio-${devcontainerId}     → /home/dev/.claudio      (per-container Claudio state)
claudio-history-${devcontainerId} → /commandhistory      (shell history)
```

**Shared (external, cross-container):**
```
claudio-shared                → /home/dev/.claudio-shared  (auth, plugins, caches)
  ├── auth/                   (.credentials.json, gh/)
  ├── plugins/                (skills/, commands/, hooks/, agents/)
  ├── caches/                 (npm/, pip/)
  └── config/                 (general config)
```

**Standalone service volumes:**
```
claudio-standalone            → /home/dev/.claudio
commandhistory-standalone     → /commandhistory
```

### New Volumes Needed for Dev Toolkit

The toolkit needs to decide which data is per-container vs shared.

**Per-container** (stored within existing `claudio-${devcontainerId}` volume):
- Session state (open tabs, recent files, UI preferences)
- Temporary query results and cache
- Per-project toolkit settings

**Shared** (stored within existing `claudio-shared` volume):
- User preferences (themes, keybindings, default views)
- Saved queries/templates (jtbl saved queries, agent builder templates)
- Plugin registry state

**No new Docker volumes are needed**. The toolkit state should be stored in subdirectories within existing volumes:

```
/home/dev/.claudio/
  toolkit/                    # Per-container toolkit state
    session.json              # Active session state
    cache/                    # Temporary data
    settings.json             # Per-project toolkit settings

/home/dev/.claudio-shared/
  toolkit/                    # Shared toolkit state
    preferences.json          # User preferences (cross-container)
    saved-queries/            # jtbl saved queries
    templates/                # Agent builder custom templates
```

The `docker-entrypoint.sh` already chowns `/home/dev/.claudio` and `/home/dev/.claudio-shared` directories, so no permission changes are needed.

---

## 6. Port Allocation

### Currently Used
- **5565**: Forwarded on devcontainer service (`docker-compose.yml:99`). Purpose undocumented.

### Available for Dev Toolkit
The issue suggests port **8080** as the default. This is a reasonable choice. It should be configurable via environment variable.

### Configuration Points
- `docker-compose.yml`: Add port mapping under `devcontainer` service
- `devcontainer.json`: Add `forwardPorts` entry
- `.env`: Add `DEV_TOOLKIT_PORT` variable

Example additions:

**docker-compose.yml** (devcontainer service):
```yaml
ports:
  - "5565:5565"
  - "${DEV_TOOLKIT_PORT:-8080}:${DEV_TOOLKIT_PORT:-8080}"
```

**devcontainer.json**:
```json
"forwardPorts": [8080],
"portsAttributes": {
  "8080": {
    "label": "Dev Toolkit",
    "onAutoForward": "notify"
  }
}
```

---

## 7. Claude Configuration: Settings, Agents, Hooks

### Settings (`/.claude/settings.json`)

Current structure:
- **permissions.allow**: Bash patterns for auto-allowed tools (git, npm, node, docker, ls, find, gh)
- **env**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"` (enables agent teams)
- **hooks**: PreToolUse, Stop (usage fetch), TeammateIdle, TaskCompleted
- **statusLine**: Custom command-based statusline
- **enabledPlugins**: `frontend-design@claude-plugins-official`

Dev toolkit integration points in settings:
- Add `DEV_TOOLKIT_PORT` to `env` if needed
- No permission changes needed unless toolkit CLI commands need auto-approval

### Agent Definitions (`/.claude/agents/`)

5 agents defined, all in markdown with YAML frontmatter:
- `coordinator.md` — Central orchestrator, never writes code
- `researcher.md` — Codebase exploration and spec writing
- `implementer.md` — Code implementation
- `planner.md` — Plan creation
- `reviewer.md` — Code review and verification

Frontmatter format:
```yaml
---
name: coordinator
description: Central orchestrator for multi-agent task pipelines.
tools: Agent(...), TeamCreate, TeamDelete, SendMessage, Read, Glob, Grep, Bash(gh issue *), ...
model: opus
---
```

**Relevant for Agent Builder (#60)**: These files are the primary targets. The Agent Builder needs to parse this frontmatter format, understand the tools declarations, and visualize relationships between agents.

### Commands (`/.claude/commands/`)

Organized in subdirectories:
- `core/` — Core development commands (commit, run-local, init-project, create-prd, feature-request)
- `core/core_piv_loop/` — Plan-implement-verify loop
- `core/github_bug_fix/` — Bug fix workflow
- `core/validation/` — Code review and validation
- `do-task.md` — Primary task pipeline entry point
- `flesh-out.md` — Flesh out issue spec
- `plan.md` — Create implementation plan

### Hooks (`/.claude/hooks/`)

Two hooks, both currently no-op placeholders:
- `teammate-idle.sh` — Exit 0 (allow idle) or exit 2 (block with feedback)
- `task-completed.sh` — Exit 0 (allow completion) or exit 2 (block with feedback)

### MCP Configuration (`/.claude/mcp.json`)

Currently empty: `{"mcpServers": {}}`. The dev toolkit could register itself as an MCP server if that pattern makes sense.

---

## 8. Image Build and Packaging

### Build Script (`build-base.sh`)

- Supports `--tags`, `--push`, `--registry` flags
- Loads `.env` for git config and registry auth
- Computes build provenance (commit, branch, tag, date, hostname)
- Pushes to `ghcr.io/ksizzle88/claudio`

### Where to Install Dev Toolkit in the Image

Following the existing pattern, the toolkit should be added after the Claudio CLI layer:

```dockerfile
# Layer 13: Claudio CLI
COPY cli/ /usr/local/lib/claudio/
RUN chmod +x ...

# Layer NEW: Dev Toolkit
COPY dev-toolkit/ /usr/local/lib/dev-toolkit/
RUN ...install steps...
RUN ln -sf /usr/local/lib/dev-toolkit/bin/dev-toolkit /usr/local/bin/dev-toolkit
```

If the toolkit is Python-based (FastAPI), it could use:
- System Python 3.12 with `pip install --break-system-packages`
- Or a dedicated venv at `/opt/dev-toolkit/venv/`

If Node-based (Express/Fastify), it could use:
- Global npm install via the existing user-writable npm prefix
- Or a bundled node_modules at `/usr/local/lib/dev-toolkit/node_modules/`

### .dockerignore Impact

The current `.dockerignore` excludes `*.md` (except README.md), `tests/`, and `Dockerfile*`. If the toolkit source lives in the repo (e.g., `dev-toolkit/`), the .dockerignore will need updates to include toolkit files in the build context.

---

## 9. Constraints: What Can't Change Without Breaking Users

1. **Volume mount paths**: `/home/dev/.claude`, `/home/dev/.claudio`, `/home/dev/.claudio-shared` are hardcoded in `docker-compose.yml`, `devcontainer.json`, and all init scripts
2. **`init-claudio` execution order**: Must run before the toolkit server starts (it sets up `~/.claude` symlink and credentials)
3. **Port 5565**: Already allocated; don't reuse it
4. **User/UID**: `dev:1000` throughout; toolkit must run as this user
5. **Entrypoint pattern**: Root for permissions, then drops to dev; toolkit must not require root
6. **`claudio-shared` volume structure**: `auth/`, `plugins/`, `caches/`, `config/` subdirectories are expected by `init-claudio.sh`
7. **`.claude/` directory structure**: `settings.json`, `mcp.json`, agents/, commands/, hooks/, skills/, reference/ — all synced by init scripts
8. **CLAUDE_CONFIG_DIR**: Must point to `~/.claude` at runtime
9. **Shell configuration**: `.zshrc` entries for history, CLAUDE_CODE_TASK_LIST_ID, etc.

---

## 10. Opportunities: Reusable Infrastructure

1. **CLI libraries** (`cli/lib/common.sh`, `cli/lib/output.sh`): Color handling, flag parsing, output formatting — can be reused if toolkit has a bash CLI component. For Python/Node CLI, these patterns should be replicated.

2. **Init script pattern**: `init-claudio.sh` demonstrates a clean phase-based initialization. The toolkit can add its own phase.

3. **Shared volume sync**: The bidirectional `cp -ru` sync pattern in `init-claudio.sh` can sync toolkit preferences across containers.

4. **Agent Teams infrastructure**: The toolkit could be exposed as an MCP server that agents can query (e.g., "what's the current task board state?").

5. **Docker-outside-of-docker**: The devcontainer feature enables container management from within the toolkit (relevant for #27 environment management).

6. **Health check endpoint**: The Dockerfile already has a healthcheck. The toolkit should add its own (e.g., `curl -f http://localhost:8080/health`).

7. **Templates system** (`cli/templates/`): Could be extended with dev-toolkit integration templates for external repos.

8. **Hooks system**: The existing `TeammateIdle` and `TaskCompleted` hooks are currently no-ops. The toolkit could provide a web UI for configuring quality gates that these hooks enforce.

9. **Build provenance**: `/etc/claudio-release` and the `generate-build-env.sh` pattern can be extended to include toolkit version.

---

## 11. Related Issues Context

### #27 (Control Plane UI) — Absorbed
Original scope: Web-based control plane for task/agent/environment management, git worktrees, remote access. This becomes the "operations dashboard" tool within the dev-toolkit. Key requirements that survive: agent status viewing, container management, task board.

### #39 (Persistent Task Board) — Becomes Toolkit Tool
EPIC for cross-session/container task persistence. Currently tasks.json is per-repo. Research needed on shared persistence (shared volume, SQLite REST API, git sync). The toolkit's task board view would be a natural consumer of whatever persistence solution is chosen.

### #40 (Research: Task Board Persistence) — Backend Decision
Pure research task. Options: shared Docker volume, git-based sync, SQLite + REST, file-based with locking. This decision directly impacts the toolkit's task board tool architecture.

---

## 12. Summary of Integration Points

| Integration Point | File(s) | What Changes |
|---|---|---|
| **Dockerfile** | `Dockerfile.base` | Add layer to install dev-toolkit |
| **Container startup** | `cli/scripts/init-claudio.sh` | Add Phase 6 to start toolkit server |
| **Docker Compose** | `docker-compose.yml` | Add port mapping for toolkit |
| **DevContainer config** | `.devcontainer/devcontainer.json` | Add `forwardPorts` entry |
| **Port permissions** | `docker-entrypoint.sh` | Permission fixes for toolkit state dir |
| **Shared volume** | `cli/scripts/create-volumes.sh` | Add `toolkit/` subdir to `claudio-shared` |
| **Environment variables** | `docker-compose.yml`, `.env.example` | Add `DEV_TOOLKIT_PORT` |
| **Health check** | `Dockerfile.base`, `docker-compose.yml` | Add toolkit health endpoint |
| **Build/push** | `build-base.sh`, `.github/workflows/build-push-image.yml` | Include toolkit in image |
| **.dockerignore** | `.dockerignore` | Allow toolkit source files in build context |
| **Claude settings** | `.claude/settings.json` | Optional: toolkit-related permissions |
| **CLI** | `cli/claudio` | Optional: add `claudio toolkit` alias |
