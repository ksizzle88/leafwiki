# Implementation Plan: Task #7 -- Add Agent Teams Support to Claudio (Hybrid Mode)

## Summary

This plan adds Claude Code Agent Teams as a complementary parallel-work capability alongside the existing sequential subagent pipeline. The changes install tmux in the base Docker image, configure Agent Teams via `settings.json` (env var + `teammateMode` + hooks), create two quality-gate hook scripts (`teammate-idle.sh` and `task-completed.sh`), create a new `/pipeline-team` slash command for team-based parallel workflows, expand permission pre-approvals for teammate friction reduction, update the init script to sync the hooks directory, and document when to use Teams vs subagents in `CLAUDE.md`. The existing `/pipeline` command remains completely unchanged.

## Research Findings

### 1. Agent Teams Feature Flag

The env var `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is already exported in the zsh profile at `/workspace/Dockerfile.base` line 136:
```
-a "export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
```

However, per the official documentation at https://code.claude.com/docs/en/agent-teams, the recommended way to persist this is via `settings.json`:
```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

The current `/workspace/.claude/settings.json` (lines 1-20) has `permissions`, `statusLine`, and `enabledPlugins` but no `env` or `hooks` or `teammateMode` keys.

### 2. tmux Not Installed

The apt-get layer at `/workspace/Dockerfile.base` lines 40-69 does NOT include `tmux`. It needs to be added for split-pane display mode. The official docs note: "Split panes require either tmux or iTerm2."

### 3. Hooks Configuration Format

Per the official hooks reference at https://code.claude.com/docs/en/hooks:

- Hooks are defined in `settings.json` under a top-level `"hooks"` key
- `TeammateIdle` and `TaskCompleted` do NOT support matchers (they always fire)
- Structure for these events:
```json
{
  "hooks": {
    "TeammateIdle": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/teammate-idle.sh"
          }
        ]
      }
    ]
  }
}
```

- **Exit code 0**: allow the action (teammate goes idle / task marked complete)
- **Exit code 2**: block the action -- stderr message is fed back to the model as feedback
- **JSON `{"continue": false, "stopReason": "..."}`**: stops the teammate entirely

- `TeammateIdle` input includes: `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`, `teammate_name`, `team_name`
- `TaskCompleted` input includes: `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`, `task_id`, `task_subject`, `task_description`, `teammate_name`, `team_name`

### 4. teammateMode Setting

Per the docs, `teammateMode` is a top-level key in settings.json:
```json
{
  "teammateMode": "auto"
}
```
Values: `"auto"` (default -- uses split panes if inside tmux, otherwise in-process), `"in-process"`, `"tmux"`.

### 5. Init Script Sync Gap

`/workspace/.devcontainer/init-claude-settings.sh` syncs these directories (line 43):
```bash
for dir in commands reference skills agents; do
```
And the shared plugins sync (line 238):
```bash
for dir in skills commands agents; do
```
Neither includes `hooks`. The new `.claude/hooks/` directory must be added to the project overlay sync loop (line 43).

### 6. .dockerignore Impact

`/workspace/.dockerignore` line 48 has `*.md` which excludes all `.md` files from the Docker build context. This means `.claude/commands/pipeline-team.md` will NOT be baked into the image -- it gets overlaid from `/workspace/.claude/` at container startup via the init script (same pattern as existing `pipeline.md`). The `.sh` hook scripts are NOT excluded by `.dockerignore` and will be included in the image.

### 7. Existing Command Pattern

`/workspace/.claude/commands/pipeline.md` (lines 1-5) uses this frontmatter format:
```
---
description: Run the full task pipeline (research -> plan -> implement -> review) for a Taskmaster task
argument-hint: <task-id>
allowed-tools: Agent, Bash(task-master *), Bash(npx task-studio*), Read, Glob, Grep
---
```

### 8. Existing Permission Pre-approvals

