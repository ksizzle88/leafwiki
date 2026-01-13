---
description: Create or update a feature request through interactive interview
argument-hint: [feature-request-file]
---

# Feature Request: Interactive Feature Specification

## Objective

Gather feature requirements through structured interview, then create or update a feature request document.

## Output File

Write to: `$ARGUMENTS` (default: `feature-request.md`)

## Process

### 1. Check Mode

- If `$ARGUMENTS` is existing file → UPDATE mode (read file, interview for changes)
- Otherwise → CREATE mode (full interview)

### 2. Conduct Interview

**For CREATE - Ask in rounds:**

**Round 1: Basics**
- What feature are you building? (New functionality / Backend enhancement / Developer tool / Integration)
- What problem does it solve? (UX improvement / New capability / Performance / Fix pain point)

**Round 2: Scope**
- Who will use it? (End users / Team / Developers / Admins)
- How complex? (Simple 1-2 days / Moderate 3-5 days / Complex 1-2 weeks / Major multi-week)

**Round 3: Requirements**
- What's essential for MVP? [multiSelect] (Core functionality / UI polish / Error handling / Documentation)
- Any constraints? [multiSelect] (Existing system integration / Performance / Security / None)

**Round 4: Context**
- Open-ended: "Provide any additional context, examples, or specific requirements"

**For UPDATE - Ask:**
- What to update? [multiSelect] (Scope / Technical approach / Priority / Add details)
- What changes? (Expand scope / Reduce scope / Refine / Clarify)
- Then gather specific updates conversationally

### 3. Generate Document

Use this structure:

```markdown
# Feature Request: [Name]

**Status:** Draft | **Priority:** Medium | **Complexity:** [from interview]
**Created:** [date] | **Updated:** [date]

## Problem
[What problem and for whom]

## Solution
[What will be built - 2-3 paragraphs]

**Key Capabilities:**
- ✅ [Feature 1]
- ✅ [Feature 2]
- ✅ [Feature 3]

## Scope

**In Scope (MVP):**
- ✅ [Item 1]
- ✅ [Item 2]

**Out of Scope:**
- ❌ [Future item 1]
- ❌ [Future item 2]

## Requirements

**Functional:**
- ✅ [Requirement 1]
- ✅ [Requirement 2]

**Non-Functional:**
- ⚡ Performance: [needs]
- 🔒 Security: [needs]

## Success Criteria
- ✅ [Measurable criteria 1]
- ✅ [Measurable criteria 2]

## Technical Notes
**Affected:** [components]
**Dependencies:** [dependencies]
**Challenges:** [known challenges]

## Timeline
- Phase 1: [deliverables]
- Phase 2: [deliverables]

## Open Questions
- [ ] [Question 1]
- [ ] [Question 2]
```

### 4. Quality Checks

- ✅ Clear problem and solution
- ✅ Specific, actionable requirements
- ✅ Realistic MVP scope
- ✅ Measurable success criteria
- ✅ Concrete examples where helpful

## Output

Provide:
1. File path confirmation
2. Brief summary of feature
3. Key requirements and scope
4. Next steps suggestion

**Style:** Clear, specific, action-oriented. Use examples. Keep scannable.
