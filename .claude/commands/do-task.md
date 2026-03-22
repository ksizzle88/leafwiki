---
description: Run a GitHub Issue through parallel agent teams (research, plan, implement, review)
argument-hint: <issue-number>
allowed-tools: Agent, Bash(gh issue *), Bash(gh project *), Bash(gh label *), Bash(gh auth *), Bash(bash .taskmaster/*), Bash(chmod *), Bash(git diff*), Bash(git status*), Bash(git log*), Bash(mkdir *), Read, Write, Glob, Grep
---

# Do Task: Parallel Agent Team Pipeline

## Overview

Run a GitHub Issue through a parallel agent team pipeline. You are the coordinator -- you dispatch agent teams, review their output at each stage gate, and decide whether to proceed, retry, or stop. You never write code directly.

### Stages

```
0. Read Task         -- load issue, set in-progress
1. Research Team     -- 2-3 parallel researchers explore different aspects
2. Plan + Test       -- planner + test author work in parallel
3. Implement         -- parallel implementers by module, self-verify with test script
4. Review            -- single reviewer runs test script + code review
```

## Step 0: Read the Task

```bash
# Get task details from the project board
gh project item-list 2 --owner ksizzle88 --format json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    content = item.get('content', {})
    if str(content.get('number', '')) == '$ARGUMENTS' or item.get('title', '').startswith('$ARGUMENTS'):
        print(f'Title: {item.get(\"title\")}')
        print(f'Status: {item.get(\"status\")}')
        print(f'Priority: {item.get(\"priority\")}')
        body = content.get('body', '')
        if body: print(f'Body:\n{body}')
        break
"

# Also read the linked issue for full details
gh issue view $ARGUMENTS --repo ksizzle88/claudio --json number,title,body,labels,state
```

```bash
# Update status on the project board (requires project write scope)
# See coordinator.md Task Board section for field/option IDs
# Fallback: comment on the linked issue
gh issue comment $ARGUMENTS --repo ksizzle88/claudio --body "Status: in-progress"
```

Show the user the issue title, description, and priority. If dependencies are not `done`, warn the user and ask whether to proceed.

**Assess scope:**
- If the issue bundles multiple unrelated concerns, recommend breaking it into sub-issues manually and linking them from the parent issue.
- If the spec is already comprehensive (Goal, Current State, Acceptance Criteria, etc.), skip Step 1 and tell the user.

## Step 1: Research Team

Create an agent team of 2-3 researchers, each investigating a different aspect of the task. Split by concern -- e.g., one researcher on existing code patterns, another on dependencies/APIs, another on edge cases.

Dispatch each researcher as `Agent(subagent_type: researcher)` with:
- The issue number: `$ARGUMENTS`
- Their specific research focus area
- Instructions to report findings back (not to update the issue directly -- you will synthesize)

**Stage gate -- review all researcher outputs:**
- Are file paths and code references real?
- Are there contradictions between researchers?
- Are there open questions that block planning?

Synthesize findings into a unified spec and update the issue:

```bash
gh issue edit $ARGUMENTS --body "<synthesized spec with Goal, Current State, Desired End State, Scope, Approach, Key Decisions, Acceptance Criteria, Dependencies & Risks>"
```

Give the user a 3-5 bullet summary of findings and proceed.

## Step 2: Plan + Test Script (Parallel)

Dispatch two agents in parallel:

### Agent A: Planner (`Agent(subagent_type: planner)`)

- The issue number: `$ARGUMENTS`
- Context: the full spec is on the GitHub Issue (researcher stage complete)
- Instructions: Read the issue, deep-dive into the codebase, create a detailed implementation plan
- Save to: `.taskmaster/plans/task-$ARGUMENTS-plan.md`
- Plan must include: Summary, Research Findings, Files to Change, Implementation Steps (with exact file paths, function names, patterns), Testing & Verification, Risks & Mitigations
- Update the issue to reference the plan file

### Agent B: Test Author (`Agent(subagent_type: implementer)`)

- The issue number: `$ARGUMENTS`
- Context: the full spec is on the GitHub Issue
- Instructions: Read the issue spec and acceptance criteria, then create a verification script
- Save to: `.taskmaster/tests/task-$ARGUMENTS-test.sh`
- The script should:
  - Be executable (`#!/usr/bin/env bash`, `set -euo pipefail`)
  - Test each acceptance criterion from the spec
  - Use non-destructive checks (read files, grep for patterns, run linters/type-checks, run existing test suites)
  - Print PASS/FAIL per criterion with clear output
  - Exit 0 if all pass, exit 1 if any fail
  - Work as a repeatable, single-command verification: `bash .taskmaster/tests/task-$ARGUMENTS-test.sh`
- Do NOT implement the feature -- only write the test script that will verify it once implemented

```bash
mkdir -p .taskmaster/plans .taskmaster/tests
```

**Stage gate -- review both outputs:**

For the plan:
- Are implementation steps specific enough to execute without further research?
- Are file paths real? Spot-check a few.
- Steps in dependency order?
- Open questions that block implementation? If so, ask the user.

For the test script:
- Does it cover all acceptance criteria from the spec?
- Is it non-destructive (won't modify the codebase)?
- Can it be run with a single command?

Make the test script executable:

```bash
chmod +x .taskmaster/tests/task-$ARGUMENTS-test.sh
```

Give the user a brief summary (plan approach, number of steps, what the test script covers) and proceed.

## Step 3: Implement (Parallel by Module)

Review the plan and split implementation into independent work streams by module/file-set. Each implementer gets a non-overlapping set of files.

Dispatch 2-4 implementers as `Agent(subagent_type: implementer)` with:
- The issue number: `$ARGUMENTS`
- The plan file: `.taskmaster/plans/task-$ARGUMENTS-plan.md`
- Their specific implementation steps (by number from the plan)
- Their assigned file set (no overlap with other implementers)
- The test script path: `.taskmaster/tests/task-$ARGUMENTS-test.sh`
- Instructions: Execute your assigned steps, then run the test script to self-verify. Report back with changes made and test results.

If the task is small enough that splitting would be artificial (e.g., 1-2 files), use a single implementer instead.

**Stage gate -- review all implementer outputs:**
- Did all assigned steps succeed?
- Did the test script pass for each implementer?
- Any divergences from the plan? Are they reasonable?
- Any conflicts between implementers' changes?

If issues exist, send specific implementers back with details on what to fix. Repeat until clean.

Run the test script one final time to verify end-to-end:

```bash
bash .taskmaster/tests/task-$ARGUMENTS-test.sh
```

Give the user a summary of what was implemented (files changed, key outcomes) and proceed.

## Step 4: Review

```bash
# Update status on the project board (requires project write scope)
# See coordinator.md Task Board section for field/option IDs
# Fallback: comment on the linked issue
gh issue comment $ARGUMENTS --repo ksizzle88/claudio --body "Status: review"
```

Dispatch `Agent(subagent_type: reviewer)` with:
- The issue number: `$ARGUMENTS`
- The plan file: `.taskmaster/plans/task-$ARGUMENTS-plan.md`
- The test script: `.taskmaster/tests/task-$ARGUMENTS-test.sh`
- Summary of what each implementer changed
- Instructions:
  1. Run the test script: `bash .taskmaster/tests/task-$ARGUMENTS-test.sh`
  2. Review changes via `git diff`
  3. Read changed files in full context
  4. Check: correctness, security, edge cases, conventions, completeness
  5. Return a PASS or FAIL verdict with details
  - IMPORTANT: Do NOT run one-off bash commands to test. Use the test script. If the test script is missing a check, add it to the script and re-run.

### If PASS

```bash
# Update status on the project board (requires project write scope)
# See coordinator.md Task Board section for field/option IDs
# Fallback: comment on the linked issue and close it
gh issue comment $ARGUMENTS --repo ksizzle88/claudio --body "Status: done"
gh issue close $ARGUMENTS --repo ksizzle88/claudio
```

Report to the user: what was accomplished, any minor nits the reviewer noted, final status.

### If FAIL

```bash
# Update status on the project board (requires project write scope)
# See coordinator.md Task Board section for field/option IDs
# Fallback: comment on the linked issue
gh issue comment $ARGUMENTS --repo ksizzle88/claudio --body "Status: in-progress"
```

Send the reviewer's issue list back to the relevant implementer(s). Include each issue with severity, file, line, description, and suggested fix.

Repeat Steps 3-4 until the reviewer passes. If the implement-review loop runs more than 3 times, stop and report to the user -- the task may need to be re-planned or broken up.

## Rules

- **Wait at each stage gate.** Review agent output before dispatching the next stage.
- **Show progress.** Brief summary to the user after each stage -- key outcomes, not full dumps.
- **Respect user intervention.** If the user speaks up, pause and follow their direction.
- **Keep status accurate.** `in-progress` at start, `review` for reviewer, `done` on pass, back to `in-progress` on fail.
- **Never write code.** All code goes through implementer agents. All review goes through the reviewer.
- **Never skip the reviewer.** Every implementation must be reviewed.
- **Use the test script.** The test script is the single source of verification. If a check is missing, update the script -- don't run ad-hoc commands.
- **No file conflicts.** When splitting implementation, ensure each implementer has a non-overlapping file set.
