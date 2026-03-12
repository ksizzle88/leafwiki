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
- **Trigger**: Agent claims the issue (`gh issue edit <number> --remove-label "status:pending" --add-label "status:in-progress"`)
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

## Best Practices

1. **Keep tasks atomic** — one clear deliverable per task
2. **Always include acceptance criteria** — how do we know it's done?
3. **Use dependencies sparingly** — prefer parallel-friendly task graphs
4. **Update status promptly** — stale boards mislead other agents
5. **Add implementation notes** — future sessions need context
