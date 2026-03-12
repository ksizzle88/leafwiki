# Implementation Plan: Task 29 -- Migrate Task Management to GitHub Issues

## Summary

This plan migrates all 37 Taskmaster tasks from `.taskmaster/tasks/tasks.json` to GitHub Issues on `ksizzle88/claudio`, then updates every agent definition, slash command, and skill file to use `gh issue` / `gh label` CLI commands instead of `task-master`. The migration script creates status and priority labels, creates issues with correct labels and state (open/closed), records an old-ID-to-new-issue-number mapping, and does a second pass to inject dependency cross-references. After migration, all 12 files that reference `task-master` are updated to use the `gh` CLI directly. No wrapper script is created; agents call `gh` natively.

## Research Findings

### Task Data Structure

The source file is `/workspace/.taskmaster/tasks/tasks.json`. Structure:
```json
{
  "master": {
    "tasks": [ { "id": "1", "title": "...", "description": "...", "status": "...", "priority": "...", "dependencies": ["4"], "subtasks": [...], "details": "...", "updatedAt": "..." }, ... ]
  }
}
```

Key observations from `/workspace/.taskmaster/tasks/tasks.json`:
- 37 tasks total. 17 `done`, 1 `in-progress` (task 29 itself), 19 `pending`.
- Fields present on all tasks: `id`, `title`, `description`, `status`, `priority`, `dependencies`, `subtasks`, `updatedAt`.
- Optional fields present on some: `details` (tasks 28, 33), `testStrategy` (task 24).
- 6 tasks have dependencies: task 5 depends on [4], task 7 on [6], task 8 on [6], task 12 on [7, 11], task 13 on [9], task 14 on [9].
- 1 task has subtasks: task 24 has 1 subtask (id: 1, title: "Research persistence options for shared task board").
- Task descriptions can be long (up to ~8KB for task 5).

### GitHub CLI & Repo State

- `gh` CLI v2.87.3, authenticated as `ksizzle88` on `ksizzle88/claudio` (verified).
- Token scopes: `gist`, `read:org`, `repo` -- sufficient for label and issue management.
- 9 default GitHub labels exist (bug, documentation, duplicate, enhancement, etc.).
- Zero existing issues.

### Files Referencing `task-master`

Every file that contains `task-master` or `Taskmaster` CLI references (from grep at `/workspace/.claude`):

| File | Line Count | Nature of References |
|------|-----------|---------------------|
| `/workspace/.claude/agents/coordinator.md` | Line 4 (tools), 76, 78 | Tools declaration, `task-master list`, `task-master set-status` |
| `/workspace/.claude/agents/researcher.md` | Line 4 (tools), 26, 30, 64 | Tools declaration, `task-master show`, `task-master update-task` |
| `/workspace/.claude/agents/planner.md` | Line 4 (tools), 32, 97 | Tools declaration, `task-master show`, `task-master update-task` |
| `/workspace/.claude/agents/implementer.md` | Line 4 (tools), rest are inherited | Tools declaration only |
| `/workspace/.claude/agents/reviewer.md` | Line 4 (tools), 28 | Tools declaration, `task-master show` |
| `/workspace/.claude/commands/do-task.md` | Lines 4, 26, 30, 36, 56, 147, 166, 174 | Tools declaration, show, set-status, expand, update-task |
| `/workspace/.claude/commands/flesh-out.md` | Lines 4, 20, 30, 85, 93 | Tools declaration, show, update-task |
| `/workspace/.claude/commands/plan.md` | Lines 4, 22, 32, 177, 183 | Tools declaration, show, update-task |
| `/workspace/.claude/commands/pipeline-deprecated.md` | Lines 4, 102, 106, 120, 210, 227, 241, 278 | Tools declaration, show, set-status, expand, update-task |
| `/workspace/.claude/skills/coordinating-agents/SKILL.md` | Lines 17, 20, 23, 26, 39-40 | task-master list, show, next, add-subtask |
| `/workspace/.claude/skills/coordinating-agents/reference/dispatch-patterns.md` | Lines 45, 48, 49, 52, 53 | add-task, next, set-status |
| `/workspace/.claude/skills/coordinating-agents/reference/task-lifecycle.md` | Lines 20, 57-58, 61, 64-67, 70, 73-74 | Full CLI reference section |
| `/workspace/.claude/skills/testing-container-changes/SKILL.md` | Line 81 | `task-master --version` (verification example) |
| `/workspace/.claude/mcp.json` | Lines 3-5 | MCP server definition for taskmaster-ai |
| `/workspace/.claude/settings.json` | Line 10 | `Bash(task-master:*)` permission |
| `/workspace/.claude/CLAUDE.md` | Line 301 | "Run any Taskmaster task through a parallel agent team pipeline" |

### Command Mapping: task-master -> gh issue

| task-master Command | gh Equivalent | Notes |
|---------------------|--------------|-------|
| `task-master list` | `gh issue list --label "status:pending" --state open --json number,title,labels` | Filter by label; use `--state all` for everything |
| `task-master list --status <status>` | `gh issue list --label "status:<status>" --state open` (or `--state closed` for done) | |
| `task-master show <id>` | `gh issue view <number> --json number,title,body,labels,state` | Returns JSON or human-readable |
| `task-master set-status --id <id> --status <status>` | `gh issue edit <number> --remove-label "status:*" --add-label "status:<status>"` + `gh issue close <number>` if done, or `gh issue reopen <number>` if un-done | Two-step: relabel + state change |
| `task-master update-task --id <id> --prompt "..."` | `gh issue edit <number> --body "..."` or `gh issue comment <number> --body "..."` | Edit body for spec updates, comment for notes |
| `task-master next` | No direct equivalent | Coordinator picks manually (per task spec) |
| `task-master expand --id <id>` | Manual: create sub-issues and reference parent | |
| `task-master add-task --title "..." --description "..." --priority high` | `gh issue create --title "..." --body "..." --label "priority:high" --label "status:pending"` | |
| `task-master add-subtask --parent <id> --title "..."` | `gh issue create --title "..." --body "Sub-issue of #<parent>"` | |
| `task-master add-dependency --id <id> --depends-on <other-id>` | Edit issue body to add "Depends on #X" | |
| `task-master analyze-complexity` | No equivalent | Out of scope |

