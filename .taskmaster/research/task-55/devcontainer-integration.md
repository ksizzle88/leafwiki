# Devcontainer Integration Patterns for Dev Toolkit Server

**Research for**: Dev Toolkit (Epic #55, Core Framework #56)
**Date**: 2026-03-13
**Researcher**: task-55-researcher-3

---

## 1. Executive Summary

The Dev Toolkit server needs to start automatically inside the Claudio devcontainer, be accessible from the host browser, survive container restarts, and fit cleanly into Claudio's existing initialization flow. This document evaluates all integration options and recommends: **background process via the existing `docker-entrypoint.sh`** with port exposure via `docker-compose.yml`, health-checked by Docker's native healthcheck mechanism.

---

## 2. Current Claudio Startup Sequence

Understanding the existing flow is critical before deciding where the dev-toolkit fits in.

### Initialization Order

```
1. initializeCommand  (.devcontainer/generate-build-env.sh)
   ↓  Runs on HOST before container build. Writes BUILD_* vars to .env.
   
2. Docker build        (Dockerfile.base)
   ↓  Builds the image. ENTRYPOINT is /usr/local/bin/docker-entrypoint.sh
   
3. Container starts    (docker-compose.yml)
   ↓  ENTRYPOINT runs as root:
   │   a. Fix volume permissions (chown /home/dev/.config, .local, .cache, .claude, .claudio)
   │   b. Copy SSH keys from read-only host mount, fix permissions
   │   c. Optional: run init-firewall.sh if CLAUDIO_FIREWALL=true
   │   d. Drop privileges: exec runuser -u dev -- sh -c 'init-claudio && exec sleep infinity'
   
4. init-claudio        (/usr/local/bin/init-claudio → cli/scripts/init-claudio.sh)
   ↓  Runs as dev user:
   │   Phase 1: First-run setup (copy defaults, overlay project .claude/)
   │   Phase 2: Sync with shared volume (credentials, gh auth, plugins, caches)
   │   Phase 3: Setup symlinks (~/.claude → ~/.claudio/claude)
   │   Phase 4: Setup shell history
   │   Phase 5: Verify (print claude --version)
   
5. sleep infinity      (keeps container alive)
   
6. VS Code attaches    (devcontainer.json features, mounts, remoteEnv applied)
```

### Key Files

| File | Location | Purpose |
|------|----------|---------|
| `docker-entrypoint.sh` | `/workspace/.devcontainer/docker-entrypoint.sh` → `/usr/local/bin/docker-entrypoint.sh` | Root → init → sleep infinity |
| `init-claudio.sh` | `/workspace/cli/scripts/init-claudio.sh` → `/usr/local/bin/init-claudio` | User-space initialization |
| `init-claude-settings.sh` | `/workspace/.devcontainer/init-claude-settings.sh` → `/usr/local/bin/init-claude-settings.sh` | Legacy init (still copied into image) |
| `devcontainer.json` | `/workspace/.devcontainer/devcontainer.json` | VS Code devcontainer config |
| `docker-compose.yml` | `/workspace/docker-compose.yml` | Service definitions |
| `Dockerfile.base` | `/workspace/Dockerfile.base` | Image build instructions |

### Existing Port Usage

The docker-compose.yml already exposes port `5565:5565` on the devcontainer service (line 99). This was previously allocated for a "Task Studio UI" (per `docs/tasks/evaluate-task-management-system.md`). This port is available for reuse by the dev-toolkit or a new port can be chosen.

---

## 3. Port Forwarding

### Option A: docker-compose.yml `ports` (RECOMMENDED)

The devcontainer service in `docker-compose.yml` already has a `ports` section:

```yaml
devcontainer:
  extends:
    service: claudio-standalone
  ports:
    - "5565:5565"  # Already exists
```

**How it works**: Docker maps host port 5565 to container port 5565 at the Docker networking level. This is the most reliable approach for docker-compose-based devcontainers.

**Advantages**:
- Works immediately when the container starts — no VS Code dependency
- Accessible from host browser without VS Code forwarding
- Works for the `claudio-standalone` service (non-VS Code usage)
- Already proven in this codebase

**Port choice**: Use `DEV_TOOLKIT_PORT` environment variable (default 5565) for configurability.

### Option B: devcontainer.json `forwardPorts`

```json
{
  "forwardPorts": [5565],
  "portsAttributes": {
    "5565": {
      "label": "Dev Toolkit",
      "onAutoForward": "silent",
      "protocol": "http"
    }
  }
}
```

**How it works**: VS Code's port forwarding creates a tunnel from the container to localhost when VS Code is attached. The `portsAttributes` object configures behavior per port.

**Available `onAutoForward` values**:
- `"notify"` — Shows a toast notification when the port is detected
- `"openBrowser"` — Opens the system browser automatically
- `"openBrowserOnce"` — Opens browser only the first time
- `"openPreview"` — Opens VS Code's Simple Browser panel (side-by-side)
- `"silent"` — Forwards quietly, no notification
- `"ignore"` — Does not forward

**Important limitation with docker-compose**: When ports are already mapped in `docker-compose.yml`, `forwardPorts` can conflict because the port is already bound on the host. The recommended approach for docker-compose setups is to use `ports` in docker-compose.yml for the actual mapping and `portsAttributes` in devcontainer.json only for labeling/behavior. Do NOT duplicate the port in `forwardPorts` if it's already in docker-compose `ports`.

### Recommended Configuration

**docker-compose.yml** (already exists, keep as-is or parameterize):
```yaml
devcontainer:
  ports:
    - "${DEV_TOOLKIT_PORT:-5565}:${DEV_TOOLKIT_PORT:-5565}"
```

**devcontainer.json** (add portsAttributes only, NOT forwardPorts):
```json
{
  "portsAttributes": {
    "5565": {
      "label": "Dev Toolkit",
      "onAutoForward": "notify",
      "protocol": "http"
    }
  }
}
```

### Port Conflict Handling

If port 5565 is already in use on the host, `docker-compose up` will fail with "Bind for 0.0.0.0:5565 failed: port is already allocated." Mitigation options:

1. **Environment variable**: Let users override via `.env`: `DEV_TOOLKIT_PORT=8081`
2. **Detection in entrypoint**: Check if the port is available before starting the server; log a clear error if not
3. **`requireLocalPort: false`** in portsAttributes: Allows VS Code to map to a different local port (only relevant if using forwardPorts, not docker-compose ports)

---

## 4. Lifecycle Hooks Analysis

### Available Hooks

| Hook | When | Frequency | Run as | Use case |
|------|------|-----------|--------|----------|
| `initializeCommand` | Before container build, on HOST | Every rebuild | Host user | Generate .env (already used) |
| `onCreateCommand` | After container first created | Once per image | Container user | One-time setup |
| `postCreateCommand` | After user assignment | Once per image | Container user | Install deps, setup |
| `postStartCommand` | Every container start | Every start | Container user | Start services |
| `postAttachCommand` | When VS Code attaches | Every attach | Container user | UI notifications |

### Parallel Object Syntax

All lifecycle commands support an object format for running multiple commands in parallel:

```json
{
  "postStartCommand": {
    "init": "init-claudio",
    "dev-toolkit": "nohup dev-toolkit serve --port 5565 &"
  }
}
```

Each key runs as a separate parallel process. This is useful for running the dev-toolkit alongside other startup tasks.

### Which Hook Should Start the Dev Toolkit?

**NOT postStartCommand** — Claudio does NOT use any devcontainer lifecycle hooks for the main initialization. The entire startup is handled by the Docker ENTRYPOINT (`docker-entrypoint.sh`), which calls `init-claudio` and then `sleep infinity`. The devcontainer.json comment on line 25 says: `"// Note: init-claudio and firewall init are handled by docker-entrypoint.sh"`.

This means:
- The `claudio-standalone` service (non-VS Code) also runs init-claudio via the entrypoint
- Adding a `postStartCommand` would only run when VS Code is attached, not for standalone usage
- The entrypoint approach is more reliable (no VS Code dependency)

**RECOMMENDED: Modify the docker-entrypoint.sh to start the dev-toolkit after init-claudio.**

---

## 5. Process Management Options

### Option 1: Entrypoint Background Process (RECOMMENDED)

Modify `docker-entrypoint.sh` to start the dev-toolkit as a background process before `sleep infinity`:

```sh
# Current (line 43):
exec runuser -u dev -- sh -c 'init-claudio && exec sleep infinity'

# Proposed:
exec runuser -u dev -- sh -c 'init-claudio && dev-toolkit serve --port ${DEV_TOOLKIT_PORT:-5565} --daemon && exec sleep infinity'
```

Or use `nohup` + `&`:

```sh
exec runuser -u dev -- sh -c '
  init-claudio
  nohup dev-toolkit serve --port ${DEV_TOOLKIT_PORT:-5565} > /tmp/dev-toolkit.log 2>&1 &
  exec sleep infinity
'
```

**Advantages**:
- Simple — no additional tools needed
- Works for both standalone and devcontainer modes
- Starts before VS Code attaches
- Process tree is clean: entrypoint → dev-toolkit + sleep

**Disadvantages**:
- No automatic restart on crash (the process just dies)
- Logs go to a file, not to docker logs (can be mitigated with stdout redirection)
- `exec sleep infinity` replaces the shell, so the background process becomes an orphan (adopted by PID 1/tini). This is fine — it's the standard Docker pattern.

### Option 2: Supervisord

Install supervisord and manage both `sleep infinity` (or nothing) and the dev-toolkit as supervised processes.

```ini
[supervisord]
nodaemon=true
logfile=/dev/null
logfile_maxbytes=0

[program:dev-toolkit]
command=dev-toolkit serve --port %(ENV_DEV_TOOLKIT_PORT)s
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true
autorestart=true
startsecs=3
startretries=5
```

**Advantages**:
- Auto-restart on crash
- Structured logging
- Health monitoring built-in
- Standard pattern for multi-process containers

**Disadvantages**:
- Adds ~5MB to the image (supervisord + Python dependencies, though Python is already there)
- Additional configuration file to maintain
- Overkill for a single background process
- Changes the entrypoint pattern significantly

### Option 3: Separate Docker Compose Service

Add the dev-toolkit as its own service:

```yaml
services:
  dev-toolkit:
    image: ${COMPOSE_PROJECT_NAME:-claudio}-base:${TAG:-develop}
    command: dev-toolkit serve --port 5565
    ports:
      - "5565:5565"
    depends_on:
      claudio-standalone:
        condition: service_healthy
    networks:
      - dev-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5565/health"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s
```

**Advantages**:
- Complete isolation from the main container
- Independent restart/rebuild/scaling
- Clean separation of concerns
- Docker-native health checks and restart policies
- Logs visible via `docker compose logs dev-toolkit`

**Disadvantages**:
- The dev-toolkit needs access to the workspace files — requires the same bind mount (`.:/workspace:cached`)
- The dev-toolkit may need access to `~/.claude` config — requires the same volume mounts
- Port forwarding from a non-primary service requires `"forwardPorts": ["dev-toolkit:5565"]` in devcontainer.json, which has known issues with some configurations
- Adds complexity to the docker-compose setup
- Two containers instead of one consumes more resources (memory, CPU)
- For file watchers / live reload of workspace files, both containers would see the same bind mount — this works but adds a layer of indirection

### Option 4: postStartCommand with nohup

```json
{
  "postStartCommand": {
    "dev-toolkit": "nohup dev-toolkit serve --port 5565 > /tmp/dev-toolkit.log 2>&1 &"
  }
}
```

**Advantages**:
- No changes to Docker image or entrypoint
- VS Code native lifecycle integration

**Disadvantages**:
- Only runs when VS Code attaches (not for standalone usage)
- If the postStartCommand fails, subsequent hooks are skipped
- Process survives VS Code disconnect but not container restart
- Less visible than entrypoint approach

### Option 5: s6-overlay

A lightweight process supervisor designed for containers.

**Advantages**:
- Purpose-built for container process management
- Handles signal forwarding correctly
- Auto-restart on crash
- Small footprint (~1MB)

**Disadvantages**:
- Requires changing the base image significantly
- Different init system than Claudio currently uses
- Steep learning curve for a single process
- Overkill for this use case

### Recommendation: Option 1 (Entrypoint) with graceful enhancement path

Start with the entrypoint background process pattern. It's the simplest approach that works for both standalone and devcontainer modes. If crash recovery becomes important, add a simple wrapper script that restarts the server on exit:

```sh
#!/bin/sh
# /usr/local/bin/dev-toolkit-daemon
while true; do
    dev-toolkit serve --port "${DEV_TOOLKIT_PORT:-5565}" 2>&1
    echo "Dev Toolkit exited with code $?. Restarting in 2s..." >&2
    sleep 2
done
```

This gives automatic restart without adding supervisord as a dependency.

---

## 6. Health Checks

### Docker HEALTHCHECK (Dockerfile.base)

The current HEALTHCHECK in the Dockerfile checks for CLI availability:

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node --version && python --version && which claude && which codex && which aws && which doppler || exit 1
```

When the dev-toolkit is added, extend this to include an HTTP health check:

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD node --version && python --version && which claude && which codex \
    && curl -sf http://localhost:${DEV_TOOLKIT_PORT:-5565}/health || exit 1
```

**Note**: `curl` is not currently installed in the Claudio base image (it uses `wget`). Either:
1. Add `curl` to the apt-get install layer (recommended — it's a common debugging tool)
2. Use `wget -q --spider http://localhost:5565/health` instead
3. Use a Python one-liner: `python -c "import urllib.request; urllib.request.urlopen('http://localhost:5565/health')"`

### docker-compose.yml Health Check

The docker-compose.yml can override or extend the Dockerfile HEALTHCHECK:

```yaml
healthcheck:
  test: ["CMD", "sh", "-c", "which claude && which codex && wget -q --spider http://localhost:5565/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 15s
```

### /health Endpoint Design

The dev-toolkit server should expose a `/health` endpoint that returns:

```json
{
  "status": "healthy",
  "version": "0.1.0",
  "uptime_seconds": 1234,
  "plugins_loaded": 3,
  "plugins": [
    {"name": "markdown-browser", "status": "loaded"},
    {"name": "jtbl", "status": "loaded"},
    {"name": "agent-builder", "status": "error", "error": "missing dependency"}
  ]
}
```

A simple 200 OK with `{"status": "healthy"}` is sufficient for the Docker HEALTHCHECK. The detailed response is for the `claudio doctor` command and human debugging.

---

## 7. Configuration

### Environment Variables

| Variable | Default | Where Set | Purpose |
|----------|---------|-----------|---------|
| `DEV_TOOLKIT_PORT` | `5565` | `.env` / `docker-compose.yml` | Server port |
| `DEV_TOOLKIT_HOST` | `0.0.0.0` | `.env` / `docker-compose.yml` | Bind address |
| `DEV_TOOLKIT_RELOAD` | `true` | `.env` | Enable hot reload (dev mode) |
| `DEV_TOOLKIT_LOG_LEVEL` | `info` | `.env` | Logging verbosity |
| `DEV_TOOLKIT_PLUGINS_DIR` | `/workspace/dev-toolkit/plugins` | `.env` | Plugin discovery directory |
| `DEV_TOOLKIT_ENABLED` | `true` | `.env` | Enable/disable auto-start |

### .env File Integration

Claudio already reads `.env` via docker-compose's automatic env_file behavior. Adding dev-toolkit variables to `.env` works seamlessly:

```bash
# Dev Toolkit
DEV_TOOLKIT_PORT=5565
DEV_TOOLKIT_ENABLED=true
DEV_TOOLKIT_RELOAD=true
```

### docker-compose.yml Environment Passthrough

Add to the `environment` section of `claudio-standalone`:

```yaml
environment:
  # ... existing vars ...
  DEV_TOOLKIT_PORT: ${DEV_TOOLKIT_PORT:-5565}
  DEV_TOOLKIT_HOST: ${DEV_TOOLKIT_HOST:-0.0.0.0}
  DEV_TOOLKIT_RELOAD: ${DEV_TOOLKIT_RELOAD:-true}
  DEV_TOOLKIT_LOG_LEVEL: ${DEV_TOOLKIT_LOG_LEVEL:-info}
  DEV_TOOLKIT_ENABLED: ${DEV_TOOLKIT_ENABLED:-true}
```

### devcontainer.json Configuration

Add `portsAttributes` (NOT `forwardPorts` since docker-compose handles port mapping):

```json
{
  "portsAttributes": {
    "5565": {
      "label": "Dev Toolkit",
      "onAutoForward": "notify",
      "protocol": "http"
    }
  }
}
```

The `onAutoForward: "notify"` setting shows a non-intrusive toast when VS Code detects the port is in use, with an option to open the browser. Other options:
- `"openPreview"` — auto-opens VS Code's Simple Browser panel (good for embedded IDE experience)
- `"openBrowser"` — auto-opens the system browser
- `"silent"` — no notification at all

---

## 8. Multi-Service vs Single-Process Architecture

### Recommendation: Single Process Inside Main Container

For the initial implementation, keep the dev-toolkit as a background process in the main devcontainer. Here is the evaluation:

| Factor | Single Process | Separate Service |
|--------|---------------|-----------------|
| **Simplicity** | One container, one set of mounts | Two containers, duplicate mounts |
| **File access** | Direct (same filesystem) | Via shared bind mount |
| **Port forwarding** | Works with existing docker-compose `ports` | Requires `"forwardPorts": ["dev-toolkit:5565"]` in devcontainer.json (has known issues) |
| **Resource usage** | Minimal overhead | ~200-500MB additional memory |
| **Restart independence** | Tied to main container | Can restart independently |
| **Logging** | Mixed with container logs | Isolated logs via `docker compose logs dev-toolkit` |
| **Claudio standalone** | Works | Works (just add to compose) |
| **Claudio devcontainer** | Works | Port forwarding from non-primary services has edge cases |

**Why single process wins for now**:

1. The dev-toolkit needs read access to the entire workspace for tools like Markdown Browser and Agent Builder. This is trivially available in the same container.
2. Port forwarding from a secondary docker-compose service to VS Code has documented issues (see GitHub issue microsoft/vscode-remote-release#4645: "Allow forwarded ports from all containers in Dev Container composition"). Using docker-compose `ports` on the primary service avoids this entirely.
3. The dev-toolkit is tightly coupled to the Claudio environment — it reads `.claude/` config, workspace files, and agent definitions. Running in the same container avoids sync/mount complexity.
4. A separate service adds memory/CPU overhead for a single-user dev tool where resource efficiency matters (the container has a 4GB memory limit).

**When to switch to separate service**:
- If the dev-toolkit grows to need its own dependencies that conflict with the base image
- If crash isolation becomes critical (one tool crashing takes down the server)
- If independent scaling/restart is needed (unlikely for a single-user dev tool)

---

## 9. Recommended Integration Plan

### Step 1: Server Install in Dockerfile.base

Add a new layer after the AI CLIs layer (Layer 10) to install the dev-toolkit Python dependencies:

```dockerfile
# Layer 10.5: Dev Toolkit dependencies
USER ${DEV_USER}
RUN pip install --break-system-packages fastapi uvicorn[standard] websockets python-multipart
USER root
```

Or, if the dev-toolkit has its own `requirements.txt`:

```dockerfile
COPY dev-toolkit/requirements.txt /tmp/dev-toolkit-requirements.txt
USER ${DEV_USER}
RUN pip install --break-system-packages -r /tmp/dev-toolkit-requirements.txt
USER root
```

### Step 2: Copy Dev Toolkit Source

Add to Dockerfile.base after the Claudio CLI layer:

```dockerfile
# Layer 13.5: Dev Toolkit
COPY dev-toolkit/ /usr/local/lib/dev-toolkit/
RUN ln -sf /usr/local/lib/dev-toolkit/cli.py /usr/local/bin/dev-toolkit \
    && chmod +x /usr/local/bin/dev-toolkit
```

### Step 3: Modify docker-entrypoint.sh

Change the exec line to start the dev-toolkit before sleep:

```sh
# Drop privileges and run as dev user
if [ "$(id -u)" = "0" ]; then
    if [ $# -eq 0 ]; then
        exec runuser -u dev -- sh -c '
            init-claudio
            if [ "${DEV_TOOLKIT_ENABLED:-true}" = "true" ]; then
                echo "Starting Dev Toolkit on port ${DEV_TOOLKIT_PORT:-5565}..."
                nohup dev-toolkit serve \
                    --host "${DEV_TOOLKIT_HOST:-0.0.0.0}" \
                    --port "${DEV_TOOLKIT_PORT:-5565}" \
                    > /tmp/dev-toolkit.log 2>&1 &
                echo "Dev Toolkit started (PID: $!). Log: /tmp/dev-toolkit.log"
            fi
            exec sleep infinity
        '
    else
        exec runuser -u dev -- "$@"
    fi
fi
```

### Step 4: Update docker-compose.yml

Add environment variables to `claudio-standalone` and parameterize the port:

```yaml
claudio-standalone:
  environment:
    # ... existing ...
    DEV_TOOLKIT_PORT: ${DEV_TOOLKIT_PORT:-5565}
    DEV_TOOLKIT_ENABLED: ${DEV_TOOLKIT_ENABLED:-true}
    DEV_TOOLKIT_RELOAD: ${DEV_TOOLKIT_RELOAD:-true}

devcontainer:
  extends:
    service: claudio-standalone
  ports:
    - "${DEV_TOOLKIT_PORT:-5565}:${DEV_TOOLKIT_PORT:-5565}"
```

### Step 5: Update devcontainer.json

Add port labeling:

```json
{
  "portsAttributes": {
    "5565": {
      "label": "Dev Toolkit",
      "onAutoForward": "notify",
      "protocol": "http"
    }
  }
}
```

### Step 6: Update Health Check

In Dockerfile.base, add wget-based health check:

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD node --version && python --version && which claude && which codex \
    && ([ "${DEV_TOOLKIT_ENABLED:-true}" != "true" ] || wget -q --spider http://localhost:${DEV_TOOLKIT_PORT:-5565}/health) \
    || exit 1
```

### Step 7: Update `claudio doctor`

Extend the `claudio doctor` command to check the dev-toolkit:

```bash
# In cli/commands/doctor.sh
check_dev_toolkit() {
    if [ "${DEV_TOOLKIT_ENABLED:-true}" = "true" ]; then
        if wget -q --spider "http://localhost:${DEV_TOOLKIT_PORT:-5565}/health" 2>/dev/null; then
            echo "  Dev Toolkit: running on port ${DEV_TOOLKIT_PORT:-5565}"
        else
            echo "  Dev Toolkit: NOT RUNNING (expected on port ${DEV_TOOLKIT_PORT:-5565})"
        fi
    else
        echo "  Dev Toolkit: disabled (DEV_TOOLKIT_ENABLED=false)"
    fi
}
```

---

## 10. Hot Reload Considerations

### Backend (Python/FastAPI)

When `DEV_TOOLKIT_RELOAD=true`, start uvicorn with `--reload`:

```sh
uvicorn dev_toolkit.main:app \
    --host 0.0.0.0 \
    --port 5565 \
    --reload \
    --reload-dir /usr/local/lib/dev-toolkit \
    --reload-dir /workspace/dev-toolkit
```

The `--reload-dir` flags specify which directories to watch. Include both the installed location and the workspace source (for development).

### Frontend (Vite)

If using React + Vite, the Vite dev server needs its own port for HMR. Two approaches:

1. **Proxy through FastAPI**: FastAPI proxies `/` to Vite dev server running on a different port (e.g., 5566). Only one port exposed externally.
2. **Separate port**: Expose Vite on 5566 and FastAPI on 5565. Requires two port forwards.

The proxy approach is recommended to keep the integration simple (single port).

### Bind Mount Performance

The workspace is mounted with `:cached` mode (`- .:/workspace:cached`). This provides near-native read performance on macOS/Windows. File change events propagate with a small delay (typically <100ms). This is fast enough for hot reload.

---

## 11. VS Code Simple Browser Integration

VS Code's Simple Browser (built-in webview) can display the dev-toolkit inline:

```json
// In devcontainer.json portsAttributes:
"5565": {
  "label": "Dev Toolkit",
  "onAutoForward": "openPreview"
}
```

With `"openPreview"`, VS Code automatically opens a Simple Browser panel pointed at `http://localhost:5565` when the port is detected.

Users can also manually open it:
- Command Palette → "Simple Browser: Show" → enter `http://localhost:5565`
- Click the notification that appears when the port is auto-forwarded

The Simple Browser supports standard web features (HTML, CSS, JS, WebSocket) and works well for SPAs. It renders inside a VS Code panel, enabling side-by-side dev-toolkit and code editing.

---

## 12. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Port 5565 conflict on host | Low | Medium | `DEV_TOOLKIT_PORT` env var; clear error message |
| Dev-toolkit crash takes down container | Very Low | Low | Background process death doesn't affect `sleep infinity` (PID 1) |
| Hot reload exhausts inotify watches | Medium | Low | Increase `fs.inotify.max_user_watches` in the image |
| Startup race (server not ready when VS Code checks) | Medium | Low | `start_period: 15s` in healthcheck; retry logic in frontend |
| Memory overhead of Python server | Low | Low | FastAPI/uvicorn uses ~50-100MB; well within 4GB limit |
| Conflicting Python package versions | Medium | Medium | Use pip install --break-system-packages carefully; consider venv if conflicts arise |

---

## Sources

- [VS Code: Start a process when the container starts](https://code.visualstudio.com/remote/advancedcontainers/start-processes)
- [Dev Container metadata reference (containers.dev)](https://containers.dev/implementors/json_reference/)
- [Dev Container specification (GitHub)](https://github.com/devcontainers/spec/blob/main/docs/specs/devcontainer-reference.md)
- [Docker: Run multiple processes in a container](https://docs.docker.com/engine/containers/multi-service_container/)
- [Docker Compose Health Checks guide](https://last9.io/blog/docker-compose-health-checks/)
- [Port forward with DevContainer and Docker Compose](https://www.heissenberger.at/en/blog/devcontainer-forward-ports-composer/)
- [forwardPorts conflicts with docker-compose port mapping (GitHub issue)](https://github.com/microsoft/vscode-remote-release/issues/3025)
- [Allow forwarded ports from all containers (GitHub issue)](https://github.com/microsoft/vscode-remote-release/issues/4645)
- [How to Configure Dev Container Port Forwarding](https://oneuptime.com/blog/post/2026-01-28-dev-container-port-forwarding/view)
- [Docker Compose startup order](https://docs.docker.com/compose/how-tos/startup-order/)
