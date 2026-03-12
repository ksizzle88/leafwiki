# Dispatch Patterns

## Same-Session Parallel Dispatch

When work streams are independent, spawn multiple agents simultaneously using the Task tool:

```
# Independent research tasks — run in parallel
Task(researcher): "Find all database query patterns in src/db/"
Task(researcher): "Document the API endpoint structure in src/routes/"
```

**When to use**: Information gathering, independent file analysis, parallel code reviews.

**Rules**:
- Each agent gets its own context — they cannot see each other's results
- The coordinator synthesizes results after all agents complete
- If one agent's output feeds another's input, use sequential dispatch instead

## Same-Session Sequential Dispatch

When tasks have dependencies, chain agents in order:

```
# Step 1: Research
researcher_result = Task(researcher): "Analyze the auth module structure"

# Step 2: Implement (uses research context)
Task(implementer): "Based on this analysis: {researcher_result}, add JWT validation"

# Step 3: Review
Task(reviewer): "Review the JWT changes in src/auth/"
```

**When to use**: Research → implement → review cycles, any dependent workflow.

## Cross-Session Patterns

For work too large for a single session or spanning multiple developers:

### GitHub Issues as Shared State

```bash
# Session 1: Coordinator creates issues
gh issue create --title "Implement auth" --body "..." --label "priority:high" --label "status:pending"

# Session 2: Worker picks up issue
gh issue list --label "priority:high" --label "status:pending" --state open
gh issue edit <number> --remove-label "status:pending" --add-label "status:in-progress"

# Session 2: Worker completes
gh issue edit <number> --remove-label "status:in-progress" --add-label "status:done" && gh issue close <number>
gh issue create --title "Review auth implementation" --label "status:pending"
```

### Handoff Protocol

When passing work between sessions:
1. Update issue body with what was done
2. Add implementation notes as issue comments
3. Reference specific files and line numbers
4. Set issue status to the next appropriate state

## Anti-Patterns

- **Don't dispatch reviewer before implementer finishes** — reviewer needs final code
- **Don't give implementer vague briefs** — always include file paths and specific requirements
- **Don't skip the researcher step** — context gathering prevents implementer from making wrong assumptions
- **Don't run more than 3 parallel agents** — diminishing returns, harder to synthesize