`/workspace/.claude/settings.json` lines 3-11 currently pre-approve:
```json
"allow": [
  "Bash(git:*)",
  "Bash(npm:*)",
  "Bash(node:*)",
  "Bash(docker:*)",
  "Bash(ls:*)",
  "Bash(find:*)",
  "Bash(REGISTRY_ENABLED=false /workspace/.git/hooks/pre-push)"
]
```

For Agent Teams teammate friction reduction, additional pre-approvals are needed for common file operations, testing, and build tools.

## Files to Change

| File | Action | What Changes |
|------|--------|-------------|
| `/workspace/Dockerfile.base` | Modify | Add `tmux` to apt-get layer (line 42-69) |
| `/workspace/.claude/settings.json` | Modify | Add `env`, `teammateMode`, `hooks`, and expanded `permissions.allow` entries |
| `/workspace/.claude/hooks/teammate-idle.sh` | Create | Quality gate script for TeammateIdle event |
| `/workspace/.claude/hooks/task-completed.sh` | Create | Quality gate script for TaskCompleted event |
| `/workspace/.claude/commands/pipeline-team.md` | Create | New slash command for parallel team-based workflows |
| `/workspace/.devcontainer/init-claude-settings.sh` | Modify | Add `hooks` to directory sync loop (line 43) |
| `/workspace/.claude/CLAUDE.md` | Modify | Add Agent Teams documentation section |

## Implementation Steps

### Step 1: Install tmux in Dockerfile.base

**What to do**: Add `tmux` to the apt-get install layer so split-pane mode is available.

**Which file**: `/workspace/Dockerfile.base`

**Key details**: Add `tmux \` to the apt-get install list at lines 42-69. Place it in the "Shell enhancements" section after `fzf` (line 55). The exact insertion point is between line 55 (`fzf \`) and line 56 (`# Build essentials`).

