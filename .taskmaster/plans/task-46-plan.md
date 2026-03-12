# Task 46: Fix init-claudio.sh to sync hooks on every container start

## Summary

The active init script (`/workspace/cli/scripts/init-claudio.sh`, installed as `/usr/local/bin/init-claudio`) has two bugs affecting directory sync:

1. **Phase 1 (first-run) project overlay is broken**: Line 32 uses `find /workspace/.claude -type f ... -exec cp {} "$CLAUDE_DIR/" \;` which copies ALL files from ALL subdirectories flat into `$CLAUDE_DIR/`, destroying directory structure. Files from `hooks/`, `commands/`, `skills/`, `agents/`, and `reference/` subdirectories all land at the top level. The image defaults' `cp -r` (line 25) correctly creates subdirectories, but the project overlay immediately flattens any overrides.

2. **Phase 2 (always-run) is missing project overlay and missing directories from shared sync**: The shared plugins sync (lines 80-85) only handles `skills` and `commands` -- missing `hooks` and `agents`. And there is no mechanism at all to sync project directories (`/workspace/.claude/`) on subsequent container starts.

This plan fixes both bugs in `init-claudio.sh` (primary) and also patches the legacy `init-claude-settings.sh` for consistency.

## Research Findings

### Active init script: `/workspace/cli/scripts/init-claudio.sh`

- **Entrypoint**: `docker-entrypoint.sh` line 43 calls `init-claudio` (NOT `init-claude-settings.sh`)
- **Installed to**: `/usr/local/bin/init-claudio` (Dockerfile.base line 165)
- **First-init guard**: Uses `$CLAUDIO_HOME/.initialized` marker file (line 16), not empty-dir check

**Phase 1 (first-run, lines 16-38)**:
```
Line 24-27: cp -r "$DEFAULTS/.claude/"* "$CLAUDE_DIR/"  -- correctly copies with directory structure
Line 30-34: find /workspace/.claude -type f ... -exec cp {} "$CLAUDE_DIR/" \;  -- BROKEN: flattens all files
```
The `find` on line 32 has no `-maxdepth 1` and uses `cp {} "$CLAUDE_DIR/"` which copies every file into the root of `$CLAUDE_DIR/` regardless of its source subdirectory. Verified in live container: files like `cli-best-practices.md`, `converting-sub-agents-to-skills.md`, `skill-template.md` all sit flat in `~/.claudio/claude/` instead of in `reference/`, `skills/`, etc.

**Phase 2 (always-run, lines 40-102)**:
```
Lines 51-72: Credentials sync (bidirectional, newer wins) -- works correctly
Lines 74-78: GitHub CLI sync -- works correctly
Lines 80-85: Plugins sync:
  - Line 82: cp -ru "$CLAUDIO_SHARED/plugins/"* "$CLAUDE_DIR/"  -- shared -> local (all plugins)
  - Line 83: cp -ru "$CLAUDE_DIR/skills" "$CLAUDIO_SHARED/plugins/"  -- local -> shared (skills only)
  - Line 84: cp -ru "$CLAUDE_DIR/commands" "$CLAUDIO_SHARED/plugins/"  -- local -> shared (commands only)
  MISSING: hooks, agents not synced to shared
  MISSING: no project overlay (/workspace/.claude/) on subsequent starts
```

**Phase 3 (lines 104-113)**: Symlinks `~/.claude` -> `$CLAUDE_DIR`. Works correctly.

### Key variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `CLAUDIO_HOME` | `$HOME/.claudio` | Root of Claudio's persistent data |
| `CLAUDIO_SHARED` | `$HOME/.claudio-shared` | Shared volume mount |
| `CLAUDE_DIR` | `$CLAUDIO_HOME/claude` | Where Claude Code config lives (symlinked to `~/.claude`) |
| `DEFAULTS` | `/opt/claudio-defaults` | Image-baked defaults |

### Shared volume directory structure