### Label Design

Status labels (mutually exclusive -- each issue has exactly one):
- `status:pending` -- #fbca04 (yellow) -- initial state for new work
- `status:in-progress` -- #0e8a16 (green) -- being worked on
- `status:review` -- #1d76db (blue) -- under review
- `status:done` -- #6f42c1 (purple) -- completed (issue also closed)
- `status:blocked` -- #d93f0b (red-orange) -- blocked by dependency
- `status:deferred` -- #c5def5 (light blue) -- postponed
- `status:cancelled` -- #e4e669 (pale yellow) -- will not be done

Priority labels (mutually exclusive):
- `priority:high` -- #b60205 (red)
- `priority:medium` -- #fbca04 (yellow)
- `priority:low` -- #0e8a16 (green)

## Files to Change

| File | Action | What Changes |
|------|--------|-------------|
| `/workspace/.taskmaster/migration/migrate-to-github-issues.sh` | **Create** | Migration script: create labels, create issues, map IDs, cross-reference dependencies |
| `/workspace/.taskmaster/migration/id-map.json` | **Create** (by script) | JSON mapping `{ "1": 42, "2": 43, ... }` of old task ID to new issue number |
| `/workspace/.claude/agents/coordinator.md` | **Modify** | Replace `task-master` tool permissions and commands with `gh issue` / `gh label` equivalents |
| `/workspace/.claude/agents/researcher.md` | **Modify** | Replace `task-master` tool permissions and commands |
| `/workspace/.claude/agents/planner.md` | **Modify** | Replace `task-master` tool permissions and commands |
| `/workspace/.claude/agents/implementer.md` | **Modify** | Replace `task-master` tool permission |
| `/workspace/.claude/agents/reviewer.md` | **Modify** | Replace `task-master` tool permissions and commands |
| `/workspace/.claude/commands/do-task.md` | **Modify** | Replace all `task-master` commands with `gh issue` equivalents |
| `/workspace/.claude/commands/flesh-out.md` | **Modify** | Replace all `task-master` commands with `gh issue` equivalents |
| `/workspace/.claude/commands/plan.md` | **Modify** | Replace all `task-master` commands with `gh issue` equivalents |
| `/workspace/.claude/commands/pipeline-deprecated.md` | **Modify** | Replace all `task-master` commands (even though deprecated, keep consistent) |
| `/workspace/.claude/skills/coordinating-agents/SKILL.md` | **Modify** | Replace task-master CLI examples with gh equivalents |
| `/workspace/.claude/skills/coordinating-agents/reference/dispatch-patterns.md` | **Modify** | Replace task-master CLI examples |
| `/workspace/.claude/skills/coordinating-agents/reference/task-lifecycle.md` | **Modify** | Replace full task-master CLI reference section |
| `/workspace/.claude/skills/testing-container-changes/SKILL.md` | **Modify** | Remove `task-master --version` from verification examples |
| `/workspace/.claude/mcp.json` | **Modify** | Remove `taskmaster-ai` MCP server entry |
| `/workspace/.claude/settings.json` | **Modify** | Replace `Bash(task-master:*)` with `Bash(gh:*)` in permissions |
| `/workspace/.claude/CLAUDE.md` | **Modify** | Update "Taskmaster task" reference to "GitHub Issue" |

## Implementation Steps

### Step 1: Create GitHub Labels

**What to do**: Create all 10 labels (7 status + 3 priority) on the `ksizzle88/claudio` repository using `gh label create`.

**Which files**: None (GitHub API only).

**Key details**: Run these commands:

```bash
# Status labels
gh label create "status:pending"      --color "fbca04" --description "Task is pending"
gh label create "status:in-progress"  --color "0e8a16" --description "Task is being worked on"
gh label create "status:review"       --color "1d76db" --description "Task is under review"
gh label create "status:done"         --color "6f42c1" --description "Task is complete"
gh label create "status:blocked"      --color "d93f0b" --description "Task is blocked"
gh label create "status:deferred"     --color "c5def5" --description "Task is deferred"
gh label create "status:cancelled"    --color "e4e669" --description "Task is cancelled"

# Priority labels
gh label create "priority:high"       --color "b60205" --description "High priority"
gh label create "priority:medium"     --color "fbca04" --description "Medium priority"
gh label create "priority:low"        --color "0e8a16" --description "Low priority"
```

**Gotchas**:
- `gh label create` will fail if a label already exists. Use `--force` flag to upsert, or check first.
- Color codes must be 6-char hex without `#` prefix.

**Verification**: `gh label list --limit 20` should show all 10 new labels plus the 9 existing defaults.

---

### Step 2: Create Migration Script

**What to do**: Write a bash script at `/workspace/.taskmaster/migration/migrate-to-github-issues.sh` that reads tasks.json and creates GitHub Issues.

**Which files**: `/workspace/.taskmaster/migration/migrate-to-github-issues.sh` (create)

**Key details**:

The script must:

1. **Read tasks.json** using `jq` to extract each task.
2. **Map status to labels**: `done` -> `status:done`, `in-progress` -> `status:in-progress`, `pending` -> `status:pending`.
3. **Map priority to labels**: `high` -> `priority:high`, `medium` -> `priority:medium`, `low` -> `priority:low`.
4. **Build issue body** for each task:
   ```
   > Migrated from Taskmaster task #<id>

   ## Description
   <task.description>

   ## Details
   <task.details if present>

   ## Subtasks
   - [ ] <subtask.title> (if any)

   ## Dependencies
   Depends on Taskmaster task(s): <dep-ids> (will be updated with issue cross-references)
   ```
