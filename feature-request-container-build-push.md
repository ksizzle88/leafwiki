# Feature Request: Automated Container Build & Push on Git Push

**Status:** Draft | **Priority:** High | **Complexity:** Moderate (3-5 days)
**Created:** 2026-01-13 | **Updated:** 2026-01-13

## Problem

Developers working in the Claudio devcontainer currently have no automated way to build and publish container images when they push code changes. This creates several pain points:

- **Manual overhead**: Developers must remember to manually build and push images separately
- **Inconsistency**: Image tags may not match code versions, causing deployment confusion
- **Error-prone**: Manual steps lead to mistakes (wrong tags, forgotten pushes, incomplete builds)
- **Slow iteration**: Extra manual steps slow down the development workflow
- **No standardization**: Different developers may use different tagging strategies

The team needs an automated, consistent, and fast way to build and publish container images as part of their normal git workflow.

## Solution

Implement a **git pre-push hook system** that automatically builds and pushes Docker images to a container registry whenever developers push code. The solution will integrate seamlessly with the existing Claudio devcontainer environment.

The system will detect when a `git push` occurs, build the container image using the current Dockerfile with BuildKit optimizations, tag it intelligently based on git metadata (branch name, commit SHA, semantic version tags), and push it to GitHub Container Registry (GHCR). All of this happens transparently before the code push completes.

**Key Capabilities:**
- ✅ **Automatic triggering**: Builds run on `git push` via pre-push hook
- ✅ **Smart tagging**: Multiple tags (latest, branch name, commit SHA, semantic version)
- ✅ **Fast builds**: Uses BuildKit cache mounts and layer caching
- ✅ **Secure credentials**: Registry authentication via environment variables
- ✅ **Clear feedback**: Progress indicators and error messages during build/push
- ✅ **Configurable**: Enable/disable per project via environment variables

## Scope

**In Scope (MVP):**
- ✅ Git pre-push hook that triggers on `git push`
- ✅ Automated Docker build using existing Dockerfile
- ✅ BuildKit-optimized builds with cache mounts
- ✅ Multi-tag strategy (latest, branch, SHA, semver)
- ✅ Push to GitHub Container Registry (GHCR)
- ✅ Environment-based configuration (.env file)
- ✅ Secure credential handling (GitHub token)
- ✅ Build success/failure reporting
- ✅ Skip hook option (env var or git push flag)
- ✅ Basic documentation (setup, config, troubleshooting)

**Out of Scope (Future Enhancements):**
- ❌ Multi-registry support (Docker Hub, ECR, etc.)
- ❌ Image vulnerability scanning
- ❌ Image signing/verification
- ❌ Slack/Discord notifications
- ❌ Build metrics/analytics
- ❌ Rollback on failed deployments
- ❌ GitHub Actions integration (this is for local dev)
- ❌ Multi-architecture builds (arm64 + amd64)

## Requirements

**Functional:**
- ✅ **Hook Installation**: Script to install git pre-push hook in `.git/hooks/`
- ✅ **Build Detection**: Detect if Dockerfile has changed since last build
- ✅ **Tag Generation**:
  - `latest` for main/master branch
  - `{branch-name}` for feature branches
  - `{commit-sha}` for all commits (first 7 chars)
  - `v{semver}` when pushing git tags (e.g., v1.2.3)
- ✅ **Registry Auth**: Login to GHCR using GitHub Personal Access Token
- ✅ **Build Execution**: Run `docker build` with BuildKit enabled
- ✅ **Push Execution**: Push all tags to registry
- ✅ **Error Handling**:
  - Abort git push if build fails
  - Clear error messages for auth failures
  - Retry logic for transient network errors
- ✅ **Skip Mechanism**: Allow developers to bypass hook when needed
  - Environment variable: `SKIP_IMAGE_BUILD=true`
  - Git flag: `git push --no-verify`

**Non-Functional:**
- ⚡ **Performance**:
  - Builds should use all available BuildKit optimizations
  - Leverage Docker layer caching to avoid rebuilding unchanged layers
  - Target: <2 minutes for incremental builds, <5 minutes for full rebuilds
- 🔒 **Security**:
  - GitHub token stored in `.env` file (gitignored)
  - No credentials in git history or logs
  - Token requires only `write:packages` scope
- 🔧 **Integration**:
  - Must work within existing Claudio devcontainer
  - Compatible with existing git workflow
  - No changes to docker-compose.yml or Dockerfile required
  - Hook script stored in `.devcontainer/hooks/` (version controlled)

## Success Criteria