Observed at `$HOME/.claudio-shared/`:
```
auth/                   -- credentials
plugins/skills/         -- shared skills
plugins/commands/       -- shared commands
plugins/mcp/            -- MCP configs
caches/npm/             -- npm cache
caches/pip/             -- pip cache
```
Missing: `plugins/hooks/` and `plugins/agents/`.

### Legacy script: `/workspace/.devcontainer/init-claude-settings.sh`

Still present in the image at `/usr/local/bin/init-claude-settings.sh` but NOT called by the entrypoint. The legacy script has a similar but different set of bugs (detailed in previous plan version). For consistency it should also get the `hooks` fix in its shared plugins sync loop (line 238: `for dir in skills commands agents; do` -- missing `hooks`).

### Directories in scope

| Directory | Phase 1 (first-run) | Phase 2 (shared sync) | Needs fix? |
|-----------|---------------------|----------------------|------------|
| `commands` | Flattened by find bug | Synced to shared (line 84) | Yes -- Phase 1 broken, no project overlay in Phase 2 |
| `skills` | Flattened by find bug | Synced to shared (line 83) | Yes -- Phase 1 broken, no project overlay in Phase 2 |
| `agents` | Flattened by find bug | Not synced | Yes -- Phase 1 broken, missing from Phase 2 entirely |
| `hooks` | Flattened by find bug | Not synced | Yes -- Phase 1 broken, missing from Phase 2 entirely |
| `reference` | Flattened by find bug | Not synced (intentional -- reference is project-specific, not shared) | Yes -- Phase 1 broken, no project overlay in Phase 2 |

## Files to Change

| File | Action | What Changes |
|------|--------|-------------|
| `/workspace/cli/scripts/init-claudio.sh` | Modify | Fix Phase 1 project overlay; add project dir sync and complete shared sync in Phase 2 |
| `/workspace/.devcontainer/init-claude-settings.sh` | Modify | Add `hooks` to shared plugins sync loop; add always-run project dir sync function |

## Implementation Steps

### Step 1: Fix Phase 1 project overlay in `init-claudio.sh` (line 30-34)

**What to do**: Replace the broken `find` command that flattens all project files with proper directory-aware sync logic that preserves subdirectory structure.

**Which file**: `/workspace/cli/scripts/init-claudio.sh`, lines 29-34.

**Key details**: Replace lines 29-34:
```bash
    # Copy project-specific overrides (if any)
    if [ -d "/workspace/.claude" ]; then
        # Skip credentials when copying project settings
        find /workspace/.claude -type f ! -name ".credentials.json" -exec cp {} "$CLAUDE_DIR/" \; 2>/dev/null || true
        echo "Applied project-specific settings"
    fi
```

With:
```bash
    # Overlay project-specific settings (if any)
    if [ -d "/workspace/.claude" ]; then
        # Copy top-level files (settings.json, mcp.json, etc.) -- skip credentials
        find /workspace/.claude -maxdepth 1 -type f ! -name ".credentials.json" -exec cp {} "$CLAUDE_DIR/" \; 2>/dev/null || true

        # Copy subdirectories preserving structure (project files override image defaults)
        for dir in commands reference skills agents hooks; do
            if [ -d "/workspace/.claude/$dir" ]; then
                mkdir -p "$CLAUDE_DIR/$dir"
                cp -r "/workspace/.claude/$dir/"* "$CLAUDE_DIR/$dir/" 2>/dev/null || true
            fi
        done
        echo "Applied project-specific settings"
    fi
```

**Gotchas**:
- The `find` MUST have `-maxdepth 1` to only copy top-level files, not recurse into subdirectories.
- The `for` loop uses `cp -r` (not `cp -ru`) because on first run there is no "newer" concern -- we want project files to unconditionally override image defaults.
- The directory list (`commands reference skills agents hooks`) matches the legacy script's list (line 43 of `init-claude-settings.sh`).

**Verification**: `bash -n /workspace/cli/scripts/init-claudio.sh` -- no syntax errors.

### Step 2: Add project directory sync to Phase 2 in `init-claudio.sh`

