---
description: Create a detailed technical implementation plan for a GitHub Issue
argument-hint: <issue-number>
allowed-tools: Bash(gh issue *), Read, Glob, Grep, WebSearch, WebFetch, Bash(jq *), Bash(ls *), Bash(docker *), Bash(git log *), Bash(git diff *), Bash(git show *), Write(.taskmaster/**), Edit(.taskmaster/**)
---

# Plan: Technical Implementation Plan for a GitHub Issue

## Objective

Take a GitHub Issue (identified by `$ARGUMENTS`) and produce a thorough, engineer-grade implementation plan. This is NOT a product spec -- it is a real build plan. The output should contain enough detail that a separate implementer agent (or engineer) can execute every step without doing additional research.

The finished plan is saved to `.taskmaster/plans/task-<id>-plan.md` and the issue is updated to reference it.

## Process

### Phase 1: Understand the Task

**1.1 Read the issue itself:**

```bash
gh issue view $ARGUMENTS --json number,title,body,labels,state
```

Capture the issue's title, body, status labels, priority labels, and any cross-references.

**1.2 Read dependent and blocking issues:**

For every issue referenced as a dependency, retrieve it:

```bash
gh issue view <dependency-number>
```

Understand what work comes before and after this task, and what assumptions those tasks make.

**1.3 Read project context:**

- Read the project's `CLAUDE.md` for architecture, conventions, and key decisions.
- Read any PRD, spec, or planning documents referenced by the issue or found in `.taskmaster/`, `docs/`, or the repo root.
- Read relevant configuration files (`devcontainer.json`, `docker-compose.yml`, `Dockerfile.*`, `package.json`, `pyproject.toml`, etc.) to understand the project's tooling and structure.

### Phase 2: Research the Codebase

**2.1 Map the relevant code:**

Use Glob, Grep, and Read systematically:

- Find all files related to the feature area (scripts, configs, source code, tests).
- Read each relevant file. Note exact file paths, key function/class names, line numbers of important logic.
- Identify the patterns the codebase already uses: naming conventions, error handling, logging, file organization, module boundaries.

**2.2 Identify files that will change:**

Based on the task requirements, determine:

- Which existing files need modification (and what specifically changes in each).
- Which new files need to be created (and where they should live, following existing conventions).
- Which files might need deletion or deprecation.

**2.3 Check recent history:**

```bash
git log --oneline -20
```

Look at recent commits for related changes. If specific files are relevant:

```bash
git log --oneline -10 -- path/to/file
git diff HEAD~5 -- path/to/file
```

This reveals in-flight work, recent refactors, and the team's current direction.

**2.4 External research (when needed):**

If the task involves external tools, libraries, APIs, or services, use WebSearch and WebFetch to:

- Check official documentation for current APIs and best practices.
- Find known gotchas, breaking changes, or migration guides.
- Verify version compatibility with the project's existing dependencies.

Document every external reference with a URL and a note on why it matters.

### Phase 3: Analyze & Design

**3.1 Technical constraints:**

- What does the existing architecture require or forbid?
- Are there performance, security, or backward-compatibility constraints?
- What environment assumptions exist (Docker, specific runtimes, volume mounts, etc.)?

**3.2 Approach selection:**

If there are multiple reasonable approaches:

- List each approach with a one-sentence description.
- For each, note: pros, cons, effort estimate, risk level.
- Recommend one and explain why.

If there is only one obvious approach, state it clearly and move on.

**3.3 Edge cases and error handling:**

- What inputs or states could cause failures?
- How should errors be surfaced to the user?
- What happens if a dependency is unavailable, a file is missing, or a config is invalid?

### Phase 4: Write the Implementation Plan

Produce the plan using the following structure. Be specific throughout -- reference exact file paths, line numbers, function names, and existing patterns. Do not write generic placeholders.

```
# Implementation Plan: Task <id> -- <task title>

## Summary
One paragraph: what this plan achieves and the general approach.

## Research Findings
Key things discovered during codebase exploration that inform the plan.
Quote specific file paths, line numbers, existing patterns.
Include links to external documentation consulted, with notes on relevance.

## Files to Change

| File | Action | What Changes |
|------|--------|-------------|
| `path/to/existing.sh` | Modify | Add validation logic for X at line ~45 |
| `path/to/new-file.py` | Create | New service implementing Y, following pattern in `path/to/similar.py` |
| `path/to/deprecated.conf` | Delete | No longer needed after migration to Z |

## Implementation Steps

Ordered by dependency. Each step is atomic -- an implementer can complete it, verify it, and move to the next.

1. **Step title**
   - What to do (specific enough to execute without guessing)
   - Which file(s) to touch
   - Key details: function signatures, config keys, patterns to follow (reference by file:line)
   - Gotchas: anything non-obvious that could cause mistakes
   - Verify: how to confirm this step worked (a command to run, an expected output, a test to pass)

2. **Next step title**
   ...continue for all steps...

## Testing & Verification

How to verify the whole thing works end-to-end after all steps are complete.

- Specific commands to run and their expected outputs
- Manual checks if applicable
- Edge cases to test explicitly
- How to confirm no regressions in existing functionality

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Description of what could go wrong | High/Medium/Low | What to do about it |

## Open Questions
Anything that could not be resolved during planning and needs human input before or during implementation. Each question should explain why it matters and what decision it blocks.
```

### Phase 5: Save the Plan

**5.1 Write the plan file:**

Save the full plan to `.taskmaster/plans/task-$ARGUMENTS-plan.md` using Write. Create the `.taskmaster/plans/` directory if it does not exist.

**5.2 Update the issue on GitHub:**

Add a reference to the plan file as a comment on the issue:

```bash
gh issue comment $ARGUMENTS --body "Implementation plan created. See .taskmaster/plans/task-$ARGUMENTS-plan.md for the full technical plan including research findings, file change list, ordered implementation steps, testing strategy, and risk analysis."
```

**5.3 Confirm and re-read:**

```bash
gh issue view $ARGUMENTS
```

Verify the update was applied.

## Quality Standards

- **Be thorough**: Read real files. Do not guess at file contents, function signatures, or config values.
- **Be specific**: Every file path, line number, function name, and pattern reference should be verifiable by the reader.
- **Be honest about unknowns**: If something requires human input, a design decision, or access you do not have, put it in Open Questions. Do not paper over gaps.
- **Be implementation-ready**: A separate agent should be able to execute the plan step-by-step without doing its own research phase. Each step should include enough context to act on immediately.
- **Be ordered**: Steps must be in dependency order. No step should reference work that has not been completed in a prior step.

## Output

After completing the plan, provide:

1. The issue number and title
2. The path to the saved plan file
3. A brief summary of the approach (2-3 sentences)
4. The number of files to change and implementation steps
5. Any open questions that need human input before implementation can begin