5. **Create the issue**: `gh issue create --title "<task.title>" --body "<body>" --label "status:<status>" --label "priority:<priority>"`
6. **For done tasks**: Immediately close with `gh issue close <number>`
7. **Record mapping**: Append to a JSON file `{ "<old_id>": <new_issue_number> }`.
8. **Second pass**: After all issues are created, iterate over tasks with dependencies. For each, compute the new issue numbers from the mapping, then update the issue body to replace the placeholder dependency text with `Depends on #<new_issue_number>`.
9. **Handle task 24's subtask**: Include the subtask as a checkbox in the issue body.

**Script structure** (pseudocode):

```bash
#!/usr/bin/env bash
set -euo pipefail

TASKS_FILE="/workspace/.taskmaster/tasks/tasks.json"
MAP_FILE="/workspace/.taskmaster/migration/id-map.json"
REPO="ksizzle88/claudio"

# Initialize map
echo "{}" > "$MAP_FILE"

TASK_COUNT=$(jq '.master.tasks | length' "$TASKS_FILE")

# Pass 1: Create issues
for i in $(seq 0 $((TASK_COUNT - 1))); do
  task=$(jq ".master.tasks[$i]" "$TASKS_FILE")
  id=$(echo "$task" | jq -r '.id')
  title=$(echo "$task" | jq -r '.title')
  description=$(echo "$task" | jq -r '.description')
  status=$(echo "$task" | jq -r '.status')
  priority=$(echo "$task" | jq -r '.priority')
  details=$(echo "$task" | jq -r '.details // ""')
  deps=$(echo "$task" | jq -r '.dependencies | join(", ")')
  subtasks=$(echo "$task" | jq -r '.subtasks // [] | map("- [ ] " + .title) | join("\n")')

  # Build body
  body="> Migrated from Taskmaster task #${id}\n\n## Description\n${description}"
  if [ -n "$details" ]; then
    body="${body}\n\n## Details\n${details}"
  fi
  if [ -n "$subtasks" ]; then
    body="${body}\n\n## Subtasks\n${subtasks}"
  fi
  if [ -n "$deps" ]; then
    body="${body}\n\n## Dependencies\n_Depends on Taskmaster task(s): ${deps} (cross-references pending)_"
  fi

  # Create issue
  issue_url=$(gh issue create --repo "$REPO" --title "$title" --body "$(echo -e "$body")" --label "status:${status}" --label "priority:${priority}")
  issue_number=$(echo "$issue_url" | grep -o '[0-9]*$')

  # Close if done
  if [ "$status" = "done" ]; then
    gh issue close "$issue_number" --repo "$REPO"
  fi

  # Update map
  jq --arg id "$id" --argjson num "$issue_number" '. + {($id): $num}' "$MAP_FILE" > "${MAP_FILE}.tmp" && mv "${MAP_FILE}.tmp" "$MAP_FILE"

  echo "Created issue #${issue_number} for task ${id}: ${title}"
  sleep 1  # Rate limiting
done

# Pass 2: Update dependency cross-references
for i in $(seq 0 $((TASK_COUNT - 1))); do
  task=$(jq ".master.tasks[$i]" "$TASKS_FILE")
  id=$(echo "$task" | jq -r '.id')
  deps=$(echo "$task" | jq -r '.dependencies[]' 2>/dev/null || true)

  if [ -z "$deps" ]; then
    continue
  fi

  issue_number=$(jq -r --arg id "$id" '.[$id]' "$MAP_FILE")

  # Build cross-reference line
  dep_refs=""
  for dep_id in $deps; do
    dep_issue=$(jq -r --arg id "$dep_id" '.[$id]' "$MAP_FILE")
    dep_refs="${dep_refs} #${dep_issue}"
  done

  # Get current body and replace placeholder
  current_body=$(gh issue view "$issue_number" --repo "$REPO" --json body -q '.body')
  new_body=$(echo "$current_body" | sed "s|_Depends on Taskmaster task(s):.*_|Depends on${dep_refs}|")

  gh issue edit "$issue_number" --repo "$REPO" --body "$new_body"
  echo "Updated issue #${issue_number} with dependency cross-references:${dep_refs}"
  sleep 1
done

echo ""
echo "Migration complete. ID mapping saved to ${MAP_FILE}"
```

**Gotchas**:
- Task descriptions can contain special characters (quotes, backticks, etc.). The script must handle these safely. Use `jq -r` for extraction and pass bodies through temp files or heredocs, not inline shell strings.
- `gh issue create` returns the issue URL, not the number. Extract the number from the URL.
- Rate limiting: GitHub API has rate limits. Add a 1-second sleep between creations. For 37 tasks, this takes ~1 minute.
- The `status` value `pending` is the Taskmaster default; it maps to the `status:pending` label.
- Task 29 (this task) has `in-progress` status. The migration should create it with `status:in-progress` label and leave it open.
- The body format should use `echo -e` or a temp file to handle `\n` newlines properly. Prefer writing to a temp file and passing `--body-file`.

**Verification**: After running, `gh issue list --state all --limit 40 --json number,title,state,labels` should show 37 issues. `cat /workspace/.taskmaster/migration/id-map.json | jq 'length'` should return 37.

---

### Step 3: Run the Migration Script

**What to do**: Execute the migration script to create all 37 issues.

**Which files**: Script creates `/workspace/.taskmaster/migration/id-map.json`

**Key details**:
```bash
chmod +x /workspace/.taskmaster/migration/migrate-to-github-issues.sh
bash /workspace/.taskmaster/migration/migrate-to-github-issues.sh
```

**Gotchas**:
- The script should be idempotent or at least detectable -- if issues already exist, running it again will create duplicates. Only run once. If a partial run occurs, manually clean up with `gh issue list --state all --json number -q '.[].number' | xargs -I{} gh issue delete {} --yes`.
- If any issue creation fails mid-run, the map file will be partial. The script should handle this gracefully (check if map entry already exists before creating).