**What to do**: After the shared volume sync block (after line 102), add a new block that syncs project directories from `/workspace/.claude/` to `$CLAUDE_DIR` on every start, using `cp -ru` (update-only-newer).

**Which file**: `/workspace/cli/scripts/init-claudio.sh`

**Where to insert**: After line 102 (the closing `fi` of the shared volume block), before line 104 (Phase 3: Setup symlinks). This runs unconditionally (whether or not a shared volume is mounted).

**Key details**: Insert the following block:

```bash

# Sync project-specific directories on every start
# Ensures hooks, commands, skills, agents, and reference docs are
# kept up to date even on containers with existing volumes.
if [ -d "/workspace/.claude" ]; then
    echo "Syncing project directories..."

    # Sync top-level files (settings.json, mcp.json, etc.) -- skip credentials
    find /workspace/.claude -maxdepth 1 -type f ! -name ".credentials.json" -newer "$CLAUDE_DIR" -exec cp -u {} "$CLAUDE_DIR/" \; 2>/dev/null || true

    # Sync subdirectories -- project is source of truth, only update newer files
    for dir in commands reference skills agents hooks; do
        if [ -d "/workspace/.claude/$dir" ]; then
            mkdir -p "$CLAUDE_DIR/$dir"
            cp -ru "/workspace/.claude/$dir/"* "$CLAUDE_DIR/$dir/" 2>/dev/null || true
        fi
    done

    echo "Project directories synced"
fi
```

**Gotchas**:
- Uses `cp -ru` (not `cp -r`) because this runs on every start and should only overwrite older files.
- Top-level file sync uses `find -newer "$CLAUDE_DIR"` combined with `cp -u` for efficient timestamp-based sync.
- Excludes `.credentials.json` -- credentials are handled by the dedicated credentials sync above.
- On first run, both Phase 1 AND this block will run. Phase 1 uses `cp -r` (unconditional), this block uses `cp -ru` (newer-only). Since Phase 1 just copied the same files, `cp -ru` will find nothing newer -- harmless and idempotent.
- The `/workspace/.claude` directory is always available because the project root is bind-mounted at `/workspace`.

**Verification**: `bash -n /workspace/cli/scripts/init-claudio.sh` -- no syntax errors.

### Step 3: Add `hooks` and `agents` to shared plugins sync in `init-claudio.sh` (lines 80-85)

**What to do**: Add `hooks` and `agents` to the local-to-shared direction of the plugins sync. Also ensure their shared directories are created.

**Which file**: `/workspace/cli/scripts/init-claudio.sh`, lines 46-48 and 80-85.

**Key details**:

First, add shared directory creation at line 46-48. Change:
```bash
    mkdir -p "$CLAUDIO_SHARED/plugins/skills"
    mkdir -p "$CLAUDIO_SHARED/plugins/commands"
```
To:
```bash
    mkdir -p "$CLAUDIO_SHARED/plugins/skills"
    mkdir -p "$CLAUDIO_SHARED/plugins/commands"
    mkdir -p "$CLAUDIO_SHARED/plugins/hooks"
    mkdir -p "$CLAUDIO_SHARED/plugins/agents"
```

Then, update the local-to-shared sync at lines 83-84. Change:
```bash
        cp -ru "$CLAUDE_DIR/skills" "$CLAUDIO_SHARED/plugins/" 2>/dev/null || true
        cp -ru "$CLAUDE_DIR/commands" "$CLAUDIO_SHARED/plugins/" 2>/dev/null || true
```
To:
```bash
        cp -ru "$CLAUDE_DIR/skills" "$CLAUDIO_SHARED/plugins/" 2>/dev/null || true
        cp -ru "$CLAUDE_DIR/commands" "$CLAUDIO_SHARED/plugins/" 2>/dev/null || true
        cp -ru "$CLAUDE_DIR/hooks" "$CLAUDIO_SHARED/plugins/" 2>/dev/null || true
        cp -ru "$CLAUDE_DIR/agents" "$CLAUDIO_SHARED/plugins/" 2>/dev/null || true
```

