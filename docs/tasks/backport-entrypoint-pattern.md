# Backport Entrypoint Pattern to Base Image

**Status**: Pending
**Priority**: High
**Scope**: Claudio base image (`Dockerfile.base`)

## Problem

The Claudio base image ends with `USER dev` (line 170), which means any downstream container that mounts Docker named volumes will hit root-ownership permission errors. We solved this in the mpulse devcontainer with a `docker-entrypoint.sh` pattern, but every new Claudio-based container will face the same issue.

### Root Cause

Docker named volumes are created with `root:root` ownership. When mounted over directories in the container, they override whatever ownership was set in the Dockerfile. Since the container runs as `dev`, any process trying to write to these directories (e.g., `init-claudio` creating symlinks in `.cache/pip`) gets "Permission denied" and the container crash-loops (exit code 137).

## Solution (Proven in mpulse)

The mpulse devcontainer uses a `docker-entrypoint.sh` script that:

1. Starts as root (no `USER` directive at end of Dockerfile)
2. Fixes ownership of volume-mounted directories: `chown -R dev:dev /home/dev/.config /home/dev/.local /home/dev/.cache`
3. Runs optional firewall init
4. Drops privileges via `runuser -u dev` to run `init-claudio` and the main process

### Key Files to Reference

- `/workspace/mpulse/.devcontainer/docker-entrypoint.sh` — working implementation
- `/workspace/mpulse/.devcontainer/Dockerfile` — how it's integrated

## Changes Required

### 1. Create `docker-entrypoint.sh` for the base image

```bash
#!/bin/sh
set -e

# Fix ownership of common volume-mounted directories
for dir in /home/dev/.config /home/dev/.local /home/dev/.cache /home/dev/.claude /home/dev/.claudio; do
    if [ -d "$dir" ]; then
        chown -R dev:dev "$dir" 2>/dev/null || true
    fi
done

# Copy SSH keys from host mount and fix permissions (Windows/WSL2 777 issue)
if [ -d "/home/dev/.ssh-host" ]; then
    mkdir -p /home/dev/.ssh
    cp -a /home/dev/.ssh-host/. /home/dev/.ssh/ 2>/dev/null || true
    chown -R dev:dev /home/dev/.ssh
    chmod 700 /home/dev/.ssh
    find /home/dev/.ssh -name "id_*" ! -name "*.pub" -exec chmod 600 {} \;
    find /home/dev/.ssh -name "*.pub" -exec chmod 644 {} \;
    [ -f /home/dev/.ssh/config ] && chmod 644 /home/dev/.ssh/config
    [ -f /home/dev/.ssh/known_hosts ] && chmod 644 /home/dev/.ssh/known_hosts
fi

# Optional: enable network firewall
if [ "${CLAUDIO_FIREWALL:-false}" = "true" ] && [ -x /usr/local/bin/init-firewall.sh ]; then
    /usr/local/bin/init-firewall.sh 2>/dev/null || true
fi

# Drop to dev user
if [ "$(id -u)" = "0" ]; then
    if [ $# -eq 0 ]; then
        exec runuser -u dev -- sh -c 'init-claudio && exec sleep infinity'
    else
        exec runuser -u dev -- "$@"
    fi
else
    if [ $# -eq 0 ]; then
        init-claudio
        exec sleep infinity
    else
        exec "$@"
    fi
fi
```

### 2. Update `Dockerfile.base`

- Remove `USER ${DEV_USER}` at end (line 170) — entrypoint handles user switching
- Add `COPY` and `ENTRYPOINT` directives
- Keep all `USER ${DEV_USER}` / `USER root` switches during build (they're fine for build layers)

### 3. Update `.devcontainer/devcontainer.json`

- Remove `postStartCommand` for firewall (now in entrypoint)
- Ensure `remoteUser: "dev"` is set (VS Code will exec as dev)

### 4. Update downstream containers

- mpulse can simplify its own `docker-entrypoint.sh` to just call the base image's entrypoint (or extend it)
- Any existing `postCreateCommand: "init-claudio"` can be removed since entrypoint handles it

## Gotchas

- **Line endings**: Script MUST have LF line endings, not CRLF. WSL2 can create CRLF files that cause "no such file or directory" errors at runtime even though the file exists in the image.
- **`runuser` vs `su`**: Use `runuser -u dev` (not `su dev -c`) because `su` requires a password even when running as root.
- **`docker exec` runs as root**: Since the container no longer has `USER dev`, `docker exec` will default to root. Use `docker exec -u dev` for interactive sessions. VS Code handles this via `remoteUser: "dev"`.

## Testing

1. Build base image: `./build-base.sh`
2. Start a container with volume mounts: `docker compose up -d`
3. Verify no permission errors in logs: `docker compose logs`
4. Verify container stays healthy (not restarting)
5. Verify `docker exec -u dev <container> whoami` returns `dev`
6. Verify `init-claudio` ran successfully
