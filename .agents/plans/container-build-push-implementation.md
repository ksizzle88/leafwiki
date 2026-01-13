# Implementation Plan: Automated Container Build & Push

**Feature Request:** [feature-request-container-build-push.md](../../feature-request-container-build-push.md)
**Created:** 2026-01-13
**Status:** Ready for Implementation

---

## Overview

Implement a git pre-push hook that automatically builds and pushes Docker images to GitHub Container Registry (GHCR) when developers push code.

## Prerequisites

- [x] GitHub PAT with `write:packages` scope → `GITHUB_PAT` in `.env`
- [x] Registry configuration in `.env` (REGISTRY_URL, REGISTRY_USERNAME, REGISTRY_IMAGE_NAME)
- [ ] Docker with BuildKit available in devcontainer (verify)

---

## Phase 1: Core Hook Script

**Goal:** Create the pre-push hook that builds Docker images

### Task 1.1: Create hooks directory structure
```
.devcontainer/
└── hooks/
    └── pre-push          # Main hook script (bash)
```

**Actions:**
- [ ] Create `.devcontainer/hooks/` directory
- [ ] Create `pre-push` script with executable permissions

### Task 1.2: Implement pre-push hook script

**File:** `.devcontainer/hooks/pre-push`

**Logic Flow:**
```
1. Check if REGISTRY_ENABLED=true (exit 0 if disabled)
2. Check for SKIP_IMAGE_BUILD=true (exit 0 if set)
3. Load environment variables from .env
4. Determine current git context:
   - Branch name (sanitized for Docker tags)
   - Commit SHA (short, 7 chars)
   - Git tags (if pushing a tag)
5. Login to GHCR using GITHUB_PAT
6. Build image with BuildKit:
   - DOCKER_BUILDKIT=1
   - Cache from previous builds
   - Multiple tags
7. Push all tags to registry
8. Report success/failure
9. Exit 0 (success) or 1 (failure, aborts push)
```

**Tags to generate:**
- `${REGISTRY_URL}/${REGISTRY_USERNAME}/${REGISTRY_IMAGE_NAME}:${branch}`
- `${REGISTRY_URL}/${REGISTRY_USERNAME}/${REGISTRY_IMAGE_NAME}:${sha}`
- `${REGISTRY_URL}/${REGISTRY_USERNAME}/${REGISTRY_IMAGE_NAME}:latest` (only for main/master)
- `${REGISTRY_URL}/${REGISTRY_USERNAME}/${REGISTRY_IMAGE_NAME}:${version}` (if git tag matches v*)

**Environment Variables Used:**
| Variable | Source | Purpose |
|----------|--------|---------|
| REGISTRY_ENABLED | .env | Toggle feature on/off |
| REGISTRY_URL | .env | Registry hostname (ghcr.io) |
| REGISTRY_USERNAME | .env | GitHub username |
| REGISTRY_IMAGE_NAME | .env | Image name |
| GITHUB_PAT | .env | Authentication token |
| SKIP_IMAGE_BUILD | runtime | Skip this build |

**Error Handling:**
- Auth failure → clear message, abort push
- Build failure → show error output, abort push
- Push failure → retry once, then abort
- Network timeout → suggest checking connectivity

---

## Phase 2: Hook Installation

**Goal:** Automatically install hooks when container starts

### Task 2.1: Create installation script

**File:** `.devcontainer/install-hooks.sh`

**Logic:**
```bash
#!/bin/bash
# Install git hooks for container build/push

HOOKS_SOURCE=".devcontainer/hooks"
HOOKS_TARGET=".git/hooks"

# Copy pre-push hook
if [ -f "$HOOKS_SOURCE/pre-push" ]; then
    cp "$HOOKS_SOURCE/pre-push" "$HOOKS_TARGET/pre-push"
    chmod +x "$HOOKS_TARGET/pre-push"
    echo "[Hooks] Installed pre-push hook"
fi
```

### Task 2.2: Update devcontainer.json

**File:** `.devcontainer/devcontainer.json`

**Change:** Add hook installation to `postCreateCommand` or `postStartCommand`

```json
{
  "postStartCommand": ".devcontainer/install-hooks.sh"
}
```

**Decision Point:**
- `postCreateCommand` - runs once when container created
- `postStartCommand` - runs every time container starts

**Recommendation:** Use `postStartCommand` to ensure hooks are always present, even if `.git/hooks` was modified.

---

## Phase 3: Build Optimization

**Goal:** Fast builds using BuildKit caching

### Task 3.1: Enable BuildKit

**In pre-push script:**
```bash
export DOCKER_BUILDKIT=1
```

### Task 3.2: Add build caching arguments