**Verification**:
- `gh issue list --state all --limit 50 --json number,title,state | jq length` should return 37
- `gh issue list --state closed --limit 50 --json number | jq length` should return 17 (done tasks)
- `gh issue list --state open --limit 50 --json number | jq length` should return 20 (19 pending + 1 in-progress)
- `cat /workspace/.taskmaster/migration/id-map.json | jq` should show a complete mapping
- `gh issue view <issue-for-task-5> --json body -q '.body'` should contain "Depends on #<issue-for-task-4>"

---

### Step 4: Update `/workspace/.claude/settings.json`

**What to do**: Replace the `Bash(task-master:*)` permission with `Bash(gh:*)` permission.

**Which file**: `/workspace/.claude/settings.json`

**Key details**: On line 10, change:
```json
"Bash(task-master:*)",
```
to:
```json
"Bash(gh:*)",
```

**Gotchas**: The `Bash(gh:*)` permission is broader than just `gh issue` -- it covers all `gh` subcommands. This is intentional since agents need `gh issue`, `gh label`, and potentially `gh api`.

**Verification**: `cat /workspace/.claude/settings.json | jq '.permissions.allow'` should include `Bash(gh:*)` and NOT include `Bash(task-master:*)`.

---

### Step 5: Update `/workspace/.claude/mcp.json`

**What to do**: Remove the `taskmaster-ai` MCP server entry. The file can either be emptied of servers or deleted. Since other MCP servers might be added later, keep the file with an empty `mcpServers` object.

**Which file**: `/workspace/.claude/mcp.json`

**Key details**: Replace the entire file content with:
```json
{
  "mcpServers": {}
}
```

**Gotchas**: If Claude Code reads this at startup and fails on empty mcpServers, we might need to delete the file entirely instead. The empty object should be fine based on Claude Code's schema.

**Verification**: `cat /workspace/.claude/mcp.json` shows empty mcpServers.

---

### Step 6: Update `/workspace/.claude/agents/coordinator.md`

**What to do**: Replace all `task-master` references with `gh issue` / `gh label` equivalents.

**Which file**: `/workspace/.claude/agents/coordinator.md`

**Key details** (line-by-line):

**Line 4 (tools declaration)**:
```
BEFORE: tools: Agent(researcher, planner, implementer, reviewer), TeamCreate, TeamDelete, SendMessage, Read, Glob, Grep, Bash(task-master *), Bash(bash .taskmaster/*), Bash(git *), Bash(npx task-studio*), Bash(mkdir *), Bash(chmod *), Write
AFTER:  tools: Agent(researcher, planner, implementer, reviewer), TeamCreate, TeamDelete, SendMessage, Read, Glob, Grep, Bash(gh issue *), Bash(gh label *), Bash(bash .taskmaster/*), Bash(git *), Bash(mkdir *), Bash(chmod *), Write
```
- Removes `Bash(task-master *)` and `Bash(npx task-studio*)`
- Adds `Bash(gh issue *)` and `Bash(gh label *)`

**Line 76** (`task-master list`):
```
BEFORE: - Read the board via `task-master list`
AFTER:  - Read the board via `gh issue list --state open --json number,title,labels --template '{{range .}}#{{.number}} {{.title}} {{range .labels}}[{{.name}}]{{end}}{{"\n"}}{{end}}'`
```

**Line 78** (`task-master set-status`):
```
BEFORE: - **The coordinator manages task STATUS only**: Use `task-master set-status --id <id> --status <status>`
AFTER:  - **The coordinator manages task STATUS only**: Use `gh issue edit <number> --remove-label "status:pending" --remove-label "status:in-progress" --remove-label "status:review" --remove-label "status:done" --remove-label "status:blocked" --add-label "status:<status>"`. If setting to `done`, also `gh issue close <number>`. If moving from `done` to another status, also `gh issue reopen <number>`.
```

**Lines 82-95** (Task Studio section): Remove the entire Task Studio section (lines 82-95) since Task Studio is a Taskmaster-specific UI that no longer applies. The GitHub Issues web UI replaces it.

**Gotchas**: The `gh issue list` template syntax uses Go template format. Make sure curly braces are not interpreted by bash. The coordinator reads task lists as human-readable text, so the template format matters for readability.

**Verification**: `grep -c "task-master" /workspace/.claude/agents/coordinator.md` should return 0.

---

### Step 7: Update `/workspace/.claude/agents/researcher.md`

**What to do**: Replace `task-master` tool permission and commands.

**Which file**: `/workspace/.claude/agents/researcher.md`

**Key details**:

**Line 4 (tools)**:
```
BEFORE: tools: Read, Glob, Grep, SendMessage, WebSearch, WebFetch, Bash(task-master *), Bash(jq *), Bash(ls *), Bash(git log *), Bash(git diff *)
AFTER:  tools: Read, Glob, Grep, SendMessage, WebSearch, WebFetch, Bash(gh issue *), Bash(jq *), Bash(ls *), Bash(git log *), Bash(git diff *)
```

**Line 26**:
```
BEFORE: Read the task from Taskmaster using `task-master show <id>`.
AFTER:  Read the task using `gh issue view <number> --json number,title,body,labels,state`.
```

**Line 30**:
```
BEFORE: Read any dependent or blocking tasks using `task-master show <dep-id>` for each dependency.
AFTER:  Read any dependent or blocking tasks by checking issue cross-references in the body and viewing them with `gh issue view <number>`.
```

**Line 64**:
```
BEFORE: task-master update-task --id=<id> --prompt="<full specification text>"
AFTER:  gh issue edit <number> --body "<updated body with full specification>"
```

Also update surrounding text references from "Taskmaster" to "GitHub Issues" where they describe the system (e.g., "Update the task in Taskmaster" -> "Update the issue on GitHub").

**Verification**: `grep -c "task-master" /workspace/.claude/agents/researcher.md` should return 0.

