# Task 19: Configure git user identity in mpulse devcontainer from .env variables

## Summary

Move git identity configuration from the zshrc shell customization file (where it runs fragily on every shell open) into the docker-entrypoint.sh (where it runs once at container start, as root, then drops to the dev user). The new entrypoint section sets `user.email`, `user.name`, `commit.gpgsign`, and `user.signingkey` via `runuser -u dev -- git config --global ...`, guarded by non-empty checks so blank .env values never wipe existing config. The two unguarded `git config` lines in zshrc are removed entirely.

## Research Findings

### Current state (the problem)

- **`/workspace/mpulse/.devcontainer/zshrc` lines 56-57** run `git config --global user.email "$GIT_USER_EMAIL"` and `git config --global user.name "$GIT_USER_NAME"` unconditionally on every interactive shell open. If either variable is empty, it **clears** the existing git identity to an empty string. This is the fragile workaround being replaced.

- **`/workspace/mpulse/.devcontainer/docker-entrypoint.sh`** has NO git config logic currently. It handles volume permissions (lines 7-26), claude symlink (lines 28-38), SSH key copy and agent (lines 40-62), Snowflake config seeding (lines 64-76), then drops to dev user and runs init-claudio (lines 78-98).

- **`/workspace/cli/scripts/init-claudio.sh`** (the `init-claudio` command from the Claudio base image) does NOT handle git config at all. It only handles Claude credentials sync, plugin sync, and shell history.

### How env vars flow into the container

- `/workspace/mpulse/.devcontainer/docker-compose.yml` line 73-75: `env_file: - path: .env` loads ALL variables from `.env` into the container environment.
- The `.env` file (`/workspace/mpulse/.devcontainer/.env`) defines `GIT_USER_EMAIL`, `GIT_USER_NAME`, and optionally `GIT_GPG_SIGN` and `GIT_SIGNING_KEY`.
- The `GIT_USER_*` variables are NOT listed in the explicit `environment:` section (lines 47-70), but they are still available because `env_file` injects them.

### Key constraint: entrypoint runs as root

- The entrypoint runs as root (PID 1). It must use `runuser -u dev -- git config --global ...` to write to `/home/dev/.gitconfig` (not `/root/.gitconfig`).
- Existing pattern in the file: `runuser -u dev -- ssh-agent -a "$SSH_SOCK"` (line 58).

### Reference implementation

- `/workspace/.devcontainer/init-claude-settings.sh` lines 264-362 contains `sync_git_config()` which supports two modes. The relevant mode is the "project-specific" path (lines 272-303) which guards each variable with `[ -n "$VAR" ]` before setting, warns if nothing is configured, and also handles GPG signing config.

### Why NOT use init-claudio for this

- `init-claudio` runs as the `dev` user (invoked via `runuser -u dev -- sh -c 'init-claudio ...'` on line 81-84 of the entrypoint).
- However, `init-claudio` is a Claudio base image script focused on Claude credential/plugin sync -- adding git config there would couple mpulse-specific concerns into the shared base image.
- The entrypoint is the right place: it already handles per-container environment setup (SSH, Snowflake), and git identity is in the same category.

### ~/.gitconfig persistence

- `/home/dev/.gitconfig` is NOT on a named volume -- it lives on the container's ephemeral filesystem. This means it is re-created from .env on every container rebuild, which is correct behavior (identity comes from .env as source of truth).
- On container restart (without rebuild), the file persists because the container filesystem survives restarts.

## Files to Change

| File | Action | What Changes |
|------|--------|-------------|
| `/workspace/mpulse/.devcontainer/docker-entrypoint.sh` | Modify | Add git identity configuration section after Snowflake section (after line 76), before init-claudio section (before line 78) |
| `/workspace/mpulse/.devcontainer/zshrc` | Modify | Remove lines 56-57 (the two `git config --global` commands) and the preceding blank line 55 |

## Implementation Steps

### Step 1: Add git identity configuration to docker-entrypoint.sh

**What to do**: Insert a new section between the Snowflake config block (ends at line 76) and the init-claudio block (starts at line 78). The new section configures git user identity from environment variables, running as the `dev` user.

**Which file**: `/workspace/mpulse/.devcontainer/docker-entrypoint.sh`

**Where**: After line 76 (`fi`) and before line 78 (`# --- Run init-claudio if available ---`). Insert the following block (with a blank line before and after for consistency with the existing style):

```sh
# --- Git identity from .env variables ---
if [ -n "$GIT_USER_EMAIL" ]; then
    runuser -u dev -- git config --global user.email "$GIT_USER_EMAIL"
    echo "[entrypoint] Set git user.email: $GIT_USER_EMAIL"
fi
if [ -n "$GIT_USER_NAME" ]; then
    runuser -u dev -- git config --global user.name "$GIT_USER_NAME"
    echo "[entrypoint] Set git user.name: $GIT_USER_NAME"
fi
if [ "${GIT_GPG_SIGN:-false}" = "true" ]; then
    runuser -u dev -- git config --global commit.gpgsign true
    if [ -n "$GIT_SIGNING_KEY" ]; then
        runuser -u dev -- git config --global user.signingkey "$GIT_SIGNING_KEY"
        echo "[entrypoint] Enabled GPG commit signing with key: $GIT_SIGNING_KEY"
    else
        echo "[entrypoint] Enabled GPG commit signing (using default key)"
    fi
fi
```

**Key details**:
- Uses `runuser -u dev --` prefix because entrypoint runs as root and `git config --global` must write to `/home/dev/.gitconfig`, not `/root/.gitconfig`.
- Each variable is guarded with `[ -n "$VAR" ]` so empty .env values never clear existing config.
- `GIT_GPG_SIGN` defaults to `false` via `${GIT_GPG_SIGN:-false}` and only enables signing when explicitly set to `"true"`.
- Echo lines use the `[entrypoint]` prefix consistent with the existing log message on line 68 and line 83.
- The section comment uses the `# --- ... ---` convention matching all other sections in the file (lines 7, 28, 40, 54, 64, 78).