**Build command:**
```bash
docker build \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  --cache-from ${FULL_IMAGE_NAME}:${branch} \
  --cache-from ${FULL_IMAGE_NAME}:latest \
  -t ${FULL_IMAGE_NAME}:${branch} \
  -t ${FULL_IMAGE_NAME}:${sha} \
  -f .devcontainer/Dockerfile \
  .
```

### Task 3.3: Consider build context

**Current `.dockerignore` review:**
- [ ] Verify `.dockerignore` excludes unnecessary files
- [ ] Ensure `workspace/` is excluded (user projects)
- [ ] Ensure `.git/` is excluded (large, not needed)
- [ ] Ensure `node_modules/` excluded if present

---

## Phase 4: Documentation & Polish

### Task 4.1: Update .env.example

Add registry configuration template:
```bash
# Container Registry Configuration
REGISTRY_ENABLED=true
REGISTRY_URL=ghcr.io
REGISTRY_USERNAME=your-github-username
REGISTRY_IMAGE_NAME=claudio
# Uses GITHUB_PAT from above for authentication
```

### Task 4.2: Update README.md

Add section covering:
- [ ] How the build/push works
- [ ] Configuration options
- [ ] Skipping builds
- [ ] Troubleshooting common issues

### Task 4.3: Add helpful output messages

**During build:**
```
[Build] Starting container image build...
[Build] Branch: feature/my-feature
[Build] Commit: abc1234
[Build] Tags: ghcr.io/ksizzle888/claudio:feature-my-feature, :abc1234
[Build] Building with BuildKit...
[Build] ✓ Build complete (45s)
[Push] Pushing to ghcr.io...
[Push] ✓ Push complete
```

---

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `.devcontainer/hooks/pre-push` | CREATE | Main hook script |
| `.devcontainer/install-hooks.sh` | CREATE | Hook installation script |
| `.devcontainer/devcontainer.json` | MODIFY | Add postStartCommand |
| `.env.example` | MODIFY | Add registry config template |
| `.dockerignore` | VERIFY | Ensure build context is minimal |
| `README.md` | MODIFY | Add usage documentation |

---

## Testing Plan

### Test 1: Manual hook execution
```bash
# Run hook directly
.devcontainer/hooks/pre-push
```

### Test 2: Build only (no push)
```bash
# Set env to disable push, only build
REGISTRY_PUSH_ENABLED=false .devcontainer/hooks/pre-push
```

### Test 3: Full integration
```bash
# Make a change, commit, push
echo "# test" >> README.md
git add README.md
git commit -m "test: verify build hook"
git push origin feature/test-build-hook
# Verify image appears in GHCR
```

### Test 4: Skip mechanism
```bash
# Test skip via env var
SKIP_IMAGE_BUILD=true git push origin main

# Test skip via git flag
git push --no-verify origin main
```

### Test 5: Error handling
```bash
# Test with invalid token
GITHUB_PAT=invalid .devcontainer/hooks/pre-push
# Should show auth error and abort
```

---

## Rollback Plan

If issues arise:
1. Remove hook: `rm .git/hooks/pre-push`
2. Set `REGISTRY_ENABLED=false` in `.env`
3. Use `git push --no-verify` as escape hatch

---

## Dependencies

| Dependency | Required Version | Status |
|------------|------------------|--------|
| Docker | 20.10+ | ✓ Available |
| BuildKit | Built into Docker | ✓ Available |
| Git | 2.x | ✓ Available |
| Bash | 4.x+ | ✓ Available |
| curl or docker login | - | ✓ Available |

---

## Estimated Effort

| Phase | Tasks | Estimate |
|-------|-------|----------|
| Phase 1 | Core hook script | 20-30 min |
| Phase 2 | Installation | 10 min |
| Phase 3 | Build optimization | 15 min |
| Phase 4 | Documentation | 15 min |
| Testing | All tests | 20 min |
| **Total** | | **~1.5 hours** |

---

## Open Decisions

1. **Which Dockerfile to build?**
   - Option A: `.devcontainer/Dockerfile` (current devcontainer)
   - Option B: `Dockerfile` in project root (if exists)
   - Option C: Configurable via `REGISTRY_DOCKERFILE` env var
   - **Recommendation:** Option A for MVP, Option C for future

2. **Hook timing:**
   - `pre-push` - Build before push (current plan) - push fails if build fails
   - `post-commit` - Build after each commit - more builds, always ready
   - **Recommendation:** `pre-push` is correct choice

3. **Multi-arch builds?**
   - Not for MVP - adds significant complexity
   - Future enhancement with `docker buildx`

---

## Ready to Execute

This plan is ready for implementation. Execute with:
```
/execute .agents/plans/container-build-push-implementation.md
```

Or ask: "Implement the container build/push feature per the plan"
