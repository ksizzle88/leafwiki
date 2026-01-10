---
description: Post-mortem review comparing execution against plan with improvement patches
argument-hint: [path-to-plan]
---

# Review Execution

Perform a comprehensive post-mortem analysis comparing what was actually implemented against the original plan.

## Purpose

**This is a retrospective analysis tool.** After completing an implementation, use this command to:

- Compare actual changes (git diff) against the planned approach
- Document divergences and their justifications
- Identify bugs, errors, or anti-patterns introduced during implementation
- Review non-technical planning documents for accuracy
- Generate patch files with suggested improvements to planning/execution assets

## Important: Path Conventions

This command operates across two scopes:

**Project Level** (active project being worked on):
- Output: `{PROJECT_ROOT}/.agents/reviews/[feature-name]-review.md`
- Project CLAUDE.md: `{PROJECT_ROOT}/.claude/CLAUDE.md`
- Project commands: `{PROJECT_ROOT}/.claude/commands/`

**Top Level** (shared across all projects):
- Top-level CLAUDE.md: `/workspace/.claude/CLAUDE.md`
- Shared commands: `/workspace/.claude/commands/`

**CRITICAL**: All paths in patches MUST be absolute paths from `/workspace/`. This ensures patches can be applied unambiguously regardless of current working directory.

## Inputs

### Required

**Plan File**: `$ARGUMENTS`
The implementation plan that guided execution. Read this first to understand intended approach.

### Gathered Automatically

**Project Root**: Determine the active project root (where the plan file lives or where implementation occurred).

**Git Diff**: Run `git diff HEAD~N` or `git diff <base-commit>` to see all changes made during implementation.

**Conversation Context**: Review the current conversation to understand decisions made during implementation.

**Related Documents**: Scan for related files in BOTH project and top-level locations:
- `{PROJECT_ROOT}/.agents/execution-reports/` - Previous execution reports
- `{PROJECT_ROOT}/.agents/plans/` - Related plans
- `{PROJECT_ROOT}/.claude/CLAUDE.md` - Project-specific conventions
- `{PROJECT_ROOT}/.claude/commands/` - Project-specific commands
- `/workspace/.claude/CLAUDE.md` - Top-level conventions
- `/workspace/.claude/commands/` - Shared commands

## Analysis Workflow

### Phase 1: Gather Evidence

**1.1 Read the Plan**
- Extract all planned tasks, patterns, and validation steps
- Note acceptance criteria and completion checklist
- Identify key architectural decisions

**1.2 Analyze Git Changes**
```bash
# Get the commit range for this implementation
git log --oneline -20

# Full diff of changes
git diff <base-commit>..HEAD --stat
git diff <base-commit>..HEAD
```

**1.3 Review Conversation**
- Identify decision points during implementation
- Note any clarifications or pivots
- Document challenges encountered

### Phase 2: Compare Plan vs Reality

**2.1 Task-by-Task Analysis**

For each task in the plan:

| Task | Planned | Actual | Status |
|------|---------|--------|--------|
| Task description | What plan specified | What was implemented | Match/Diverged/Skipped |

**2.2 Divergence Classification**

For each divergence, classify:

**Justified Divergences** (Good):
- Plan assumption was incorrect
- Better pattern discovered in codebase
- Security or performance improvement
- External constraint discovered

**Problematic Divergences** (Concerning):
- Deviated without clear reason
- Ignored documented patterns
- Introduced technical debt
- Skipped validation steps

### Phase 3: Code Quality Review

**3.1 Bug/Error Detection**

Search for common issues in the diff:
- Type mismatches or missing type hints
- Unhandled error cases
- Resource leaks (unclosed connections, files)
- Race conditions or async issues
- Security vulnerabilities (injection, XSS, etc.)
- Missing null/undefined checks
- Incorrect API contracts

**3.2 Pattern Violations**

