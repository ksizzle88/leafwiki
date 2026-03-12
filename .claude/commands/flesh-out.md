---
description: Expand a GitHub Issue's brief description into a comprehensive, non-technical specification
argument-hint: <issue-number>
allowed-tools: Bash(gh issue *), Read, Glob, Grep, WebSearch, WebFetch, Bash(jq *), Bash(ls *), Write(.taskmaster/**), Edit(.taskmaster/**)
---

# Flesh Out: Expand Issue into Full Specification

## Objective

Take a brief GitHub Issue (identified by `$ARGUMENTS`) and expand its title and description into a comprehensive, non-technical task specification. The result is saved back to the issue as the updated body.

## Process

### 1. Retrieve the Task

Run the following to get the issue details:

```bash
gh issue view $ARGUMENTS --json number,title,body,labels,state
```

Read the issue's title, body, status labels, dependencies, and any existing subtasks carefully.

### 2. Gather Context from Related Issues

If the issue has dependencies or is depended upon by other issues, retrieve those as well:

```bash
gh issue view <dependency-number>
```

Understanding the surrounding issues helps produce a specification that fits within the broader project plan. Also review any relevant project files (CLAUDE.md, PRD, etc.) if they would help clarify what this task is about.

### 3. Analyze What Exists

Before writing, consider:
- What does the brief title/description actually mean in plain language?
- What business or user value does this task deliver?
- What is the current state of things (what exists today)?
- What will be different when this task is done?
- What are the boundaries -- what is included and what is not?

### 4. Write the Expanded Specification

Produce a specification using the following structure. Write in a non-technical tone -- think product manager explaining to stakeholders, not engineer writing a design doc. Be specific and concrete, not vague or hand-wavy.

```
## Goal
What we're trying to achieve and why (business/user value)

## Current State
What exists today and what's wrong or missing

## Desired End State
What "done" looks like -- concrete, observable outcomes

## Scope
### In Scope
- Bullet list of what's included

### Out of Scope
- What we're explicitly NOT doing (to prevent scope creep)

## Approach (High Level)
Numbered steps of the general approach -- non-technical, like explaining to a PM.
Not implementation details, but the logical sequence of work.

## Key Decisions Needed
Questions or choices that need to be resolved before or during implementation

## Acceptance Criteria
Checklist of verifiable conditions that must be true when the task is done

## Dependencies & Risks
- What this task depends on
- What could go wrong
```

### 5. Save the Expanded Specification

Update the issue on GitHub with the fleshed-out description. Pass the entire expanded specification as the body:

```bash
gh issue edit $ARGUMENTS --body "<the full expanded specification text>"
```

### 6. Confirm the Update

After updating, re-read the issue to verify the update was applied:

```bash
gh issue view $ARGUMENTS
```

## Writing Guidelines

- **Tone**: Non-technical. A product manager or business stakeholder should be able to read and understand every word.
- **Specificity**: Use concrete language. Instead of "improve the system," say "add error messages that tell the user exactly what went wrong and how to fix it."
- **Scope discipline**: The "Out of Scope" section is just as important as "In Scope." Be explicit about what this task does NOT include.
- **Acceptance criteria**: Each criterion should be independently verifiable. Someone should be able to look at the finished work and check each one off with a clear yes or no.
- **Approach**: Describe the logical sequence of work, not the code changes. Think "First we figure out X, then we set up Y, then we connect Z" rather than "Create a new module, add a function, update the config."
- **Dependencies and risks**: Be honest about unknowns. If something could block this work or cause problems, call it out.

## Output

After completing the update, provide:
1. A brief confirmation that the issue was updated
2. The issue number and title for reference
3. A one-sentence summary of the expanded specification