---

### Step 8: Update `/workspace/.claude/agents/planner.md`

**What to do**: Replace `task-master` tool permission and commands.

**Which file**: `/workspace/.claude/agents/planner.md`

**Key details**:

**Line 4 (tools)**:
```
BEFORE: tools: Read, Glob, Grep, SendMessage, WebSearch, WebFetch, Bash(task-master *), Bash(jq *), Bash(ls *), Bash(docker *), Bash(git log *), Bash(git diff *), Bash(git show *), Write(.taskmaster/**)
AFTER:  tools: Read, Glob, Grep, SendMessage, WebSearch, WebFetch, Bash(gh issue *), Bash(jq *), Bash(ls *), Bash(docker *), Bash(git log *), Bash(git diff *), Bash(git show *), Write(.taskmaster/**)
```

**Line 32**:
```
BEFORE: Read the task from Taskmaster using `task-master show <id>`.
AFTER:  Read the task using `gh issue view <number> --json number,title,body,labels,state`.
```

**Line 97**:
```
BEFORE: Use `task-master update-task --id=<id> --prompt="Implementation plan created at .taskmaster/plans/task-<id>-plan.md"` to note the plan on the task.
AFTER:  Use `gh issue comment <number> --body "Implementation plan created at .taskmaster/plans/task-<id>-plan.md"` to note the plan on the issue.
```

**Verification**: `grep -c "task-master" /workspace/.claude/agents/planner.md` should return 0.

---

### Step 9: Update `/workspace/.claude/agents/implementer.md`

**What to do**: Replace `task-master` tool permission.

**Which file**: `/workspace/.claude/agents/implementer.md`

**Key details**:

**Line 4 (tools)**:
```
BEFORE: tools: Read, Edit, Write, Bash, Glob, Grep, SendMessage, Bash(task-master *)
AFTER:  tools: Read, Edit, Write, Bash, Glob, Grep, SendMessage, Bash(gh issue *)
```

**Line 50**: Update the comment about not updating task status:
```
BEFORE: Do NOT update task status -- the coordinator does that after the reviewer passes.
AFTER:  Do NOT update issue status -- the coordinator does that after the reviewer passes.
```

**Verification**: `grep -c "task-master" /workspace/.claude/agents/implementer.md` should return 0.

---

### Step 10: Update `/workspace/.claude/agents/reviewer.md`

**What to do**: Replace `task-master` tool permission and commands.

**Which file**: `/workspace/.claude/agents/reviewer.md`

**Key details**:

**Line 4 (tools)**:
```
BEFORE: tools: Read, Glob, Grep, SendMessage, Bash(task-master *), Bash(bash .taskmaster/*), Bash(git diff *), Bash(git status *), Bash(git log *)
AFTER:  tools: Read, Glob, Grep, SendMessage, Bash(gh issue *), Bash(bash .taskmaster/*), Bash(git diff *), Bash(git status *), Bash(git log *)
```

**Line 28**:
```
BEFORE: - Read the task from Taskmaster using `task-master show <id>` to understand what was supposed to be accomplished
AFTER:  - Read the issue using `gh issue view <number> --json number,title,body,labels,state` to understand what was supposed to be accomplished
```

**Verification**: `grep -c "task-master" /workspace/.claude/agents/reviewer.md` should return 0.

---

### Step 11: Update `/workspace/.claude/commands/do-task.md`

**What to do**: Replace all `task-master` commands with `gh issue` equivalents. This is the most heavily referenced file.

**Which file**: `/workspace/.claude/commands/do-task.md`

**Key details**:

**Line 4 (allowed-tools)**:
```
BEFORE: allowed-tools: Agent, Bash(task-master *), Bash(npx task-studio*), Bash(bash .taskmaster/*), Bash(chmod *), Bash(git diff*), Bash(git status*), Bash(git log*), Bash(mkdir *), Read, Write, Glob, Grep
AFTER:  allowed-tools: Agent, Bash(gh issue *), Bash(gh label *), Bash(bash .taskmaster/*), Bash(chmod *), Bash(git diff*), Bash(git status*), Bash(git log*), Bash(mkdir *), Read, Write, Glob, Grep
```

**Line 26** (Step 0: show task):
```
BEFORE: task-master show $ARGUMENTS
AFTER:  gh issue view $ARGUMENTS --json number,title,body,labels,state
```

**Line 30** (Step 0: set in-progress):
```
BEFORE: task-master set-status --id=$ARGUMENTS --status=in-progress
AFTER:  gh issue edit $ARGUMENTS --remove-label "status:pending" --remove-label "status:blocked" --add-label "status:in-progress"
```

Note: `$ARGUMENTS` will now be the GitHub Issue number, not the old task ID.

**Line 36** (Step 0: expand recommendation):
```
BEFORE: recommend `task-master expand --id=$ARGUMENTS` to break it up first.
AFTER:  recommend breaking it into sub-issues manually and linking them from the parent issue.
```

**Line 56** (Step 1: update task with spec):
```
BEFORE: task-master update-task --id=$ARGUMENTS --prompt="<synthesized spec with Goal, Current State, Desired End State, Scope, Approach, Key Decisions, Acceptance Criteria, Dependencies & Risks>"
AFTER:  gh issue edit $ARGUMENTS --body "<synthesized spec with Goal, Current State, Desired End State, Scope, Approach, Key Decisions, Acceptance Criteria, Dependencies & Risks>"
```

**Line 147** (Step 4: set review status):
```
BEFORE: task-master set-status --id=$ARGUMENTS --status=review
AFTER:  gh issue edit $ARGUMENTS --remove-label "status:in-progress" --add-label "status:review"
```

**Line 166** (Step 4 PASS: set done):
```
BEFORE: task-master set-status --id=$ARGUMENTS --status=done
AFTER:  gh issue edit $ARGUMENTS --remove-label "status:review" --add-label "status:done" && gh issue close $ARGUMENTS
```