**Gotchas**:
- Do NOT add an `else` branch that clears config when vars are empty -- that was the bug in the zshrc approach.
- The `runuser` command inherits the environment from the root shell, so `$GIT_USER_EMAIL` etc. are available.
- `/home/dev/.gitconfig` may not exist yet on first container start; `git config --global` creates it automatically.

**Verification**: After the change, the entrypoint file should have the new section between the Snowflake `fi` and the `# --- Run init-claudio if available ---` comment. Count the total lines: original is 99 lines, the new block adds 19 lines (including surrounding blank lines), so the file should be approximately 118 lines.

### Step 2: Remove git config lines from zshrc

**What to do**: Remove lines 55-57 from zshrc. Line 55 is a blank line, line 56 is `git config --global user.email "$GIT_USER_EMAIL"`, and line 57 is `git config --global user.name "$GIT_USER_NAME"`. These are the last three lines of the file.

**Which file**: `/workspace/mpulse/.devcontainer/zshrc`

**Where**: Lines 55-57 (the trailing blank line and two git config commands at the end of the file).

**After the edit**, the file should end at line 54 (the blank line after the closing `}` of the `sso-login` function, or at line 53 which is `}`). Keeping one trailing blank line after the function closing brace is acceptable for style consistency, but the two `git config` lines must be completely removed.

The final lines of the file should be:

```
    echo "All SSO logins complete."
}
```

Optionally followed by a single trailing newline (which is standard for POSIX text files).

**Key details**:
- The zshrc is bind-mounted read-only into the container at `/etc/zsh/zshrc.mpulse` (see docker-compose.yml line 41: `./zshrc:/etc/zsh/zshrc.mpulse:ro`).
- It is also COPY'd into the image during build (Dockerfile lines 107-108), but the bind mount takes precedence at runtime.
- Removing these lines means git identity is no longer set on every shell open, which is the correct behavior since it's now handled once at container start.

**Gotchas**:
- Make sure to remove the blank line 55 as well, not just lines 56-57, to avoid a trailing double-blank at end of file.
- The file currently has NO trailing newline after line 57. The edited file should end with a newline after the closing `}` of `sso-login`.

**Verification**: After editing, `wc -l zshrc` should show 53 lines (the `}` on line 53) or 54 if a trailing blank line is kept. The file should NOT contain any `git config` commands -- verify with `grep "git config" zshrc` returning no results.

## Testing and Verification

### Pre-flight checks (before rebuilding)

1. **Syntax check the entrypoint**:
   ```bash
   sh -n /workspace/mpulse/.devcontainer/docker-entrypoint.sh
   ```
   Expected: no output (clean syntax).

2. **Verify zshrc has no git config lines**:
   ```bash
   grep "git config" /workspace/mpulse/.devcontainer/zshrc
   ```
   Expected: no output (no matches).

3. **Verify entrypoint has the new git config section**:
   ```bash
   grep -c "GIT_USER_EMAIL\|GIT_USER_NAME\|GIT_GPG_SIGN" /workspace/mpulse/.devcontainer/docker-entrypoint.sh
   ```
   Expected: at least 3 matches.

### Post-rebuild verification (inside the container)

1. **Verify git identity is set** (with .env values populated):
   ```bash
   git config --global user.email
   git config --global user.name
   ```
   Expected: returns the values from `.env` (`keith.schepis@mpulse.com` and `Keith Schepis`).

2. **Verify identity is available in non-interactive context**:
   ```bash
   docker exec <container> git config --global user.email
   ```
   Expected: returns the same email.

3. **Verify empty vars do not wipe config**:
   - Set `GIT_USER_EMAIL=` and `GIT_USER_NAME=` in `.env` (empty values).
   - Manually set git config inside container: `git config --global user.name "Test"`.
   - Rebuild container.
   - Check: `git config --global user.name` should still show nothing (fresh container, no prior config to preserve). But critically, it should NOT be set to an empty string -- `git config --global user.name` should return exit code 1 (not configured), not exit code 0 with empty output.

4. **Verify new shell does not re-run git config**:
   - Open a new terminal/zsh session inside the container.
   - The git identity should still be whatever was set at entrypoint time, not re-applied.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|-------------|
| `runuser -u dev -- git config --global` fails if `/home/dev` does not exist or has wrong permissions | Medium | The entrypoint already fixes permissions on `/home/dev` directories (lines 7-26). The dev user's home dir is created in the Dockerfile. No additional mitigation needed. |
| Environment variables from `env_file` not available in entrypoint | Low | Docker Compose `env_file` injects vars into the container's environment, which the entrypoint inherits as PID 1. This is standard Docker behavior and already works for `CLAUDIO_HOME`, `CLAUDIO_SHARED`, etc. |
| Removing zshrc git config breaks existing containers that haven't rebuilt | Low | The zshrc is bind-mounted from the host (docker-compose.yml line 41), so editing the file takes effect on next shell open without rebuild. However, the entrypoint change requires a container rebuild. During the window between zshrc edit and rebuild, git identity will not be set. Mitigation: commit both changes together and rebuild immediately. |
| `GIT_GPG_SIGN` value is not `true`/`false` but some other string (e.g., `yes`, `1`) | Low | We check for exact string `"true"` matching the .env.example convention (`GIT_GPG_SIGN=false`). Document that only `true` or `false` are valid values. |

## Open Questions

None. The task spec from the researcher is complete and all necessary files have been examined. The implementation is straightforward with no ambiguity.
