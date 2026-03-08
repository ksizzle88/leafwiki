# Implementation Plan: Task 5 -- Triage untracked directories

## Summary

Clean up the repository by removing legacy/stale tracked files, relocating misplaced documentation, untracking ephemeral state, and hardening `.gitignore` with missing patterns. Eight confirmed actions produce a single commit on the `develop` branch. Two additional optional disk-cleanup steps remove untracked/ignored stale directories.

## Research Findings

### Files confirmed tracked (via `git ls-files`)

| File/Directory | Tracked? | Notes |
|---|---|---|
| `.taskmaster/state.json` | Yes | Ephemeral local state; gitignored at `.gitignore:63-64` but still tracked |
| `feature-request-container-build-push.md` | Yes | 235-line legacy feature request; feature already shipped |
| `test-sync.sh` | Yes | 94-line early dev utility referencing obsolete branch names; stale |
| `.setup-security.md` | Yes | 212-line security setup checklist |
| `.agents/` (5 tracked files) | Yes | `feature-requests/` (2), `plans/` (3), `reviews/` (empty dir) |
| `workspace/.gitignore` | **No** | 0-byte empty file; already ignored by root gitignore `workspace/*` rule |

### Current `.gitignore` (`/workspace/.gitignore`, 64 lines)

- Line 24: `exploration-logging-strategy-2026-01-14/` -- exact match, needs wildcard
- Line 44: `.env` -- only exact name, missing `.env.local` and `.env.*.local`
- Missing patterns: `.venv/`, `dist/`, `build/`, `coverage/`, `.pytest_cache/`, `.nyc_output/`, `*.tmp`, `*.temp`, `desktop.ini`

### Cross-references

- `.agents/plans/container-build-push-implementation.md` line 3 has a relative link to `../../feature-request-container-build-push.md`. Both files are being deleted in the same commit -- no broken link concern.
- No other files reference `.setup-security.md`, `feature-request-container-build-push.md`, `test-sync.sh`, or any `.agents/` file.

### Destination for `.setup-security.md`

`/workspace/.claude/reference/` exists with 8 files (e.g., `cli-best-practices.md`, `github-cicd-best-practices.md`). No naming conflict with `setup-security.md`.

### Do-not-touch items (confirmed safe)

- `mpulse/CLAUDE.md` and `mpulse/.gitignore` -- intentionally tracked via negation at `.gitignore:28`
- `.claude-dev/` -- tracked with 2 files, leave as-is
- `.sandbox/`, `docs/external-repos/`, `workspace/*` -- already properly gitignored

## Files to Change

| File | Action | What Changes |
|---|---|---|
| `.taskmaster/state.json` | Untrack (`git rm --cached`) | Remove from git index only; file stays on disk |
| `feature-request-container-build-push.md` | Delete (`git rm`) | Remove tracked legacy feature request |
| `test-sync.sh` | Delete (`git rm`) | Remove tracked stale dev utility |
| `.setup-security.md` | Move (`git mv`) | Relocate to `.claude/reference/setup-security.md` |
| `.agents/` (5 files + empty dirs) | Delete (`git rm -r`) | Remove entire obsolete directory tree |
| `.gitignore` | Modify | Add missing patterns; change exploration rule to wildcard |
| `workspace/.gitignore` | Delete (`rm`) | Remove untracked 0-byte file from disk |

## Implementation Steps

### Step 1: Untrack `.taskmaster/state.json`

- **What to do**: Remove `.taskmaster/state.json` from the git index without deleting it from disk.
- **Command**: `git rm --cached .taskmaster/state.json`
- **Key details**: The `--cached` flag removes from index only. The file remains on disk. The existing gitignore rule at `.gitignore:63-64` will keep it ignored going forward.
- **Gotchas**: Must use `--cached`. Without it, the file gets deleted from disk. The commit diff will show a "deleted file" even though it stays on disk -- this is expected.
- **Verification**:
  ```bash
  git ls-files .taskmaster/state.json   # Should return empty
  test -f .taskmaster/state.json && echo "OK"  # File still on disk
  ```

### Step 2: Delete `feature-request-container-build-push.md`

- **What to do**: Remove the legacy feature request from the repo root.
- **Command**: `git rm feature-request-container-build-push.md`
- **Key details**: 235-line markdown at `/workspace/feature-request-container-build-push.md`. The feature it describes is already implemented in `.devcontainer/hooks/pre-push` and `.github/workflows/build-push-image.yml`.
- **Gotchas**: None. The only reference is from `.agents/plans/container-build-push-implementation.md:3`, also being deleted in step 5.
- **Verification**: `test ! -f feature-request-container-build-push.md`