**Line 174** (Step 4 FAIL: back to in-progress):
```
BEFORE: task-master set-status --id=$ARGUMENTS --status=in-progress
AFTER:  gh issue edit $ARGUMENTS --remove-label "status:review" --add-label "status:in-progress"
```

Also update text that says "Taskmaster" to "GitHub Issues" where it describes the system.

**Verification**: `grep -c "task-master" /workspace/.claude/commands/do-task.md` should return 0.

---

### Step 12: Update `/workspace/.claude/commands/flesh-out.md`

**What to do**: Replace all `task-master` commands.

**Which file**: `/workspace/.claude/commands/flesh-out.md`

**Key details**:

**Line 4 (allowed-tools)**:
```
BEFORE: allowed-tools: Bash(task-master *), Read, Glob, Grep, WebSearch, WebFetch, Bash(jq *), Bash(ls *), Write(.taskmaster/**), Edit(.taskmaster/**)
AFTER:  allowed-tools: Bash(gh issue *), Read, Glob, Grep, WebSearch, WebFetch, Bash(jq *), Bash(ls *), Write(.taskmaster/**), Edit(.taskmaster/**)
```

**Line 20** (retrieve task):
```
BEFORE: task-master show $ARGUMENTS
AFTER:  gh issue view $ARGUMENTS --json number,title,body,labels,state
```

**Line 30** (read dependencies):
```
BEFORE: task-master show <dependency-id>
AFTER:  gh issue view <dependency-number>
```

**Line 85** (save specification):
```
BEFORE: task-master update-task --id=$ARGUMENTS --prompt="<the full expanded specification text>"
AFTER:  gh issue edit $ARGUMENTS --body "<the full expanded specification text>"
```

**Line 93** (confirm update):
```
BEFORE: task-master show $ARGUMENTS
AFTER:  gh issue view $ARGUMENTS
```

Update description text from "Taskmaster task" to "GitHub Issue" throughout.

**Verification**: `grep -c "task-master" /workspace/.claude/commands/flesh-out.md` should return 0.

---

### Step 13: Update `/workspace/.claude/commands/plan.md`

**What to do**: Replace all `task-master` commands.

**Which file**: `/workspace/.claude/commands/plan.md`

**Key details**:

**Line 4 (allowed-tools)**:
```
BEFORE: allowed-tools: Bash(task-master *), Read, Glob, Grep, WebSearch, WebFetch, Bash(jq *), Bash(ls *), Bash(docker *), Bash(git log *), Bash(git diff *), Bash(git show *), Write(.taskmaster/**), Edit(.taskmaster/**)
AFTER:  allowed-tools: Bash(gh issue *), Read, Glob, Grep, WebSearch, WebFetch, Bash(jq *), Bash(ls *), Bash(docker *), Bash(git log *), Bash(git diff *), Bash(git show *), Write(.taskmaster/**), Edit(.taskmaster/**)
```

**Line 22** (read task):
```
BEFORE: task-master show $ARGUMENTS
AFTER:  gh issue view $ARGUMENTS --json number,title,body,labels,state
```

**Line 32** (read dependencies):
```
BEFORE: task-master show <dependency-id>
AFTER:  gh issue view <dependency-number>
```

**Line 177** (update task with plan reference):
```
BEFORE: task-master update-task --id=$ARGUMENTS --prompt="Implementation plan created. See .taskmaster/plans/task-$ARGUMENTS-plan.md for the full technical plan including research findings, file change list, ordered implementation steps, testing strategy, and risk analysis."
AFTER:  gh issue comment $ARGUMENTS --body "Implementation plan created. See .taskmaster/plans/task-$ARGUMENTS-plan.md for the full technical plan including research findings, file change list, ordered implementation steps, testing strategy, and risk analysis."
```

**Line 183** (confirm update):
```
BEFORE: task-master show $ARGUMENTS
AFTER:  gh issue view $ARGUMENTS
```

Update description text throughout.

**Verification**: `grep -c "task-master" /workspace/.claude/commands/plan.md` should return 0.

---

### Step 14: Update `/workspace/.claude/commands/pipeline-deprecated.md`

**What to do**: Apply the same task-master -> gh issue changes as the other command files. Even though deprecated, keep it consistent in case anyone references it.

**Which file**: `/workspace/.claude/commands/pipeline-deprecated.md`

**Key details**: Same pattern as do-task.md. Replace:
- Line 4: `Bash(task-master *)` -> `Bash(gh issue *)` in allowed-tools
- Line 102: `task-master show` -> `gh issue view`
- Line 106: `task-master set-status` -> `gh issue edit` (label swap)
- Line 120: `task-master update-task` -> `gh issue edit`
- Line 210: `task-master set-status --status=review` -> `gh issue edit` (label swap)
- Line 227: `task-master set-status --status=done` -> `gh issue edit` + `gh issue close`
- Line 241: `task-master set-status --status=in-progress` -> `gh issue edit` (label swap)
- Line 278: `task-master expand` -> breaking into sub-issues manually

**Verification**: `grep -c "task-master" /workspace/.claude/commands/pipeline-deprecated.md` should return 0.

---

### Step 15: Update `/workspace/.claude/skills/coordinating-agents/SKILL.md`

**What to do**: Replace all task-master CLI examples.

**Which file**: `/workspace/.claude/skills/coordinating-agents/SKILL.md`

**Key details**:

Replace the "Reading the Task Board" section (lines 12-27):
```
BEFORE:
Use Taskmaster MCP (automatically available via `.claude/mcp.json`) or the CLI:
```bash
# List all tasks
task-master list
# List tasks by status
task-master list --status in-progress
# Get task details
task-master show <task-id>
# Get next recommended task
task-master next
```

AFTER:
Use the GitHub CLI to manage the issue board:
```bash
# List all open issues
gh issue list --state open --json number,title,labels
# List issues by status
gh issue list --label "status:in-progress" --state open
# Get issue details
gh issue view <issue-number> --json number,title,body,labels,state
# List by priority
gh issue list --label "priority:high" --state open
```
```

