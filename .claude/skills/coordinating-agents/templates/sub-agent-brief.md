# Sub-Agent Brief Template

Use this template when dispatching work to a sub-agent via the Task tool.

---

## Brief for: [agent-name]

### Context
[What the agent needs to know about the current state. Include:]
- Relevant issue number and description from GitHub Issues
- Key files and their locations
- Any decisions already made
- Output from previous agents (if sequential)

### Scope
[Exactly what the agent should do:]
- Specific files to read/modify
- Boundaries — what NOT to touch
- Expected deliverable format

### Acceptance Criteria
[How we know the agent succeeded:]
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Tests pass (if applicable)

### Constraints
- Time/scope boundaries
- Patterns to follow (reference existing code)
- Security considerations

---

## Example: Researcher Brief

```
Task(researcher): "
Context: Task #12 requires adding rate limiting to the API.
We need to understand the current middleware stack before implementing.

Scope:
- Read src/middleware/ and document all middleware in the chain
- Find how existing auth middleware is registered
- Check if there's an existing rate limiter or throttling code

Acceptance Criteria:
- List of all middleware with file paths and line numbers
- Recommended insertion point for rate limiter
- Any existing rate limiting code found
"
```

## Example: Implementer Brief

```
Task(implementer): "
Context: Task #12 - Add rate limiting. Researcher found:
- Middleware chain in src/middleware/index.ts (lines 15-42)
- Auth middleware at src/middleware/auth.ts
- No existing rate limiter
- Best insertion point: after auth, before route handlers (line 28)

Scope:
- Create src/middleware/rate-limiter.ts
- Register in src/middleware/index.ts at line 28
- Follow the pattern in src/middleware/auth.ts for structure
- Do NOT modify existing middleware

Acceptance Criteria:
- Rate limiter limits to 100 req/min per IP
- Returns 429 with Retry-After header when exceeded
- Tests in src/middleware/__tests__/rate-limiter.test.ts pass
"
```

## Example: Reviewer Brief

```
Task(reviewer): "
Context: Task #12 - Rate limiting implemented by implementer.
Changed files: src/middleware/rate-limiter.ts, src/middleware/index.ts

Scope:
- Review the new rate-limiter.ts for correctness and security
- Verify middleware registration order is correct
- Check edge cases: concurrent requests, header injection, IPv6
- Run tests if available

Acceptance Criteria:
- No security issues found (or documented if found)
- Code follows project conventions
- Test coverage is adequate
"
```
