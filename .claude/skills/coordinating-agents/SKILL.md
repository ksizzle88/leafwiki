---
name: coordinating-agents
description: Orchestration playbook for coordinating specialized agents across complex tasks. Covers reading the task board, breaking work into sub-tasks, dispatching to agents, and managing task lifecycle.
user_invocable: false
---

# Coordinating Agents

This skill provides the orchestration knowledge for the coordinator agent and any session that needs to manage multi-agent workflows.

## Reading the Task Board

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

## Breaking Work Into Sub-Tasks

When a task is too large for a single agent:

1. Analyze the parent task scope
2. Identify independent work streams (can run in parallel)
3. Identify dependent work streams (must run sequentially)
4. Create sub-issues on GitHub:

```bash
gh issue create --title "Research auth patterns" --body "Sub-issue of #<parent-number>\n\n<description>" --label "status:pending" --label "priority:high"
gh issue create --title "Implement auth middleware" --body "Sub-issue of #<parent-number>\n\n<description>" --label "status:pending" --label "priority:high"
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

1. **GitHub Issues as shared board** — all agents read/write via the `gh` CLI against the same repository
2. **Status updates** — each agent updates issue status when starting/completing work
3. **Handoff notes** — use issue comments to pass context between sessions

## Agent Selection Guide

| Agent | Use When | Tools Available |
|-------|----------|-----------------|
| `researcher` | Need to understand code, find patterns, gather context | Read, Glob, Grep, WebSearch |
| `implementer` | Need to write/modify code, run tests | Read, Edit, Write, Bash, Glob, Grep |
| `reviewer` | Need quality/security review of changes | Read, Glob, Grep, Bash |

## Workflow Pattern

```
1. Read board → pick highest-priority issue
2. Analyze issue → break into sub-issues if needed
3. Dispatch researcher → gather context
4. Dispatch implementer → make changes (with researcher context)
5. Dispatch reviewer → verify changes
6. If reviewer finds issues → back to implementer
7. Update issue status → move to done
```

## Integration with Existing Commands

The coordinating workflow complements existing slash commands:
- `/plan-feature` — generates the plan that becomes GitHub Issues
- `/code-review` — can be used by the reviewer agent
- `/commit` — implementer uses after changes pass review

## Visual Board

The GitHub Issues web UI at the repository's Issues tab serves as the visual task board. Filter by labels (`status:pending`, `status:in-progress`, etc.) to view tasks by status.

## Reference

- `reference/dispatch-patterns.md` — Parallel vs sequential dispatch patterns
- `reference/task-lifecycle.md` — Task state machine and transitions
- `templates/sub-agent-brief.md` — Template for dispatching work to sub-agents