Replace the "Breaking Work Into Sub-Tasks" section (lines 38-41):
```
BEFORE:
task-master add-subtask --parent <id> --title "Research auth patterns" --description "..."
task-master add-subtask --parent <id> --title "Implement auth middleware" --description "..."

AFTER:
gh issue create --title "Research auth patterns" --body "Sub-issue of #<parent-number>\n\n<description>" --label "status:pending" --label "priority:high"
gh issue create --title "Implement auth middleware" --body "Sub-issue of #<parent-number>\n\n<description>" --label "status:pending" --label "priority:high"
```

Replace the "Cross-Session Coordination" text (line 61):
```
BEFORE: **Taskmaster as shared board** — all agents read/write the same `.taskmaster/` directory
AFTER:  **GitHub Issues as shared board** — all agents read/write via the `gh` CLI against the same repository
```

Remove the Task Studio section (lines 92-99) or replace with a note that the GitHub Issues web UI at `https://github.com/ksizzle88/claudio/issues` serves as the visual board.

**Verification**: `grep -c "task-master" /workspace/.claude/skills/coordinating-agents/SKILL.md` should return 0.

---

### Step 16: Update `/workspace/.claude/skills/coordinating-agents/reference/dispatch-patterns.md`

**What to do**: Replace task-master CLI examples.

**Which file**: `/workspace/.claude/skills/coordinating-agents/reference/dispatch-patterns.md`

**Key details**:

Replace lines 44-53 (Cross-Session Patterns):
```
BEFORE:
# Session 1: Coordinator creates tasks
task-master add-task --title "Implement auth" --description "..." --priority high
# Session 2: Worker picks up task
task-master next
task-master set-status --id <id> --status in-progress
# Session 2: Worker completes
task-master set-status --id <id> --status done
task-master add-task --title "Review auth implementation" --status todo

AFTER:
# Session 1: Coordinator creates issues
gh issue create --title "Implement auth" --body "..." --label "priority:high" --label "status:pending"
# Session 2: Worker picks up issue
gh issue list --label "priority:high" --label "status:pending" --state open
gh issue edit <number> --remove-label "status:pending" --add-label "status:in-progress"
# Session 2: Worker completes
gh issue edit <number> --remove-label "status:in-progress" --add-label "status:done" && gh issue close <number>
gh issue create --title "Review auth implementation" --label "status:pending"
```

**Verification**: `grep -c "task-master" /workspace/.claude/skills/coordinating-agents/reference/dispatch-patterns.md` should return 0.

---

### Step 17: Update `/workspace/.claude/skills/coordinating-agents/reference/task-lifecycle.md`

**What to do**: Replace the full Taskmaster CLI reference section with gh equivalents.

**Which file**: `/workspace/.claude/skills/coordinating-agents/reference/task-lifecycle.md`

**Key details**:

Replace line 20 (`task-master set-status`):
```
BEFORE: - **Trigger**: Agent claims the task (`task-master set-status --id <id> --status in-progress`)
AFTER:  - **Trigger**: Agent claims the issue (`gh issue edit <number> --remove-label "status:pending" --add-label "status:in-progress"`)
```

Replace the entire "Taskmaster CLI Reference" section (lines 53-74):
```
BEFORE:
## Taskmaster CLI Reference
```bash
# Create tasks
task-master add-task --title "..." --description "..." --priority high
task-master add-subtask --parent <id> --title "..."
# Status management
task-master set-status --id <id> --status <todo|in-progress|review|done>
# Query tasks
task-master list                    # All tasks
task-master list --status todo      # Filter by status
task-master next                    # AI-recommended next task
task-master show <id>               # Full task details
# Dependencies
task-master add-dependency --id <id> --depends-on <other-id>
# Complexity analysis
task-master analyze-complexity      # AI analyzes task complexity
task-master expand --id <id>        # Break task into sub-tasks
```

AFTER:
## GitHub Issues CLI Reference
```bash
# Create issues
gh issue create --title "..." --body "..." --label "priority:high" --label "status:pending"
# Create sub-issues (reference parent in body)
gh issue create --title "..." --body "Sub-issue of #<parent>" --label "status:pending"
# Status management (swap labels + open/close)
gh issue edit <number> --remove-label "status:pending" --add-label "status:in-progress"
gh issue edit <number> --remove-label "status:in-progress" --add-label "status:done" && gh issue close <number>
# Query issues
gh issue list --state all --json number,title,labels    # All issues
gh issue list --label "status:pending" --state open     # Filter by status
gh issue list --label "priority:high" --state open      # Filter by priority
gh issue view <number>                                  # Full issue details
# Dependencies (add to issue body)
# Edit issue body to include "Depends on #<number>"
```
```

**Verification**: `grep -c "task-master" /workspace/.claude/skills/coordinating-agents/reference/task-lifecycle.md` should return 0.

---

### Step 18: Update `/workspace/.claude/skills/testing-container-changes/SKILL.md`

**What to do**: Remove the `task-master --version` line from the verification examples.

**Which file**: `/workspace/.claude/skills/testing-container-changes/SKILL.md`

**Key details**: On line 81, remove:
```
task-master --version
```

Or replace with `gh --version` if a replacement verification command is needed.

**Verification**: `grep -c "task-master" /workspace/.claude/skills/testing-container-changes/SKILL.md` should return 0.

---

### Step 19: Update `/workspace/.claude/CLAUDE.md`

**What to do**: Update the single reference to "Taskmaster task" in the Task Pipeline section.

**Which file**: `/workspace/.claude/CLAUDE.md`

**Key details**: On line 301, change:
```
BEFORE: Run any Taskmaster task through a parallel agent team pipeline:
AFTER:  Run any GitHub Issue through a parallel agent team pipeline:
```