**Exact change**: After line 55 (`fzf \`), add:
```dockerfile
        tmux \
```

The result should look like:
```dockerfile
        # Shell enhancements
        zsh \
        fzf \
        tmux \
        # Build essentials (for native modules)
```

**Gotchas**:
- The backslash continuation at the end of `fzf \` is already present, so just add the new line with the same indentation (8 spaces) and trailing backslash.
- tmux is available in the Ubuntu 24.04 default repositories, so no additional PPAs are needed.

**Verification**:
```bash
# Syntax check the Dockerfile
docker build -f /workspace/Dockerfile.base --check /workspace 2>&1 | head -5
# Or simply verify the line is present:
grep -n 'tmux' /workspace/Dockerfile.base
```

---

### Step 2: Create the hooks directory and teammate-idle.sh script

**What to do**: Create `.claude/hooks/teammate-idle.sh` -- a quality gate that runs when a teammate is about to go idle. The script performs basic checks: verifies no syntax errors exist in recently modified shell scripts.

**Which file**: `/workspace/.claude/hooks/teammate-idle.sh` (new file)

**Key details**:
- The script receives JSON on stdin with fields: `session_id`, `cwd`, `teammate_name`, `team_name`, `hook_event_name`
- Exit 0 = allow teammate to go idle
- Exit 2 = block idle, stderr message fed back to teammate as feedback
- Must be executable (`chmod +x`)
- The script should be lightweight since it runs every time a teammate finishes

**Exact content**:
```bash
#!/bin/bash
# .claude/hooks/teammate-idle.sh
# Quality gate: runs when an Agent Teams teammate is about to go idle.
# Exit 0 = allow idle. Exit 2 = send stderr feedback and keep teammate working.

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
TEAMMATE=$(echo "$INPUT" | jq -r '.teammate_name // "unknown"')

# Check for uncommitted changes that look like incomplete work
# (files modified but not staged)
cd "$CWD" 2>/dev/null || exit 0

UNSTAGED=$(git diff --name-only 2>/dev/null | wc -l)
if [ "$UNSTAGED" -gt 0 ]; then
    MODIFIED_FILES=$(git diff --name-only 2>/dev/null | head -5)
    echo "Teammate '$TEAMMATE' has $UNSTAGED unstaged modified file(s). Please review and stage or revert before going idle:" >&2
    echo "$MODIFIED_FILES" >&2
    exit 2
fi

exit 0
```

**Gotchas**:
- Must use `>&2` for stderr output (that is what gets fed back to the model)
- The `jq` command is already installed in the base image (Dockerfile.base line 48)
- Must handle the case where `cwd` is not a git repo (the `2>/dev/null || exit 0` pattern)

**Verification**:
```bash
ls -la /workspace/.claude/hooks/teammate-idle.sh
# Should show the file exists and is executable
bash -n /workspace/.claude/hooks/teammate-idle.sh && echo "PASS: syntax ok"
```

---

### Step 3: Create the task-completed.sh hook script

**What to do**: Create `.claude/hooks/task-completed.sh` -- a quality gate that runs when a task is being marked complete. It performs basic validation checks.

**Which file**: `/workspace/.claude/hooks/task-completed.sh` (new file)

**Key details**:
- The script receives JSON on stdin with fields: `session_id`, `cwd`, `task_id`, `task_subject`, `task_description`, `teammate_name`, `team_name`, `hook_event_name`
- Exit 0 = allow task completion
- Exit 2 = block completion, stderr message fed back to the model
- Should check for basic quality signals

**Exact content**:
```bash
#!/bin/bash
# .claude/hooks/task-completed.sh
# Quality gate: runs when a task is being marked as completed.
# Exit 0 = allow completion. Exit 2 = block completion with feedback.

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // "unknown"')
TASK_ID=$(echo "$INPUT" | jq -r '.task_id // "unknown"')

cd "$CWD" 2>/dev/null || exit 0

# Check 1: Ensure no shell syntax errors in modified .sh files
MODIFIED_SH=$(git diff --name-only HEAD 2>/dev/null | grep '\.sh$' || true)
if [ -n "$MODIFIED_SH" ]; then
    ERRORS=""
    while IFS= read -r f; do
        if [ -f "$f" ] && ! bash -n "$f" 2>/dev/null; then
            ERRORS="${ERRORS}  - ${f}\n"
        fi
    done <<< "$MODIFIED_SH"
    if [ -n "$ERRORS" ]; then
        echo "Task '$TASK_SUBJECT' ($TASK_ID): shell syntax errors found in modified files:" >&2
        echo -e "$ERRORS" >&2
        echo "Fix syntax errors before marking this task complete." >&2
        exit 2
    fi
fi

# Check 2: Ensure no Dockerfile syntax issues if Dockerfile was modified
MODIFIED_DF=$(git diff --name-only HEAD 2>/dev/null | grep -i 'dockerfile' || true)
if [ -n "$MODIFIED_DF" ]; then
    while IFS= read -r f; do
        if [ -f "$f" ]; then
            # Basic check: ensure FROM instruction exists
            if ! grep -q '^FROM ' "$f" 2>/dev/null; then
                echo "Task '$TASK_SUBJECT' ($TASK_ID): $f appears to be missing a FROM instruction." >&2
                exit 2
            fi
        fi
    done <<< "$MODIFIED_DF"
fi

exit 0
```

**Gotchas**:
- The `git diff --name-only HEAD` pattern shows files changed vs the last commit, which captures work done by the teammate during the current session
- `bash -n` only checks syntax, not runtime correctness -- this is intentional for a lightweight gate
- Must handle repos where HEAD does not exist (fresh repos) -- the `2>/dev/null || true` pattern covers this

**Verification**:
```bash
ls -la /workspace/.claude/hooks/task-completed.sh
bash -n /workspace/.claude/hooks/task-completed.sh && echo "PASS: syntax ok"
```

---

### Step 4: Update settings.json with Agent Teams configuration

**What to do**: Add the `env`, `teammateMode`, `hooks`, and expanded `permissions.allow` entries to the project settings.json.

**Which file**: `/workspace/.claude/settings.json`

**Key details**: The current file (lines 1-20) contains only `permissions`, `statusLine`, and `enabledPlugins`. We need to add:

1. `"env"` block with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`
2. `"teammateMode": "auto"` (uses split panes inside tmux, in-process otherwise)
3. `"hooks"` block with `TeammateIdle` and `TaskCompleted` handlers
4. Additional permission pre-approvals for teammate friction reduction

**Exact new content for `/workspace/.claude/settings.json`**:
```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(npm:*)",
      "Bash(node:*)",
      "Bash(docker:*)",
      "Bash(ls:*)",
      "Bash(find:*)",
      "Bash(REGISTRY_ENABLED=false /workspace/.git/hooks/pre-push)",
      "Bash(cat:*)",
      "Bash(mkdir:*)",
      "Bash(cp:*)",
      "Bash(mv:*)",
      "Bash(rm:*)",
      "Bash(chmod:*)",
      "Bash(touch:*)",
      "Bash(echo:*)",
      "Bash(grep:*)",
      "Bash(wc:*)",
      "Bash(head:*)",
      "Bash(tail:*)",
      "Bash(sort:*)",
      "Bash(jq:*)",
      "Bash(python3:*)",
      "Bash(make:*)",
      "Bash(task-master:*)"
    ]
  },
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "teammateMode": "auto",
  "hooks": {
    "TeammateIdle": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/teammate-idle.sh"
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/task-completed.sh"
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  },
  "enabledPlugins": {
    "frontend-design@claude-plugins-official": true
  }
}
```

**Gotchas**:
- The hook `command` paths use `"$CLAUDE_PROJECT_DIR"` which is a Claude Code environment variable that resolves to the project root. This ensures hooks work regardless of the container's working directory. The double quotes around the variable are required for paths with spaces.
- `TeammateIdle` and `TaskCompleted` do NOT use the `matcher` field (it is silently ignored per docs). The outer object in the array has only `hooks`, no `matcher`.
- The expanded permission pre-approvals (`cat`, `mkdir`, `cp`, `mv`, `rm`, `chmod`, `touch`, `echo`, `grep`, `wc`, `head`, `tail`, `sort`, `jq`, `python3`, `make`, `task-master`) reduce teammate friction by pre-approving common development operations. This is the project-level settings.json, so it only applies to this project.
- Existing entries (`Bash(git:*)`, `Bash(npm:*)`, etc.) are preserved.

**Verification**:
```bash
# Validate JSON syntax
python3 -c "import json; json.load(open('/workspace/.claude/settings.json')); print('PASS: valid JSON')"
# Check hooks section exists
jq '.hooks | keys' /workspace/.claude/settings.json
# Expected: ["TaskCompleted", "TeammateIdle"]
```

---

### Step 5: Create the /pipeline-team slash command

**What to do**: Create a new slash command that instructs Claude to create an Agent Team for parallel task execution. This is the counterpart to the existing sequential `/pipeline` command.

**Which file**: `/workspace/.claude/commands/pipeline-team.md` (new file)

**Key details**: Follow the frontmatter pattern from `/workspace/.claude/commands/pipeline.md` (lines 1-5). The command should:
1. Accept a task ID as an argument
2. Read the task from Taskmaster
3. Instruct Claude to create an Agent Team with role-based teammates
4. Guide the team structure and task decomposition
5. Reference the existing pipeline stages (research, plan, implement, review) but execute them in parallel where possible

**Exact content**:
```markdown
---
description: Run a parallel agent team pipeline for a Taskmaster task (complementary to /pipeline which is sequential)
argument-hint: <task-id>
allowed-tools: Agent, Bash(task-master *), Bash(npx task-studio*), Read, Glob, Grep
---

# Pipeline-Team: Parallel Agent Team Pipeline for a Taskmaster Task

## Overview

Run a Taskmaster task using Claude Code Agent Teams for parallel execution. This is the parallel counterpart to `/pipeline` (which runs stages sequentially via subagents). Use this when the task has independent sub-problems that benefit from parallel exploration.

### When to Use This vs /pipeline

| Criteria | /pipeline (sequential) | /pipeline-team (parallel) |
|----------|----------------------|--------------------------|
| Task nature | Linear dependencies between stages | Independent sub-problems |
| Best for | Standard feature implementation | Research, refactoring, multi-module work |
| Coordination | Subagents report back to coordinator | Teammates communicate with each other |
| Token cost | Lower | Higher (each teammate has own context) |
| Speed | Slower (sequential) | Faster (parallel execution) |

### Pipeline Flow

```
1. Read the task from Taskmaster
2. Break it into parallel work streams
3. Create an agent team with role-based teammates
4. Teammates work in parallel, coordinating via shared task list
5. Lead synthesizes results and verifies completeness
6. Mark task done
```

## Step 0: Read the Task

Before creating a team, load the task and assess whether it benefits from parallel work.

```bash
task-master show $ARGUMENTS
```

```bash
task-master set-status --id=$ARGUMENTS --status=in-progress
```

Show the user the task title, description, and priority. If the task has dependencies that are not yet `done`, warn the user.

**Assess parallelizability**: Does this task have 2+ independent work streams? Examples:
- Research multiple approaches simultaneously
- Implement changes across separate modules
- Run different types of review (security, performance, tests) in parallel

If the task is purely sequential (each step depends on the previous), recommend using `/pipeline` instead.

## Step 1: Design the Team

Based on the task, propose a team structure. Common patterns:

### Pattern A: Research Team (3-4 teammates)
Use when exploring a problem space or investigating alternatives:
- **Researcher A**: Investigate approach/aspect 1
- **Researcher B**: Investigate approach/aspect 2
- **Devil's advocate**: Challenge findings from other teammates
- *Lead synthesizes findings into recommendations*

### Pattern B: Implementation Team (2-4 teammates)
Use when implementing changes across independent modules:
- **Module owner per area**: Each teammate owns a separate set of files
- *Lead coordinates integration points and runs final verification*

### Pattern C: Review Team (3 teammates)
Use for thorough parallel review of existing code or a PR:
- **Security reviewer**: Focus on security implications
- **Quality reviewer**: Check correctness, edge cases, error handling
- **Test reviewer**: Validate test coverage and completeness
- *Lead synthesizes findings into a unified report*

Present the proposed team structure to the user and get confirmation before proceeding.

## Step 2: Create the Team

Ask Claude to create the agent team. Include in the prompt:

1. The task description and context from Taskmaster
2. The agreed-upon team structure
3. Specific instructions for each teammate
4. What files/areas each teammate should focus on
5. How teammates should communicate findings

Example prompt to Claude:

```
Create an agent team for task #$ARGUMENTS: [task title].

Team structure:
- [teammate 1 name]: [specific instructions and file focus]
- [teammate 2 name]: [specific instructions and file focus]
- [teammate 3 name]: [specific instructions and file focus]

Each teammate should:
1. Read CLAUDE.md for project conventions
2. Work only on their assigned files/areas
3. Report findings via the shared task list
4. Message other teammates if they discover cross-cutting concerns

Quality gates are enforced via hooks:
- TeammateIdle hook checks for unstaged changes before allowing idle
- TaskCompleted hook validates shell script syntax and Dockerfile correctness

When all teammates finish, synthesize results and verify the overall task is complete.
```

## Step 3: Monitor and Guide

While the team works:
- Use Shift+Down to cycle through teammates (in-process mode)
- Check teammate progress via the shared task list (Ctrl+T)
- Redirect teammates if they go off track
- Resolve conflicts if two teammates need to touch the same file

## Step 4: Synthesize and Verify

After all teammates finish:
1. Review each teammate's contributions
2. Check for conflicts or inconsistencies between teammates' work
3. Run any end-to-end verification (tests, builds, linting)
4. Resolve any issues found

## Step 5: Complete the Task

```bash
task-master set-status --id=$ARGUMENTS --status=done
```

Report to the user:
- What each teammate accomplished
- Any issues found and resolved during synthesis
- Final verification results

## Rules

- **Assess before teaming.** Not every task benefits from parallel work. If the task is sequential, recommend `/pipeline` instead.
- **Avoid file conflicts.** Assign each teammate a distinct set of files. Two teammates editing the same file leads to overwrites.
- **Keep teams small.** 3-5 teammates is the sweet spot. More teammates means more coordination overhead and higher token costs.
- **Use the hooks.** The TeammateIdle and TaskCompleted hooks enforce basic quality gates. Do not disable them.
- **Clean up when done.** Ask the lead to clean up the team after the task is complete.
- **Respect user input.** If the user wants to change the team structure or redirect a teammate, pause and follow their direction.
```

**Gotchas**:
- This file is a `.md` file inside `.claude/commands/`, so it follows the same pattern as `pipeline.md`
- The `allowed-tools` in frontmatter matches the existing pipeline command
- Unlike `/pipeline`, this command does NOT dispatch subagents via the Agent tool directly -- it instructs Claude to use the native Agent Teams feature
- The `.dockerignore` `*.md` pattern means this file won't be in the Docker image but will be overlaid from `/workspace/.claude/` at container startup (same as existing commands)

**Verification**:
```bash
ls -la /workspace/.claude/commands/pipeline-team.md
# Verify frontmatter is valid
head -5 /workspace/.claude/commands/pipeline-team.md
```

---

### Step 6: Add hooks directory to init-claude-settings.sh sync loop

**What to do**: Add `hooks` to the list of directories that get synced from the project's `.claude/` directory into the container's `~/.claude/` during initialization.

**Which file**: `/workspace/.devcontainer/init-claude-settings.sh`

**Key details**: Line 43 currently reads:
```bash
        for dir in commands reference skills agents; do
```

Change it to:
```bash
        for dir in commands reference skills agents hooks; do
```

This ensures that hook scripts in `/workspace/.claude/hooks/` are copied to `~/.claude/hooks/` when the container initializes.

**Gotchas**:
- This is the project overlay section (lines 36-49), not the shared plugins sync section (line 238). The shared plugins sync at line 238 does NOT need to include `hooks` because hooks are project-specific, not shared across containers.
- The `cp -r` on line 46 will copy the hooks directory recursively, preserving the executable permission bits on `.sh` files.

**Verification**:
```bash
grep -n 'for dir in' /workspace/.devcontainer/init-claude-settings.sh
# Should show line 43 with: for dir in commands reference skills agents hooks; do
```

---

### Step 7: Update CLAUDE.md with Agent Teams documentation

**What to do**: Add a new section to `.claude/CLAUDE.md` documenting Agent Teams support, when to use Teams vs subagents, and examples.

**Which file**: `/workspace/.claude/CLAUDE.md`

**Key details**: Add the new section after the "Common Development Workflows" section (after line 297) and before the "Troubleshooting" section (line 299). The new section should explain:
1. What Agent Teams are and how they differ from subagents
2. When to use each approach
3. How to use the `/pipeline-team` command
4. Quality gate hooks
5. Configuration details

**Exact content to insert** after line 297 (after the "Testing Changes Without Disrupting Current Container" block ends):

```markdown

## Agent Teams (Parallel Pipeline)

Claudio supports two complementary modes for multi-agent work:

- **`/pipeline`** (sequential): Runs research -> plan -> implement -> review stages one at a time using subagents. Best for standard feature implementation where each stage depends on the previous.
- **`/pipeline-team`** (parallel): Creates an Agent Team where multiple teammates work simultaneously. Best for tasks with independent sub-problems.

### When to Use Agent Teams vs Subagents

| Criteria | Subagents (/pipeline) | Agent Teams (/pipeline-team) |
|----------|----------------------|------------------------------|
| Task type | Linear, dependent stages | Independent, parallelizable work |
| Communication | Report results back to coordinator only | Teammates message each other directly |
| Best for | Standard features, bug fixes | Research, multi-module refactoring, parallel review |
| Token cost | Lower | Higher (each teammate has its own context window) |
| Coordination | Coordinator manages everything | Shared task list with self-coordination |

### Quick Start

```bash
# Sequential pipeline (existing)
/pipeline 7

# Parallel team pipeline (new)
/pipeline-team 7
```

### Configuration

Agent Teams are enabled via settings.json:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "teammateMode": "auto"
}
```

The `teammateMode` setting controls display:
- `"auto"` (default): Uses split panes if inside a tmux session, in-process otherwise
- `"in-process"`: All teammates in one terminal. Use Shift+Down to cycle.
- `"tmux"`: Force split-pane mode (requires tmux, which is installed in the base image)

### Quality Gate Hooks

Two hooks enforce basic quality gates for Agent Teams:

- **TeammateIdle** (`.claude/hooks/teammate-idle.sh`): Runs when a teammate is about to go idle. Checks for unstaged modified files and sends feedback if found.
- **TaskCompleted** (`.claude/hooks/task-completed.sh`): Runs when a task is marked complete. Validates shell script syntax and Dockerfile correctness.

These hooks exit with code 2 to block the action and provide feedback to the teammate. Exit 0 allows the action to proceed.

### Team Patterns

Common team structures for different task types:

1. **Research Team** (3-4 teammates): Investigate different aspects of a problem simultaneously
2. **Implementation Team** (2-4 teammates): Each teammate owns a separate module or file set
3. **Review Team** (3 teammates): Security, quality, and test coverage reviewers in parallel

### Tips

- Keep teams small: 3-5 teammates is the sweet spot
- Assign distinct file sets to each teammate to avoid conflicts
- Use `Ctrl+T` to view the shared task list
- The lead coordinates everything; interact with the lead to steer the team
- Clean up the team after the task is complete
```

**Gotchas**:
- The CLAUDE.md is long (375 lines). Insert the new section cleanly between "Common Development Workflows" and "Troubleshooting".
- Do not modify any existing content -- only insert the new Agent Teams section.
- The examples reference `/pipeline` and `/pipeline-team` slash commands, both of which will exist after this task is complete.

**Verification**:
```bash
# Check the new section exists
grep -n 'Agent Teams' /workspace/.claude/CLAUDE.md
# Should find the new section header
grep -c 'pipeline-team' /workspace/.claude/CLAUDE.md
# Should return at least 3 (multiple references)
```

## Testing and Verification

### End-to-End Checks

1. **Dockerfile syntax validation**:
   ```bash
   docker build -f /workspace/Dockerfile.base --check /workspace 2>&1 | head -5
   ```
   Expected: No errors (or "check passed")

2. **settings.json validation**:
   ```bash
   python3 -c "import json; d=json.load(open('/workspace/.claude/settings.json')); assert 'hooks' in d; assert 'env' in d; assert 'teammateMode' in d; print('PASS: all keys present')"
   ```

3. **Hook scripts are executable and have valid syntax**:
   ```bash
   bash -n /workspace/.claude/hooks/teammate-idle.sh && echo "PASS: teammate-idle.sh syntax ok"
   bash -n /workspace/.claude/hooks/task-completed.sh && echo "PASS: task-completed.sh syntax ok"
   test -x /workspace/.claude/hooks/teammate-idle.sh && echo "PASS: teammate-idle.sh is executable"
   test -x /workspace/.claude/hooks/task-completed.sh && echo "PASS: task-completed.sh is executable"
   ```

4. **New command file exists with valid frontmatter**:
   ```bash
   head -5 /workspace/.claude/commands/pipeline-team.md
   ```
   Expected: Frontmatter block with `description`, `argument-hint`, `allowed-tools`

5. **Init script syncs hooks directory**:
   ```bash
   grep 'hooks' /workspace/.devcontainer/init-claude-settings.sh | head -3
   ```
   Expected: `for dir in commands reference skills agents hooks; do`

6. **CLAUDE.md updated with Agent Teams section**:
   ```bash
   grep -c 'Agent Teams' /workspace/.claude/CLAUDE.md
   ```
   Expected: Non-zero count

7. **tmux in Dockerfile**:
   ```bash
   grep 'tmux' /workspace/Dockerfile.base
   ```
   Expected: `tmux \` line present in apt-get layer

8. **Full Docker build smoke test** (optional, resource-intensive):
   ```bash
   docker build -f /workspace/Dockerfile.base -t claudio-test:agent-teams /workspace 2>&1 | tail -5
   ```
   Expected: Build succeeds

### Manual Verification

- After rebuilding the container, verify `tmux` is available: `which tmux`
- Verify the Agent Teams env var is set: `echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` (should be `1`)
- Verify hooks are in `~/.claude/hooks/` after container init
- Test `/pipeline-team` command by typing it in Claude Code (should show the command description)

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| tmux installation increases Docker image size | Low | tmux is ~600KB, negligible compared to Node.js and Claude Code CLI (~100MB+) |
| Hook scripts could block teammates unexpectedly | Medium | Scripts are conservative -- only check for obvious issues (unstaged files, syntax errors). Exit 0 is the default path. |
| Expanded permission pre-approvals could allow unintended operations | Medium | Pre-approvals are project-scoped (in `.claude/settings.json`, not user settings). Only standard dev tools are pre-approved. Destructive operations like `rm -rf /` are still flagged by Claude Code's built-in safety. |
| Agent Teams feature is experimental and may change | Medium | The env var and settings keys follow the official documentation. If the API changes, only `settings.json` needs updating. The hook scripts use standard bash and are independent of the Teams feature itself. |
| `*.md` in `.dockerignore` prevents pipeline-team.md from being baked into image | Low | This is the existing pattern -- all `.claude/commands/*.md` files are overlaid from the workspace at container startup, not from the Docker image. No change needed. |
| Hook command paths using `$CLAUDE_PROJECT_DIR` may not resolve in all contexts | Medium | `$CLAUDE_PROJECT_DIR` is a Claude Code built-in env var. If it is not set (e.g., running outside a project), the hook will fail gracefully (command not found, exit != 0/2, no blocking effect). |

## Open Questions

1. **Hook script aggressiveness**: The current hook scripts are intentionally conservative (only checking for unstaged files and syntax errors). Should they also run project-specific tests (e.g., `npm test`, `make lint`)? This would be more thorough but could slow down teammate workflows significantly. The current approach can be extended later by adding more checks to the existing scripts.

2. **Duplicate env var declaration**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is now set in two places: the Dockerfile zsh profile (line 136) and `settings.json`. The zsh profile export is the runtime fallback; the `settings.json` env block is the canonical Claude Code way. Consider removing the Dockerfile export in a follow-up cleanup task to avoid confusion, though having both does not cause any issues (env var just gets set twice to the same value).

3. **Permission pre-approval scope**: The expanded pre-approvals (`rm`, `cp`, `mv`, etc.) are added to the project-level `settings.json`. If the user has more restrictive preferences, those would need to be in `settings.local.json`. Is the current set of pre-approvals appropriate, or should some (like `rm`) be excluded from the project defaults?