Compare against CLAUDE.md and codebase conventions:
- Naming convention violations
- Import organization issues
- Error handling inconsistencies
- Logging pattern deviations
- Test coverage gaps

**3.3 Document Findings with Code Examples**

For each bug or error found:

```markdown
### Bug: [Title]

**Location**: `path/to/file.py:line`

**Issue**: [Description of the problem]

**Code**:
```python
# Problematic code
def bad_example():
    ...
```

**Fix**:
```python
# Corrected code
def good_example():
    ...
```

**Why This Matters**: [Impact if not fixed]
```

### Phase 4: Non-Technical Document Review

Review planning and process documents for accuracy:

**4.1 Plan Accuracy**
- Were file paths correct?
- Were pattern references accurate?
- Were validation commands executable?
- Were dependencies correctly identified?

**4.2 CLAUDE.md Accuracy**
- Are documented patterns still current?
- Are there new patterns that should be added?
- Are there deprecated patterns to remove?

**4.3 Command Accuracy**
- Did command instructions work as written?
- Are there missing steps?
- Are there unclear instructions?

### Phase 5: Generate Improvement Patches

For each document that needs updates, generate a unified diff patch.

**CRITICAL: Use Absolute Paths**

All patch paths MUST be absolute from `/workspace/`. This distinguishes between:
- Project-level files: `/workspace/workspace/project-name/.claude/...`
- Top-level files: `/workspace/.claude/...`

**Patch Format**:
```diff
--- a/workspace/.claude/CLAUDE.md
+++ b/workspace/.claude/CLAUDE.md
@@ -100,6 +100,12 @@ ## Patterns

+### New Pattern: [Name]
+
+Discovered during [feature] implementation:
+
+[Pattern description with code example]
+
```

**Project-level patch example**:
```diff
--- a/workspace/workspace/trainer2/.claude/CLAUDE.md
+++ b/workspace/workspace/trainer2/.claude/CLAUDE.md
@@ -50,3 +50,8 @@ ## Docker Guidelines

+### Container Health Checks
+
+Always verify container health before running tests...
+
```

Generate patches for (using full absolute paths):

**Top-Level (shared across projects)**:
- `/workspace/.claude/CLAUDE.md` - Shared patterns, anti-patterns, conventions
- `/workspace/.claude/commands/core_piv_loop/plan-feature.md` - Planning improvements
- `/workspace/.claude/commands/core_piv_loop/execute.md` - Execution improvements
- `/workspace/.claude/commands/validation/*.md` - Validation improvements

**Project-Level (specific to active project)**:
- `{PROJECT_ROOT}/.claude/CLAUDE.md` - Project-specific patterns
- `{PROJECT_ROOT}/.claude/commands/*.md` - Project-specific commands

## Output Format

**Save to**: `{PROJECT_ROOT}/.agents/reviews/[feature-name]-review.md`

The review MUST be saved in the active project's `.agents/reviews/` directory, NOT the top-level `.agents/`. Create the directory if it doesn't exist.

Example: If working on `/workspace/workspace/trainer2/`, save to:
`/workspace/workspace/trainer2/.agents/reviews/feature-name-review.md`

### Report Structure

