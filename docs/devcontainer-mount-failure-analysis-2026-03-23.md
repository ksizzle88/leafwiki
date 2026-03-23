# Devcontainer Mount Failure Analysis (2026-03-23)

## Scope
This document explains the startup failure seen in the Dev Containers log. It does not apply any fix.

## Symptom
During `docker compose up -d` invoked by VS Code Dev Containers, startup fails while bringing up `claudio-devcontainer-1`.

Observed error:

```text
Error response from daemon: error while mounting volume '/var/lib/docker/volumes/claudio_claudio-sessions/_data': failed to mount local volume: mount /run/desktop/mnt/host/wsl/docker-desktop-bind-mounts/Ubuntu/9917b42e952818843da5952895515bbe237a859d898d70b612983a0153284f60:/var/lib/docker/volumes/claudio_claudio-sessions/_data, flags: 0x1000: no such file or directory
```

## Where This Comes From
The failing volume is the compose-managed named volume `claudio_claudio-sessions`, mapped from volume key `claudio-sessions` in [docker-compose.yml](docker-compose.yml).

Relevant config:
- [docker-compose.yml](docker-compose.yml): `volumes.claudio-sessions` uses `driver: local` and bind options (`type: none`, `o: bind`) to host path `${CLAUDIO_ROOT:-/home/kschepis/.claudio}/sessions/claudio`
- [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json): mounts `source=claudio-sessions,target=/home/dev/.claudio-sessions,type=volume`

So the devcontainer depends on that named bind volume being mountable by Docker Desktop.

## Why This Fails Even When Paths Look Correct
The host-side directory exists (`/home/kschepis/.claudio/sessions/claudio`), and the Docker volume metadata can still look correct. However, the daemon error references a Docker Desktop internal bind mapping path under:

- `/run/desktop/mnt/host/wsl/docker-desktop-bind-mounts/Ubuntu/<hash>`

The failure is at that intermediate Docker Desktop bind-mount path (`no such file or directory`), not at the configured compose `device` path itself.

This indicates a stale or broken Docker Desktop WSL bind-mount mapping for that specific named volume instance.

## Behavioral Clues in the Log
From the attached log excerpt:
- Containers repeatedly show `Created`/`Starting` state transitions for `claudio-devcontainer-1`
- Other services (`claudio-leafwiki-1`, `claudio-devcontainer-test-1`, `claudio-claudio-standalone-1`) continue to start/turn healthy
- Final failure occurs exactly at volume mount stage for `claudio_claudio-sessions`

This pattern is consistent with an infrastructure mount-layer issue (Docker Desktop/WSL bind mapping), not an application/container image crash.

## Root Cause Statement
Primary cause: Docker daemon cannot resolve the Docker Desktop WSL bind-mount backing path for named volume `claudio_claudio-sessions`, causing devcontainer startup to abort before container runtime is fully established.

Contributing factors:
- `claudio-sessions` is configured as a named bind volume (not a plain anonymous/local volume)
- Devcontainer startup path relies on that volume early via `mounts` in [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json)

## Impact
- VS Code Dev Containers `up` command exits with code 1
- `devcontainer` service cannot transition from `Created/Starting` to healthy/running
- Workspace attach/open in container fails until mount path issue is resolved

## Proposed Fix (TODO)

Add a stale volume pre-check to `initializeCommand` in each devcontainer.json. This runs on the host *before* `docker compose up`, which is the only point where we can detect and nuke a stale volume before compose tries to mount it.

```bash
# Test-mount each bind volume; if stale, remove it so compose recreates fresh
for v in claudio-shared claudio-sessions; do
  docker run --rm -v $v:/t alpine true 2>/dev/null || docker volume rm $v 2>/dev/null
done
```

If a stale volume is removed, compose recreates it from the `driver_opts` definition (pointing back at `~/.claudio/` on the host). Data is preserved because the host directory still has everything — the volume is just Docker's pointer to it.

Also add a daily backup cron on WSL as a safety net:

```bash
# ~/.claudio/backup-sessions.sh
BACKUP_DIR="$HOME/.claudio/backups/$(date +%Y-%m-%d)"
mkdir -p "$BACKUP_DIR"
for vol in claudio-sessions mpulse-sessions homebase-sessions; do
  docker volume inspect "$vol" &>/dev/null && \
    docker run --rm -v "$vol":/src -v "$BACKUP_DIR":/dest alpine \
      tar czf "/dest/${vol}.tar.gz" -C /src .
done
find "$HOME/.claudio/backups" -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;
```

Crontab: `0 3 * * * bash ~/.claudio/backup-sessions.sh`

### When this happens
- After Docker Desktop restarts, updates, or WSL resets
- The bind-mount mapping is ephemeral on Docker Desktop's side even though the volume definition and host directory persist

### Quick manual fix
```bash
docker volume rm claudio_claudio-sessions
# Then rebuild devcontainer — compose recreates the volume automatically
```

## Non-Fix Notes
No changes were made to:
- compose files
- devcontainer config
- running volumes or containers
- host filesystem

This document is diagnosis-only, per request. Fix is TODO.