### Step 3: Delete `test-sync.sh`

- **What to do**: Remove the stale dev utility script from the repo root.
- **Command**: `git rm test-sync.sh`
- **Key details**: 94-line bash script at `/workspace/test-sync.sh`. References obsolete branches (`feature-setup2`, `feature/dev_container_setup`). Not referenced anywhere.
- **Gotchas**: None.
- **Verification**: `test ! -f test-sync.sh`

### Step 4: Move `.setup-security.md` to `.claude/reference/`

- **What to do**: Relocate the security setup checklist to the reference docs directory.
- **Command**: `git mv .setup-security.md .claude/reference/setup-security.md`
- **Key details**: Destination: `/workspace/.claude/reference/setup-security.md`. The filename drops the leading dot (no longer hidden), matching the naming convention of the 8 existing files in that directory.
- **Gotchas**: None. No other files reference `.setup-security.md`.
- **Verification**: `test -f .claude/reference/setup-security.md && test ! -f .setup-security.md`

### Step 5: Delete `.agents/` directory

- **What to do**: Remove the entire `.agents/` directory tree (superseded by `.taskmaster/`).
- **Command**: `git rm -r .agents/`
- **Key details**: 5 tracked files:
  - `.agents/feature-requests/devcontainer-template-and-trainer2-integration.md`
  - `.agents/feature-requests/setup-production-ready-infra-repo.md`
  - `.agents/plans/container-build-push-implementation.md`
  - `.agents/plans/devcontainer-template-and-trainer2-integration.md`
  - `.agents/plans/setup-production-ready-infra-repo.md`
- **Gotchas**: The `reviews/` subdirectory is empty. If `git rm -r` leaves it behind, follow up with `rm -rf .agents/` to clean up empty directories.
- **Verification**: `test ! -d .agents`

### Step 6: Update `.gitignore`

- **What to do**: Edit `/workspace/.gitignore` to add missing patterns and change the exploration rule to a wildcard.
- **Which file**: `/workspace/.gitignore` (currently 64 lines)

**Write this exact content** (the complete file, ~75 lines):

```gitignore
# OS
.DS_Store
Thumbs.db
desktop.ini
.dev/*

# Node
node_modules/
dist/
build/

# Python
__pycache__/
*.pyc
.venv/

# VS Code
.vscode/

# Workspace - ignore all projects except .gitkeep
workspace/*
!workspace/.gitkeep

# External repo documentation (generated/local reference)
docs/external-repos/

# Exploration output
exploration-*/

# mpulse - only devcontainer is committed, rest lives in container volumes
mpulse/*
!mpulse/.devcontainer/

# Claude local settings (personal overrides)
.claude/settings.local.json
.claude/*.local.md
.sandbox/*

# Devcontainer local overrides (personal mounts/settings)
.devcontainer/devcontainer.local.json
.devcontainer/local-mounts.yml
.devcontainer/*.local.md

# Docker Compose local overrides (personal volume mounts)
docker-compose.override.yml

# Environment configuration
.env
.env.local
.env.*.local

# Logs
logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*
dev-debug.log

# Editor directories and files
.idea
*.suo
*.ntvs*
*.njsproj
*.sln
*.sw?

# Build and test output
coverage/
.pytest_cache/
.nyc_output/
*.tmp
*.temp

# Taskmaster ephemeral state
.taskmaster/state.json
```

**Summary of changes from current file**:
1. Added `desktop.ini` after `Thumbs.db` (OS section)
2. Added `dist/` and `build/` after `node_modules/` (Node section)
3. Added `.venv/` after `*.pyc` (Python section)
4. Changed comment `# Old exploration output` to `# Exploration output`
5. Changed `exploration-logging-strategy-2026-01-14/` to `exploration-*/`
6. Added `.env.local` and `.env.*.local` after `.env` (Environment section)
7. Added new section "Build and test output" with `coverage/`, `.pytest_cache/`, `.nyc_output/`, `*.tmp`, `*.temp`

**Gotchas**:
- The mpulse negation rules (`mpulse/*` / `!mpulse/.devcontainer/`) must remain exactly as-is.
- The `.env` line stays -- new patterns are additions, not replacements.
- Ensure a trailing newline at end of file.