**Gotchas**:
- The shared-to-local direction (line 82: `cp -ru "$CLAUDIO_SHARED/plugins/"* "$CLAUDE_DIR/"`) already copies ALL contents of the shared plugins directory to local. Since `hooks/` and `agents/` will now exist under `$CLAUDIO_SHARED/plugins/`, they will automatically sync from shared to local via this existing wildcard glob. No change needed for that direction.
- `cp -ru "$CLAUDE_DIR/hooks"` copies the entire directory (not its contents with `/*`). This matches the existing pattern for `skills` and `commands` on lines 83-84.

**Verification**: `grep -A6 'Plugins sync' /workspace/cli/scripts/init-claudio.sh` should show the four `cp -ru` lines.

### Step 4: Add `hooks` to legacy script shared plugins sync (`init-claude-settings.sh`, line 238)

**What to do**: Add `hooks` to the `for dir in ...` loop in the `sync_shared_plugins` function of the legacy script.

**Which file**: `/workspace/.devcontainer/init-claude-settings.sh`, line 238.

**Key details**: Change:
```bash
    for dir in skills commands agents; do
```
To:
```bash
    for dir in skills commands agents hooks; do
```

**Gotchas**: This is a one-line change. The existing loop body handles empty dirs gracefully.

**Verification**: `grep 'for dir in skills commands agents hooks' /workspace/.devcontainer/init-claude-settings.sh` should match.

### Step 5: Add always-run project dir sync to legacy script (`init-claude-settings.sh`)

**What to do**: Add a `sync_project_dirs` function that runs on every container start, syncing project directories from `$PROJECT_CLAUDE` to `$CLAUDE_HOME`. Insert after line 54 (the `fi` closing the first-init guard), before line 56 (the `sync_shared_credentials` function).

**Which file**: `/workspace/.devcontainer/init-claude-settings.sh`

**Where to insert**: After line 54, before line 56.

**Key details**: Insert:
```bash

# Sync project-specific .claude/ directories on every start
# Ensures hooks, commands, skills, agents, and reference docs
# are kept up to date even on containers with existing volumes.
sync_project_dirs() {
    if [ ! -d "$PROJECT_CLAUDE" ] || [ -z "$(ls -A "$PROJECT_CLAUDE" 2>/dev/null)" ]; then
        return 0
    fi

    echo "Syncing project-specific directories from $PROJECT_CLAUDE..."

    # Sync directories -- project files override local (cp -ru = update only newer)
    for dir in commands reference skills agents hooks; do
        if [ -d "$PROJECT_CLAUDE/$dir" ] && [ -n "$(ls -A "$PROJECT_CLAUDE/$dir" 2>/dev/null)" ]; then
            mkdir -p "$CLAUDE_HOME/$dir"
            cp -ru "$PROJECT_CLAUDE/$dir/"* "$CLAUDE_HOME/$dir/" 2>/dev/null || true
            echo "  Synced $dir from project."
        fi
    done

    # Sync top-level files (settings, etc.) -- exclude credentials
    find "$PROJECT_CLAUDE" -maxdepth 1 -type f ! -name ".credentials.json" -newer "$CLAUDE_HOME" -exec cp -u {} "$CLAUDE_HOME/" \; 2>/dev/null || true
}

# Call project dir sync
sync_project_dirs
```

Also update the else-branch message on line 53. Change:
```bash
    echo "$CLAUDE_HOME already initialized, skipping."
```
To:
```bash
    echo "$CLAUDE_HOME already initialized, skipping first-time setup."
```

**Gotchas**:
- Uses `cp -ru` for directory sync (update-only-newer), matching the pattern in `sync_shared_plugins`.
- Excludes `.credentials.json` since credentials have their own sync function.
- On first run, both the first-init block and this function run. The first-init block uses `cp -r`, then this function uses `cp -ru` which finds nothing newer. Idempotent, no conflict.

**Verification**: `bash -n /workspace/.devcontainer/init-claude-settings.sh` -- no syntax errors.

## Testing and Verification

### 1. Syntax check (both scripts)
```bash
bash -n /workspace/cli/scripts/init-claudio.sh
bash -n /workspace/.devcontainer/init-claude-settings.sh
```
Expected: No output (success) for both.

