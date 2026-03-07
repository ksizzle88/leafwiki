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
- TeammateIdle hook runs when a teammate is about to go idle
- TaskCompleted hook runs when a task is marked complete

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