```markdown
# Execution Review: [Feature Name]

## Meta Information

- **Project Root**: [absolute path to project, e.g., /workspace/workspace/trainer2]
- **Plan**: [absolute path to plan file]
- **Review Date**: [YYYY-MM-DD]
- **Commits Analyzed**: [commit range or list]
- **Files Changed**: +X -Y across N files

---

## Executive Summary

**Overall Alignment**: X/10

[2-3 sentence summary of how well execution matched plan]

**Key Findings**:
- [Top 3-5 findings]

---

## Plan vs Reality Comparison

### Tasks Completed as Planned
- [List of tasks that matched plan exactly]

### Divergences

#### Divergence 1: [Title]

| Aspect | Details |
|--------|---------|
| **Planned** | [What plan specified] |
| **Actual** | [What was implemented] |
| **Reason** | [Why divergence occurred] |
| **Classification** | Justified / Problematic |
| **Impact** | [Effect on feature/codebase] |

[Continue for each divergence...]

### Skipped Items
- [Items from plan not implemented, with reasons]

---

## Bugs & Errors Found

### Bug 1: [Title]

**Severity**: Critical / High / Medium / Low
**Location**: `path/to/file:line`

**Issue**:
[Description]

**Problematic Code**:
```language
[code snippet]
```

**Suggested Fix**:
```language
[corrected code]
```

**Impact**: [What could go wrong if not fixed]

[Continue for each bug...]

---

## Pattern Compliance

### Followed Patterns
- [Patterns from CLAUDE.md that were correctly applied]

### Violated Patterns
- [Patterns that were not followed, with locations]

### New Patterns Discovered
- [Patterns that emerged during implementation worth documenting]

---

## Document Accuracy Review

### Plan Document Issues

| Issue | Location | Correction Needed |
|-------|----------|-------------------|
| [issue] | [section] | [what to fix] |

### CLAUDE.md Issues

| Issue | Section | Correction Needed |
|-------|---------|-------------------|
| [issue] | [section] | [what to fix] |

### Command Issues

| Command | Issue | Correction Needed |
|---------|-------|-------------------|
| [command] | [issue] | [what to fix] |

---

## Improvement Patches

**IMPORTANT**: All patches use absolute paths from /workspace/

### Patch 1: Update top-level CLAUDE.md

**Target**: `/workspace/.claude/CLAUDE.md`
**Purpose**: [Why this change is needed]

```diff
--- a/workspace/.claude/CLAUDE.md
+++ b/workspace/.claude/CLAUDE.md
@@ -line,count +line,count @@ Section
 existing line
+new line
-removed line
```

### Patch 2: Update project CLAUDE.md

**Target**: `/workspace/workspace/[project]/.claude/CLAUDE.md`
**Purpose**: [Why this change is needed]

```diff
--- a/workspace/workspace/[project]/.claude/CLAUDE.md
+++ b/workspace/workspace/[project]/.claude/CLAUDE.md
@@ -line,count +line,count @@ Section
 existing line
+new line
```

### Patch 3: Update plan-feature.md

**Target**: `/workspace/.claude/commands/core_piv_loop/plan-feature.md`
**Purpose**: [Why this change is needed]

```diff
--- a/workspace/.claude/commands/core_piv_loop/plan-feature.md
+++ b/workspace/.claude/commands/core_piv_loop/plan-feature.md
[unified diff content]
```

[Continue for each patch...]

---

## Recommendations

### Immediate Actions
- [ ] [Action items to address bugs/issues found]

### Process Improvements
- [ ] [Changes to planning/execution process]

### Documentation Updates
- [ ] [Specific docs to update]

---

## Lessons Learned

### What Worked Well
- [Specific successful aspects]

### What to Improve
- [Specific areas for improvement]

### For Next Implementation
- [Concrete recommendations]
```

## Important Guidelines

### Be Specific
- Include file paths and line numbers
- Show actual code, not just descriptions
- Reference specific plan sections

### Focus on Actionable Items
- Every finding should have a suggested fix
- Patches should be applicable with `git apply`
- Recommendations should be concrete

### Maintain Objectivity
- Document both successes and failures
- Classify divergences fairly
- Consider context for decisions made

### Prioritize by Impact
- Critical bugs first
- High-impact pattern violations second
- Documentation improvements third

## Validation

After generating the review:

1. Verify all file paths in patches exist and are absolute paths from `/workspace/`
2. Test that patches apply cleanly:
   ```bash
   # Extract patches and test (from /workspace/)
   cd /workspace
   git apply --check {PROJECT_ROOT}/.agents/reviews/[name]-review.md
   ```
3. Confirm bug locations reference real files with correct line numbers
4. Ensure recommendations are actionable
5. Verify the review was saved to the PROJECT's `.agents/reviews/`, not top-level