**Verification**:
```bash
grep 'exploration-\*/' .gitignore        # matches
grep '.env.local' .gitignore             # matches
grep 'desktop.ini' .gitignore            # matches
grep '.venv/' .gitignore                 # matches
grep 'coverage/' .gitignore              # matches
grep '.pytest_cache/' .gitignore         # matches
grep '.nyc_output/' .gitignore           # matches
grep '!mpulse/.devcontainer/' .gitignore # still present (critical)
```

### Step 7: Delete `workspace/.gitignore`

- **What to do**: Remove the 0-byte untracked file from disk.
- **Command**: `rm /workspace/workspace/.gitignore`
- **Key details**: Not tracked by git. 0 bytes. Root `.gitignore` already covers `workspace/*` with `!workspace/.gitkeep` exception.
- **Gotchas**: Use plain `rm`, not `git rm`. This won't appear in the commit diff.
- **Verification**: `test ! -f workspace/.gitignore && test -f workspace/.gitkeep`

### Step 8: Stage and commit

- **What to do**: Stage `.gitignore`, review staged changes, commit.
- **Commands**:
  ```bash
  git add .gitignore
  git diff --cached --stat
  git status
  ```
- **Expected staged changes** (10 file operations):
  - deleted: `.agents/feature-requests/devcontainer-template-and-trainer2-integration.md`
  - deleted: `.agents/feature-requests/setup-production-ready-infra-repo.md`
  - deleted: `.agents/plans/container-build-push-implementation.md`
  - deleted: `.agents/plans/devcontainer-template-and-trainer2-integration.md`
  - deleted: `.agents/plans/setup-production-ready-infra-repo.md`
  - deleted: `.taskmaster/state.json`
  - deleted: `feature-request-container-build-push.md`
  - deleted: `test-sync.sh`
  - renamed: `.setup-security.md` -> `.claude/reference/setup-security.md`
  - modified: `.gitignore`
- **Commit message**: `chore: triage repo — remove stale files, relocate docs, harden gitignore`
- **Verification**: `git log --oneline -1` shows the commit. `git status` shows clean working tree (for tracked files).

## Testing and Verification

After all steps, run this consolidated check:

```bash
# 1. state.json untracked but on disk
git ls-files .taskmaster/state.json | wc -l   # 0
test -f .taskmaster/state.json && echo "PASS"

# 2. Stale root files gone
test ! -f feature-request-container-build-push.md && echo "PASS"
test ! -f test-sync.sh && echo "PASS"

# 3. Security doc relocated
test -f .claude/reference/setup-security.md && echo "PASS"
test ! -f .setup-security.md && echo "PASS"

# 4. .agents/ fully removed
test ! -d .agents && echo "PASS"

# 5. Gitignore patterns work
git check-ignore exploration-foo/       # Should output path
git check-ignore .env.local             # Should output path
git check-ignore .env.dev.local         # Should output path
git check-ignore desktop.ini            # Should output path
git check-ignore foo.tmp                # Should output path
git check-ignore node_modules/foo       # Should output path (existing rule)

# 6. workspace/.gitignore removed
test ! -f workspace/.gitignore && echo "PASS"
test -f workspace/.gitkeep && echo "PASS"

# 7. Staged file count
git diff HEAD~1 --name-only | wc -l    # Should be 10

# 8. DO NOT TOUCH items intact
git ls-files .claude-dev/ | wc -l                      # Should be >= 1
git ls-files mpulse/CLAUDE.md mpulse/.gitignore | wc -l  # Should be 2
grep '!mpulse/.devcontainer/' .gitignore && echo "PASS"
```

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| `git rm` without `--cached` on state.json | Low -- file is regenerated | Use `git rm --cached` explicitly. Verify file on disk after. |
| mpulse negation rules lost during `.gitignore` edit | High -- mpulse files untracked | Do not reorder or delete mpulse section. Verify `!mpulse/.devcontainer/` present after edit. Verify `git ls-files mpulse/CLAUDE.md mpulse/.gitignore` returns both. |
| `.setup-security.md` referenced elsewhere | Medium -- broken reference | Confirmed: no references found. Safe to move. |
| New gitignore patterns accidentally ignore tracked files | Medium -- silent data loss | All new patterns target directories/extensions not present as tracked files. Verify with `git status` after staging. |
| `exploration-*/` wildcard too broad | Low | Only matches dirs starting with `exploration-` at repo root. Intentional for future exploration output. |

## Open Questions

None. All 8 actions are fully specified and confirmed. The implementer can proceed without further input.