### 2. Test Phase 1 fix (first-run with fresh volume)
```bash
# Simulate first-run by removing the marker and resetting CLAUDE_DIR
TESTDIR=$(mktemp -d)
export CLAUDIO_HOME="$TESTDIR"
export CLAUDIO_SHARED="/nonexistent"
CLAUDE_DIR="$TESTDIR/claude"

# Run just Phase 1 manually or run the full script
bash /workspace/cli/scripts/init-claudio.sh

# Verify subdirectories were created with proper structure
ls "$TESTDIR/claude/hooks/"
# Expected: task-completed.sh  teammate-idle.sh

ls "$TESTDIR/claude/agents/"
# Expected: coordinator.md  implementer.md  planner.md  researcher.md  reviewer.md

ls "$TESTDIR/claude/commands/"
# Expected: core/  do-task.md  flesh-out.md  pipeline-deprecated.md  plan.md

# Verify top-level files were NOT flattened from subdirs
test -f "$TESTDIR/claude/task-completed.sh" && echo "BUG: still flattened" || echo "PASS: no flattening"

rm -rf "$TESTDIR"
```

### 3. Test Phase 2 project sync (existing volume)
```bash
# Create a temp dir simulating an existing CLAUDE_DIR with old hooks
TESTDIR=$(mktemp -d)
mkdir -p "$TESTDIR/claude/hooks"
echo "old-content" > "$TESTDIR/claude/hooks/task-completed.sh"
touch "$TESTDIR/.initialized"  # Mark as already initialized
export CLAUDIO_HOME="$TESTDIR"
export CLAUDIO_SHARED="/nonexistent"

bash /workspace/cli/scripts/init-claudio.sh

# Verify hooks were updated from project
diff "$TESTDIR/claude/hooks/task-completed.sh" /workspace/.claude/hooks/task-completed.sh
# Expected: no differences (or project version is newer and overwrote)

# Verify agents directory was created
ls "$TESTDIR/claude/agents/"
# Expected: coordinator.md  implementer.md  etc.

rm -rf "$TESTDIR"
```

### 4. Full container test
```bash
# Build image with changes
docker build -f Dockerfile.base -t claudio-base:test .

# Run container, verify init output
docker run --rm claudio-base:test sh -c '
    init-claudio
    echo "--- Hooks ---"
    ls -la ~/.claude/hooks/
    echo "--- Agents ---"
    ls -la ~/.claude/agents/
    echo "--- Commands ---"
    ls -la ~/.claude/commands/
'
```

### 5. Regression check
Verify credentials sync still works (not broken by changes):
```bash
# The credentials sync logic (lines 51-72) is untouched
# Confirm by visual inspection: no changes to that block
```

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| `cp -ru` glob expands to nothing in empty source dir | Low | Already mitigated by `2>/dev/null \|\| true` pattern used throughout the script |
| Project file overrides user's local customization | Medium | `cp -ru` only overwrites if source is newer. Project is intentionally source of truth. Users who need local overrides should use `settings.local.json` (which is gitignored and not synced). |
| Running both Phase 1 and project sync on first run | Low | Idempotent: Phase 1 uses `cp -r` (unconditional), project sync uses `cp -ru` (newer-only). Since Phase 1 just copied the same files, `cp -ru` finds nothing newer. |
| Shared volume `mkdir -p` for hooks/agents dirs on every start | Low | `mkdir -p` is idempotent and cheap. Same pattern already used for skills/commands. |
| Legacy script changes diverge from active script | Low | Both scripts use the same sync pattern and directory list. The legacy script is a fallback and may eventually be removed, but for now it should be consistent. |

## Open Questions

1. **Should `reference/` be included in the shared plugins bidirectional sync?** Currently `reference/` is only synced from the project directory, not to/from the shared volume. This seems intentional since reference docs are project-specific. The plan does NOT add `reference/` to the shared sync. If cross-container reference sharing is desired, it can be added later as a separate change.