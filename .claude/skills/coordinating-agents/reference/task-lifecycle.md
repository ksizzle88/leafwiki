# Task Lifecycle

## State Machine

```
                  ┌──────────────┐
                  │              │
  ┌──────┐    ┌──▼───┐    ┌────┴────┐    ┌──────┐
  │ todo │───▶│ in-   │───▶│ review  │───▶│ done │
  │      │    │progress│    │         │    │      │
  └──────┘    └───┬───┘    └────┬────┘    └──────┘
                  │             │
                  ◄─────────────┘
                  (reviewer rejects)
```

## Transitions

### todo → in-progress
- **Trigger**: Agent claims the task (`task-master set-status --id <id> --status in-progress`)
- **Requirements**: No blocking dependencies, task is properly scoped
- **Action**: Agent begins work

### in-progress → review
- **Trigger**: Implementation complete, tests pass
- **Requirements**: All code changes committed or staged
- **Action**: Reviewer agent dispatched

### review → done
- **Trigger**: Reviewer approves with no blocking issues
- **Requirements**: All feedback addressed
- **Action**: Task marked complete, parent task checked for completion

### review → in-progress
- **Trigger**: Reviewer finds issues requiring changes
- **Requirements**: Specific feedback provided
- **Action**: Implementer re-dispatched with reviewer feedback

## Task Hierarchy

```
Parent Task (epic-level)
├── Sub-task 1 (todo)
├── Sub-task 2 (in-progress)
├── Sub-task 3 (done)
└── Sub-task 4 (blocked by Sub-task 2)
```

- Parent task status reflects aggregate child status
- Parent moves to "done" only when all children are "done"
- Children can be worked in parallel unless explicitly blocked

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

## Best Practices

1. **Keep tasks atomic** — one clear deliverable per task
2. **Always include acceptance criteria** — how do we know it's done?
3. **Use dependencies sparingly** — prefer parallel-friendly task graphs
4. **Update status promptly** — stale boards mislead other agents
5. **Add implementation notes** — future sessions need context