- ✅ Developer pushes code → image automatically builds and pushes without manual intervention
- ✅ Build failures prevent git push from completing (protecting broken images)
- ✅ Images tagged correctly and visible in GHCR (ghcr.io/owner/claudio)
- ✅ Incremental builds complete in <2 minutes (with warm cache)
- ✅ Documentation allows new developer to set up in <5 minutes
- ✅ Zero credential leaks or security warnings

## Technical Notes

**Affected Components:**
- `.devcontainer/hooks/pre-push` - New git hook script (bash)
- `.devcontainer/install-hooks.sh` - Hook installation script
- `.env.example` - Template with required variables
- `.dockerignore` - Already exists, may need updates
- `README.md` - Updated with build/push documentation

**Dependencies:**
- Docker (already present in devcontainer)
- BuildKit (enable via `DOCKER_BUILDKIT=1`)
- Git (already present)
- GitHub Personal Access Token with `write:packages` scope
- Network access to ghcr.io

**Technology Stack:**
- Bash scripts for git hooks
- Docker CLI with BuildKit
- GitHub Container Registry (GHCR)
- Environment variables for configuration

**Configuration (.env):**
```bash
# Container Registry Configuration
REGISTRY_ENABLED=true
REGISTRY_URL=ghcr.io
REGISTRY_USERNAME=your-github-username
REGISTRY_TOKEN=ghp_your_personal_access_token
REGISTRY_IMAGE_NAME=claudio  # or your-org/claudio
```

**Tagging Strategy:**
```
ghcr.io/username/claudio:latest          (main branch only)
ghcr.io/username/claudio:main            (main branch)
ghcr.io/username/claudio:feature-xyz     (feature branches)
ghcr.io/username/claudio:abc1234         (commit SHA)
ghcr.io/username/claudio:v1.2.3          (semantic version tags)
```

**Known Challenges:**
- BuildKit cache persistence across container rebuilds (may need volume)
- Large image sizes slowing initial pushes (mitigated by layer caching)
- GHCR rate limits (unlikely for personal use, document limits)
- Hook installation timing (run in postCreateCommand)

## Implementation Plan

**Phase 1: Core Build Hook (Days 1-2)**
- Create pre-push hook bash script
- Implement Docker build with BuildKit
- Add basic tag generation (branch + SHA)
- Test build success/failure flows

**Phase 2: Registry Integration (Days 3-4)**
- Add GHCR authentication
- Implement multi-tag push
- Add semver tag detection
- Environment variable configuration
- Error handling and retry logic

**Phase 3: Polish & Documentation (Day 5)**
- Hook installation script
- Update .env.example
- Write documentation (setup, usage, troubleshooting)
- Test clean install process
- Add skip mechanisms

## Open Questions

- [ ] Should the hook build the devcontainer image itself, or a production image?
  - **Recommendation**: Build production image from separate Dockerfile.prod (future enhancement)
  - **MVP**: Build the devcontainer Dockerfile for now
- [ ] What if the push is to a remote that isn't GitHub?
  - **Recommendation**: Hook checks git remote, only runs if GitHub detected
- [ ] Should we support Docker Hub as alternative to GHCR?
  - **Recommendation**: GHCR for MVP, multi-registry in Phase 2
- [ ] How to handle multi-container projects (docker-compose with multiple images)?
  - **Recommendation**: Out of scope for MVP, document limitation

## Example Usage

**Initial Setup (one-time):**
```bash
# 1. Configure environment
cp .env.example .env
# Edit .env with your GitHub credentials

# 2. Install hooks (automatic via postCreateCommand)
.devcontainer/install-hooks.sh
```

**Normal Workflow:**
```bash
# Developer makes changes
git add .
git commit -m "feat: add new feature"

# Push triggers automatic build & push
git push origin feature-branch
# Output:
# [Pre-push] Building Docker image...
# [Pre-push] Tagging: ghcr.io/user/claudio:feature-branch, :abc1234
# [Pre-push] Pushing to GHCR...
# [Pre-push] ✅ Image pushed successfully
# Enumerating objects...
```

**Skip build when needed:**
```bash
# Option 1: Use --no-verify
git push --no-verify origin main

# Option 2: Set env var
SKIP_IMAGE_BUILD=true git push origin main
```

## Next Steps

1. **Review & approve** this feature request
2. **Create GitHub PAT** with `write:packages` scope
3. **Implement Phase 1** (core build hook)
4. **Test in development** branch
5. **Iterate and refine** based on feedback
6. **Document and roll out** to team

---

**Notes:**
- This integrates seamlessly with existing Claudio architecture
- Follows Docker and devcontainer best practices already established
- Minimal changes to existing configuration
- Can be disabled per-project if not needed
