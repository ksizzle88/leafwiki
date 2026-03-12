# Task 45: Clean up duplicate AGENT_TEAMS env var in Dockerfile vs settings.json

## Summary

`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set in two places: the Dockerfile.base zsh profile (line 149) and `.claude/settings.json` (env block, line 15). This plan removes the Dockerfile export while keeping the `settings.json` declaration, which is the canonical mechanism for configuring Claude Code environment variables.

## Research Findings

### Location 1: Dockerfile.base (line 148-149)

File: `/workspace/Dockerfile.base`, lines 138-150 (Layer 12: Zsh configuration).

The `zsh-in-docker.sh` script appends lines to `~/.zshrc` via `-a` flags:

```dockerfile
RUN sh -c "$(wget -O- ...zsh-in-docker.sh...)" -- \
    ...
    -a "export CLAUDE_CODE_TASK_LIST_ID=main" \        # line 148
    -a "export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1" \  # line 149 <-- REMOVE THIS
    -x
```

This results in `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` being appended to the dev user's `~/.zshrc` in the Docker image. It sets the env var at the shell level for every zsh session.

### Location 2: .claude/settings.json (line 14-16)

File: `/workspace/.claude/settings.json`, lines 14-16:

```json
"env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
}
```

This is Claude Code's built-in mechanism for injecting environment variables into its own process and all subprocesses/agents it spawns. It is the documented, canonical way to configure Claude Code environment variables (see the CLAUDE.md documentation, which already recommends this approach).

### Why settings.json is canonical

1. **It is the documented approach**: The project's own CLAUDE.md documents `settings.json` env block as the way to enable Agent Teams.
2. **It works across shells and platforms**: The settings.json approach works regardless of whether the user is in zsh, bash, or another shell, and on any platform -- not just inside this Docker image.
3. **Claude Code reads it directly**: The env block is processed by Claude Code at startup. The zsh export is an indirect mechanism that relies on Claude Code inheriting the shell environment.
4. **Portability**: When this `settings.json` is used in other projects (copied via the init-claude-settings.sh sync mechanism), the env var carries over automatically. The Dockerfile zsh profile is image-specific.

### Note about CLAUDE_CODE_TASK_LIST_ID

Line 148 (`export CLAUDE_CODE_TASK_LIST_ID=main`) is NOT duplicated in settings.json, so it should remain in the Dockerfile. It is only set in the zsh profile and serves a different purpose (giving the native task system a stable ID). This is not in scope for this task.

### No downstream dependencies

- The init scripts (`init-claude-settings.sh`, `install-claudio.sh`, etc.) do not reference `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` at all.
- No devcontainer.json files reference this env var.
- The mpulse sub-project does not set this var in its own zshrc.

## Files to Change

| File | Action | What Changes |
|------|--------|-------------|
| `/workspace/Dockerfile.base` | Modify | Remove line 149: `-a "export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"` |

Only one file changes. `/workspace/.claude/settings.json` is already correct and stays as-is.

## Implementation Steps

### Step 1: Remove the duplicate export from Dockerfile.base

- **What to do**: In `/workspace/Dockerfile.base`, remove line 149 which reads `-a "export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1" \`. The trailing backslash from the previous line (148) must be preserved since line 150 (`-x`) still follows.
- **Which file**: `/workspace/Dockerfile.base`
- **Key details**:
  - Current lines 147-150:
    ```dockerfile
        -a "export HISTSIZE=10000" \
        -a "export CLAUDE_CODE_TASK_LIST_ID=main" \
        -a "export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1" \
        -x
    ```
  - After change, lines 147-149 should be:
    ```dockerfile
        -a "export HISTSIZE=10000" \
        -a "export CLAUDE_CODE_TASK_LIST_ID=main" \
        -x
    ```
- **Gotchas**:
  - Do NOT remove the backslash `\` at the end of line 148 (`CLAUDE_CODE_TASK_LIST_ID`). It must remain because the `-x` flag on the next line is still part of the same RUN command.
  - Do NOT touch line 148 (`CLAUDE_CODE_TASK_LIST_ID=main`). That env var is not duplicated elsewhere and should stay.
- **Verification**: Run `grep -n "AGENT_TEAMS" /workspace/Dockerfile.base` -- should return zero results.

## Testing and Verification

1. **Grep check**: Confirm the env var is no longer in Dockerfile.base:
   ```bash
   grep -c "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" /workspace/Dockerfile.base
   # Expected: 0
   ```

2. **Settings.json check**: Confirm the env var is still in settings.json:
   ```bash
   grep -c "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" /workspace/.claude/settings.json
   # Expected: 1
   ```

3. **Dockerfile syntax check**: Confirm the Dockerfile is still valid:
   ```bash
   docker build -f /workspace/Dockerfile.base --check /workspace
   # Expected: no syntax errors
   ```

4. **Visual inspection**: Read the modified section of Dockerfile.base and confirm the `zsh-in-docker` RUN command is still syntactically correct (all `-a` flags followed by `\`, final `-x` line has no trailing backslash).

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Some workflow depends on the shell-level export rather than settings.json | Low | Claude Code reads its env block on startup, so the var is always available. No scripts in the codebase reference this env var outside of settings.json and the Dockerfile line being removed. |
| Dockerfile syntax broken by bad line continuation | Low | The verification step includes a `docker build --check` to catch this immediately. |

## Open Questions

None. This is a straightforward cleanup with a clear canonical location already documented in the project.