Also update the `/do-task` description and any surrounding text that implies Taskmaster is the backing store. The argument hint should note it takes a GitHub Issue number.

**Verification**: `grep -ci "taskmaster" /workspace/.claude/CLAUDE.md` should return 0 (case-insensitive check). Note: references to `.taskmaster/` directory paths are fine -- those are directory names, not tool references.

---

## Testing & Verification

### Acceptance Criterion 1: All 37 tasks exist as GitHub Issues
```bash
gh issue list --state all --limit 50 --json number,title,state,labels | jq length
# Expected: 37
```

### Acceptance Criterion 2: Correct labels (status + priority) and state (open/closed)
```bash
# Check done tasks are closed
gh issue list --state closed --label "status:done" --limit 50 --json number | jq length
# Expected: 17

# Check pending tasks are open with correct label
gh issue list --state open --label "status:pending" --limit 50 --json number | jq length
# Expected: 19

# Check in-progress task is open
gh issue list --state open --label "status:in-progress" --limit 50 --json number | jq length
# Expected: 1
```

### Acceptance Criterion 3: Dependencies noted as cross-references
```bash
# Check task 5 (depends on task 4) has "Depends on #<issue-for-4>" in body
TASK5_ISSUE=$(jq -r '.["5"]' /workspace/.taskmaster/migration/id-map.json)
TASK4_ISSUE=$(jq -r '.["4"]' /workspace/.taskmaster/migration/id-map.json)
gh issue view $TASK5_ISSUE --json body -q '.body' | grep -o "Depends on #${TASK4_ISSUE}"
# Expected: "Depends on #<number>"

# Check task 12 (depends on 7 and 11) has both references
TASK12_ISSUE=$(jq -r '.["12"]' /workspace/.taskmaster/migration/id-map.json)
gh issue view $TASK12_ISSUE --json body -q '.body' | grep "Depends on"
# Expected: contains both issue numbers for tasks 7 and 11
```

### Acceptance Criterion 4: Coordinator uses gh issue commands
```bash
grep -c "task-master" /workspace/.claude/agents/coordinator.md
# Expected: 0
grep -c "gh issue" /workspace/.claude/agents/coordinator.md
# Expected: > 0
```

### Acceptance Criterion 5: All slash commands use gh issue commands
```bash
for f in /workspace/.claude/commands/do-task.md /workspace/.claude/commands/flesh-out.md /workspace/.claude/commands/plan.md; do
  echo "$f: $(grep -c 'task-master' "$f") task-master refs"
done
# Expected: 0 for each file
```

### Acceptance Criterion 6: All agent definitions have updated tool permissions
```bash
for f in /workspace/.claude/agents/*.md; do
  echo "$(basename $f): $(grep -c 'task-master' "$f") task-master refs"
done
# Expected: 0 for each file
```

### Acceptance Criterion 7: Migration mapping file exists
```bash
cat /workspace/.taskmaster/migration/id-map.json | jq 'length'
# Expected: 37
cat /workspace/.taskmaster/migration/id-map.json | jq 'to_entries | map(select(.value > 0)) | length'
# Expected: 37 (all values are positive issue numbers)
```

### Full Sweep: No task-master references remain
```bash
grep -r "task-master" /workspace/.claude/ --include="*.md" --include="*.json" -l
# Expected: no output (no files contain task-master)
# Exception: if .taskmaster/ directory name is mentioned as a path, that's fine
grep -r "task-master" /workspace/.claude/ --include="*.md" --include="*.json" | grep -v ".taskmaster/" | grep -v "Taskmaster task #"
# Expected: no output
```

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Migration script creates duplicate issues if run twice | Medium | Script outputs clear log. If re-run needed, delete all issues first with `gh issue list --state all --json number -q '.[].number' \| xargs -I{} gh issue delete {} --yes` |
| GitHub API rate limiting during 37-issue creation | Low | 1-second sleep between API calls. 37 tasks takes ~2 minutes. GitHub allows 5000 requests/hour for authenticated users. |
| Task descriptions with special chars break `gh issue create` | High | Use `--body-file` with temp files instead of inline strings. Use `jq -r` for extraction. |
| `gh issue edit --remove-label` fails if label not present | Medium | The `--remove-label` flag silently ignores non-existent labels in recent gh versions. Test this before relying on it. Alternative: use `gh api` to manage labels atomically. |
| Agents confused by new command syntax during transition | Medium | All files updated atomically in one implementation pass. No partial migration state. |
| `$ARGUMENTS` in slash commands now means issue number, not task ID | Medium | After migration, the ID mapping file documents the correspondence. Update any documentation that references old task IDs. |
| Loss of `task-master next` (AI-recommended next task) | Low | Task spec explicitly says coordinator picks manually. Not a regression. |
| MCP server removal breaks something | Low | The taskmaster-ai MCP server is only used by task-master. Removing it has no side effects on other functionality. |

## Open Questions

1. **Should the migration script handle re-runs gracefully?** The simplest approach is "run once, clean up manually if it fails partway." A more robust approach would check for existing issues by title before creating. Recommendation: simple approach, with clear instructions for cleanup.

2. **Should we keep `.taskmaster/tasks/tasks.json` after migration?** It serves as a historical record and the migration mapping references it. Recommendation: keep it in place but do not modify it going forward. Add a note in the file or a README explaining it is archived.

3. **Task 24 subtask handling**: Task 24 has a subtask (id: 1, "Research persistence options for shared task board"). However, task 25 has the exact same title. Should the subtask be a checkbox in issue 24's body, or should it be a separate issue cross-referenced from issue 24? Recommendation: include as a checkbox in issue 24's body, since task 25 already covers it as a standalone issue.

4. **Should the `pipeline-deprecated.md` file be updated or simply deleted?** It is already marked as deprecated. Recommendation: update it for consistency, since someone might reference it. But deleting it is also reasonable -- implementer should decide based on coordinator guidance.
