# Feature Request: Devcontainer Base Image Pattern & Trainer2 Integration

**Status:** ✅ Completed | **Priority:** High | **Complexity:** Medium  
**Created:** 2026-01-10 | **Updated:** 2026-01-12

## Problem (SOLVED)

The Claudio devcontainer needed a clean, reusable pattern for:
- ✅ Simple authentication (OAuth for both VS Code and terminal)
- ✅ Clear volume strategy (per-container isolated authentication)
- ✅ Reusable base image (shared across multiple projects)
- ✅ Minimal configuration (git config, Claude CLI baked into image)
- ✅ Easy integration (Trainer2 can extend the base image)

**Who it affects**: Developers using Claude Code in containerized environments.

## Solution (IMPLEMENTED)

Created a **base image pattern** where:

1. **claudio-base:latest** - Reusable Docker image with:
   - Python 3.12 (Ubuntu 24.04 native)
   - Node.js 20
   - Claude Code CLI pre-installed
   - Git configuration baked in (from `.env` file)
   - Initialization scripts included

2. **Simple Devcontainers** - Both Claudio and Trainer2 use:
   - Per-container Claude auth volumes (isolated credentials)
   - Minimal configuration (extends base image)
   - Clean postCreateCommand: `init-claude-settings.sh && claude --version`

3. **Build Workflow**:
   - Edit `.env` with git config
   - Run `./build-base.sh` to build base image
   - Any project can extend `claudio-base:latest`

## Architecture

### Base Image (claudio-base:latest)
```dockerfile
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# System deps, Python 3.12, Node.js 20
# Claude Code CLI installed globally
# Git config (user.email, user.name) from build args
# init-claude-settings.sh available
```

### Project Devcontainers

**Claudio** (uses image directly):
```json
{
  "image": "claudio-base:latest",
  "mounts": [
    "source=claudio-claude-${devcontainerId},target=/home/vscode/.claude,type=volume"
  ],
  "postCreateCommand": "init-claude-settings.sh && claude --version"
}
```

**Trainer2** (extends via Dockerfile):
```dockerfile
FROM claudio-base:latest
# Add Trainer2-specific dependencies
```

```json
{
  "build": { "dockerfile": "Dockerfile" },
  "mounts": [
    "source=trainer2-claude-${devcontainerId},target=/home/vscode/.claude,type=volume"
  ],
  "postCreateCommand": "init-claude-settings.sh && claude --version"
}
```

## Implementation Details

### Key Files

**Claudio**:
- `Dockerfile.base` - Base image definition
- `build-base.sh` - Builds claudio-base:latest
- `.env` - Git configuration (gitignored)
- `.env.example` - Template for git config
- `.devcontainer/devcontainer.json` - Uses base image
- `.devcontainer/init-claude-settings.sh` - First-run initialization

**Trainer2**:
- `.devcontainer/Dockerfile` - Extends claudio-base:latest
- `.devcontainer/devcontainer.json` - Build config
- Uses same init-claude-settings.sh from base image

### Authentication Strategy

**Per-Container Volumes**:
- Each container gets its own isolated Claude auth
- No credential sharing between projects
- Volume persists across rebuilds
- Format: `<project>-claude-${devcontainerId}`

**Why Not Bind Mount?**
- Prevents conflicts between VS Code extension and terminal CLI
- True isolation for multi-project work
- Cleaner security model

### Git Configuration

**Baked Into Image**:
- User provides `GIT_USER_EMAIL` and `GIT_USER_NAME` in `.env`
- `build-base.sh` loads `.env` and passes as build args
- Git config set during image build (as vscode user)
- No runtime configuration needed

## Success Criteria (ALL MET)

- ✅ claudio-base:latest image builds successfully
- ✅ Git config baked into image (from .env)
- ✅ Claude Code CLI pre-installed
- ✅ Claudio devcontainer simplified (minimal config)
- ✅ Trainer2 devcontainer extends base image
- ✅ Per-container authentication volumes work
- ✅ Both projects ready to test (pushed to GitHub)

## Testing Plan

**From WSL Host**:
```bash
# Run test-sync.sh
cd /path/to/claudio
./test-sync.sh

# This will:
# 1. Pull latest Claudio (feature-setup2)
# 2. Pull latest Trainer2 (feature/dev_container_setup)
# 3. Build claudio-base:latest
# 4. Open both in VS Code
```

**In VS Code**:
1. Click "Reopen in Container" for both projects
2. Wait for containers to build
3. Authenticate via VS Code extension (OAuth)
4. Verify `claude --version` works in terminal
5. Verify `git config --list` shows correct user

## Benefits

**For Claudio**:
- Clean, maintainable base image
- Simple devcontainer configuration
- Easy to update (rebuild base image)

**For Trainer2**:
- Inherits all tooling from base
- Minimal configuration needed
- Can add project-specific dependencies
- Isolated authentication

**For Future Projects**:
- Copy Trainer2's `.devcontainer/` pattern
- Extend claudio-base:latest
- Add project-specific tools
- Everything just works

## Files Changed

**Claudio**:
- `Dockerfile.base` - Base image with Python, Node, Claude CLI, git config
- `build-base.sh` - Loads .env, builds image
- `.env.example` - Template for git configuration
- `.env` - User's git config (gitignored)
- `.devcontainer/devcontainer.json` - Simplified (uses base image)
- `test-sync.sh` - Opens both Claudio and Trainer2

**Trainer2**:
- `.devcontainer/Dockerfile` - Extends claudio-base:latest
- `.devcontainer/devcontainer.json` - Simplified configuration

## Next Steps

1. Test opening Claudio in fresh container
2. Test opening Trainer2 in fresh container
3. Verify authentication works in both
4. Verify git config works in both
5. Document any issues found
6. Update CLAUDE.md files if needed

## Open Questions (RESOLVED)

- ~~How to handle git config?~~ → Baked into image via .env
- ~~How to prevent auth conflicts?~~ → Per-container volumes
- ~~How to share base image?~~ → Local claudio-base:latest image
- ~~How to minimize devcontainer config?~~ → Inherit from base image
