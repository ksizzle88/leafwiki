---
name: coordinating-agents
description: Orchestration playbook for coordinating specialized agents across complex tasks. Covers reading the task board, breaking work into sub-tasks, dispatching to agents, and managing task lifecycle.
user_invocable: false
---

# Coordinating Agents

This skill provides the orchestration knowledge for the coordinator agent and any session that needs to manage multi-agent workflows.

## Reading the Task Board

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

## Breaking Work Into Sub-Tasks

When a task is too large for a single agent:

1. Analyze the parent task scope
2. Identify independent work streams (can run in parallel)
3. Identify dependent work streams (must run sequentially)
4. Create sub-tasks via Taskmaster:

```bash
task-master add-subtask --parent <id> --title "Research auth patterns" --description "..."
task-master add-subtask --parent <id> --title "Implement auth middleware" --description "..."
```

## Dispatching to Agents

### Same-Session Dispatch (Parallel Task Tool)

Use the Task tool to spawn sub-agents within the current session:

```
Task(researcher): "Explore the authentication module and document all entry points"
Task(implementer): "Add rate limiting middleware to /api/auth endpoints"
Task(reviewer): "Review the changes in src/auth/ for security issues"
```

See `reference/dispatch-patterns.md` for detailed patterns.

### Cross-Session Coordination

For work that spans multiple Claude Code sessions:

1. **Taskmaster as shared board** — all agents read/write the same `.taskmaster/` directory
2. **Status updates** — each agent updates task status when starting/completing work
3. **Handoff notes** — use task descriptions to pass context between sessions

## Agent Selection Guide

| Agent | Use When | Tools Available |
|-------|----------|-----------------|
| `researcher` | Need to understand code, find patterns, gather context | Read, Glob, Grep, WebSearch |
| `implementer` | Need to write/modify code, run tests | Read, Edit, Write, Bash, Glob, Grep |
| `reviewer` | Need quality/security review of changes | Read, Glob, Grep, Bash |

## Workflow Pattern

```
1. Read board → pick highest-priority task
2. Analyze task → break into sub-tasks if needed
3. Dispatch researcher → gather context
4. Dispatch implementer → make changes (with researcher context)
5. Dispatch reviewer → verify changes
6. If reviewer finds issues → back to implementer
7. Update task status → move to done
```

## Integration with Existing Commands

The coordinating workflow complements existing slash commands:
- `/plan-feature` — generates the plan that becomes Taskmaster tasks
- `/code-review` — can be used by the reviewer agent
- `/commit` — implementer uses after changes pass review

## Task Studio (Visual Board)

Launch the Kanban UI for visual task management:

```bash
npx task-studio@latest
# Opens at http://localhost:5565
```

Columns: Todo → In Progress → Review → Done

## Reference

- `reference/dispatch-patterns.md` — Parallel vs sequential dispatch patterns
- `reference/task-lifecycle.md` — Task state machine and transitions
- `templates/sub-agent-brief.md` — Template for dispatching work to sub-agents
