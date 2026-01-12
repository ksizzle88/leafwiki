# Implementation Plan: Claudio Base Image Pattern & Trainer2 Integration

## Executive Summary

Create a reusable Docker base image (`claudio-base:latest`) that both Claudio and Trainer2 can use/extend. This eliminates duplication, simplifies devcontainer configuration, and provides a clean pattern for future projects.

**Key Innovation**: Git config and Claude CLI baked into the base image, with per-container authentication volumes for isolation.

## Architecture

### Base Image Pattern

```
claudio-base:latest
├── Ubuntu 24.04 (Microsoft devcontainer base)
├── Python 3.12 (native, no PPA needed)
├── Node.js 20 (via NodeSource)
├── Claude Code CLI (pre-installed globally)
├── Git config (from .env build args)
└── init-claude-settings.sh (baked in)

Projects extend or use directly:
├── Claudio: Uses image directly
└── Trainer2: Extends via Dockerfile (adds project-specific deps)
```

### Authentication Strategy

**Per-Container Volumes** (NOT bind mounts):
- Each container gets isolated Claude auth: `<project>-claude-${devcontainerId}`
- Prevents VS Code extension vs terminal CLI conflicts
- Clean separation between projects
- Credentials persist across container rebuilds

**Why not bind mount to host `~/.claude`?**
- Shared credentials cause auth conflicts
- VS Code extension and terminal fight over `.credentials.json`
- No true isolation between projects

## Implementation Steps

### Phase 1: Create Base Image (Claudio repo)

#### File: `Dockerfile.base`

```dockerfile
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Build args for git config
ARG DEBIAN_FRONTEND=noninteractive
ARG PYTHON_VERSION=3.12
ARG NODE_VERSION=20
ARG GIT_USER_EMAIL
ARG GIT_USER_NAME

# Layer 1: System dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates curl git openssh-client jq wget make \
    software-properties-common build-essential libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Layer 2: Python 3.12 (Ubuntu 24.04 native)
RUN apt-get update && apt-get install -y \
    python3.12 python3.12-dev python3.12-venv python3-pip \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 \
    && python -m pip install --upgrade --break-system-packages --ignore-installed pip setuptools wheel

# Layer 3: Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y nodejs

# Layer 4: Environment variables
ENV npm_config_update_notifier=false \
    npm_config_fund=false \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    CLAUDE_CONFIG_DIR=/home/vscode/.claude

# Layer 5: Claude Code CLI
RUN npm -g i @anthropic-ai/claude-code

# Layer 6: Claude initialization script
COPY .devcontainer/init-claude-settings.sh /usr/local/bin/init-claude-settings.sh
RUN chmod +x /usr/local/bin/init-claude-settings.sh

# Layer 7: User permissions
RUN mkdir -p /home/vscode/.claude /home/vscode/.history \
    && chown -R vscode:vscode /home/vscode/.claude /home/vscode/.history

# Switch to vscode user
USER vscode

# Layer 8: Git config (as vscode user)
RUN git config --global init.defaultBranch main \
    && git config --global push.autoSetupRemote true \
    && if [ -n "$GIT_USER_EMAIL" ]; then git config --global user.email "$GIT_USER_EMAIL"; fi \
    && if [ -n "$GIT_USER_NAME" ]; then git config --global user.name "$GIT_USER_NAME"; fi

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node --version && python --version || exit 1
```

#### File: `build-base.sh`

```bash
#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Building claudio-base:latest..."

# Load .env if it exists
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

docker build \
    -f Dockerfile.base \
    -t claudio-base:latest \
    --build-arg PYTHON_VERSION=3.12 \
    --build-arg NODE_VERSION=20 \
    --build-arg GIT_USER_EMAIL="${GIT_USER_EMAIL:-}" \
    --build-arg GIT_USER_NAME="${GIT_USER_NAME:-}" \
    .

echo -e "${GREEN}✓${NC} Base image built successfully!"
echo "Image: claudio-base:latest"
```

#### File: `.env.example`

```bash
# Git Configuration (baked into base image)
GIT_USER_EMAIL=your.email@example.com
GIT_USER_NAME=Your Name
```

#### File: `.env` (gitignored)

User creates this locally with their actual git config.

### Phase 2: Simplify Claudio Devcontainer

#### File: `.devcontainer/devcontainer.json`

```json
{
    "name": "claudio (Claude Code)",
    "image": "claudio-base:latest",
    "workspaceFolder": "/workspace",
    "remoteUser": "vscode",
    "features": {
        "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {}
    },
    "mounts": [
        "source=claudio-claude-${devcontainerId},target=/home/vscode/.claude,type=volume",
        "source=claudio-bashhistory-${devcontainerId},target=/commandhistory,type=volume"
    ],
    "postCreateCommand": "init-claude-settings.sh && claude --version",
    "customizations": {
        "vscode": {
            "extensions": [
                "anthropic.claude-code",
                "ms-azuretools.vscode-docker"
            ]
        }
    }
}
```

**Key changes from before**:
- ❌ Removed: Complex bind mount to `~/.claude` on host
- ❌ Removed: Environment variables for git config
- ❌ Removed: Long postCreateCommand with git config setup
- ✅ Added: Per-container volume for Claude auth
- ✅ Added: Simple postCreateCommand (just init and verify)

### Phase 3: Create Trainer2 Devcontainer

#### File: `workspace/trainer2/.devcontainer/Dockerfile`

```dockerfile
# Trainer2 Devcontainer - Extends claudio-base with project-specific dependencies
FROM claudio-base:latest

# Switch to root for installations
USER root

# Trainer2-specific dependencies can be added here
# Example: Install project Python packages globally (optional)
# COPY requirements.txt /tmp/
# RUN python -m pip install --break-system-packages -r /tmp/requirements.txt

# Or install additional system packages
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     your-package-here \
#     && rm -rf /var/lib/apt/lists/*

# Switch back to vscode user
USER vscode

# Project-specific environment variables (if needed)
# ENV TRAINER2_ENV=development
```

#### File: `workspace/trainer2/.devcontainer/devcontainer.json`

```json
{
    "name": "Trainer2 (Claude Code)",
    "build": {
        "dockerfile": "Dockerfile",
        "context": "."
    },
    "remoteUser": "vscode",
    "features": {
        "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {}
    },
    "mounts": [
        "source=trainer2-claude-${devcontainerId},target=/home/vscode/.claude,type=volume",
        "source=trainer2-bashhistory-${devcontainerId},target=/commandhistory,type=volume"
    ],
    "postCreateCommand": "init-claude-settings.sh && claude --version",
    "customizations": {
        "vscode": {
            "extensions": [
                "anthropic.claude-code",
                "ms-azuretools.vscode-docker",
                "ms-python.python",
                "ms-python.vscode-pylance",
                "dbaeumer.vscode-eslint",
                "esbenp.prettier-vscode",
                "bradlc.vscode-tailwindcss"
            ],
            "settings": {
                "python.defaultInterpreterPath": "/usr/bin/python3",
                "editor.formatOnSave": true
            }
        }
    }
}
```

### Phase 4: Update Gitignore

#### File: `.gitignore`

```gitignore
# Environment configuration
.env

# Workspace projects (except .gitkeep)
workspace/*
!workspace/.gitkeep

# Test/debug scripts (local only)
push-changes.sh
test-sync.sh
.dev/
```

### Phase 5: Create Test Script

#### File: `test-sync.sh` (gitignored, for local testing)

```bash
#!/bin/bash
set -e

CLAUDIO_BRANCH="${1:-feature-setup2}"
TRAINER2_BRANCH="${2:-feature/dev_container_setup}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
CLAUDIO_DIR="$SCRIPT_DIR"
TRAINER2_DIR="$PARENT_DIR/trainer2"

# Step 1: Pull Claudio
cd "$CLAUDIO_DIR"
git fetch origin
git checkout "$CLAUDIO_BRANCH"
git pull origin "$CLAUDIO_BRANCH"

# Step 2: Pull Trainer2
cd "$TRAINER2_DIR"
git fetch origin
git checkout "$TRAINER2_BRANCH"
git pull origin "$TRAINER2_BRANCH"

# Step 3: Build base image
cd "$CLAUDIO_DIR"
./build-base.sh

# Step 4: Open both repos in VS Code
cd "$CLAUDIO_DIR"
code .

cd "$TRAINER2_DIR"
code .

echo ""
echo "✓ Both VS Code windows opened"
echo ""
echo "Next: Click 'Reopen in Container' in both windows"
```

## Testing & Validation

### Pre-Testing Checklist

```bash
# 1. Verify .env exists with git config
cat .env
# Should contain:
# GIT_USER_EMAIL=your@email.com
# GIT_USER_NAME=Your Name

# 2. Build base image
./build-base.sh

# 3. Verify base image has git config
docker run --rm claudio-base:latest git config --global --list
# Should show user.email and user.name

# 4. Verify Claude CLI installed
docker run --rm claudio-base:latest claude --version
# Should show version number
```

### Full End-to-End Test

**From WSL Host**:
1. Run `test-sync.sh` (pulls both repos, builds base, opens VS Code)
2. In Claudio VS Code window: Click "Reopen in Container"
3. In Trainer2 VS Code window: Click "Reopen in Container"
4. Wait for both containers to build

**In Claudio Container**:
```bash
# Verify tools installed
claude --version  # Should work
python --version  # Should be 3.12.x
node --version    # Should be 20.x
git config --list # Should show your email/name

# Verify auth volume exists
ls -la ~/.claude/  # Should exist (empty until authenticated)
```

**In Trainer2 Container**:
```bash
# Same verification as Claudio
claude --version
python --version
node --version
git config --list

# Plus Trainer2-specific
docker compose --version  # For running Trainer2 services
```

**Authentication Test**:
1. In VS Code extension, sign in to Claude (OAuth flow)
2. Verify `~/.claude/.credentials.json` created
3. In terminal, run `claude` - should work without re-authenticating
4. Rebuild container - credentials should persist

### Validation Criteria

- ✅ Base image builds without errors
- ✅ Git config baked into image (no runtime setup needed)
- ✅ Claude CLI pre-installed and working
- ✅ Claudio container starts with minimal config
- ✅ Trainer2 container extends base successfully
- ✅ Per-container volumes isolate authentication
- ✅ Both VS Code extension and terminal share auth
- ✅ Credentials persist across container rebuilds
- ✅ No conflicts between Claudio and Trainer2 auth

## Key Design Decisions

### 1. Per-Container Volumes vs Bind Mount

**Decision**: Use per-container volumes for `~/.claude`

**Rationale**:
- Prevents auth conflicts between VS Code extension and terminal
- True isolation between projects
- Cleaner security model
- Each project can have different Claude accounts if needed

**Trade-off**: Must authenticate separately in each container (but credentials persist)

### 2. Git Config Baked Into Image vs Runtime

**Decision**: Bake git config into base image via `.env` build args

**Rationale**:
- Zero runtime configuration needed
- Consistent across all containers using the image
- Simpler devcontainer.json
- One-time setup in `.env` file

**Trade-off**: Must rebuild image if git config changes (rare)

### 3. Standalone Dockerfile vs Image Reference

**Decision**: 
- Claudio uses image directly
- Trainer2 extends via Dockerfile

**Rationale**:
- Claudio doesn't need extra dependencies (just the base)
- Trainer2 may need project-specific Python packages
- Provides template for future projects to extend

**Trade-off**: Trainer2 has one extra file (Dockerfile)

### 4. Python 3.12 Source

**Decision**: Use Ubuntu 24.04 native Python 3.12, NOT deadsnakes PPA

**Rationale**:
- Ubuntu 24.04 ships with Python 3.12
- No PPA needed, simpler installation
- Deadsnakes PPA explicitly doesn't provide Ubuntu 24.04 packages

**Issue Discovered**: Using deadsnakes PPA caused `python3.12-distutils` not found error

### 5. Claude CLI Installation

**Decision**: Install globally in base image with `npm -g i`

**Rationale**:
- Available to all projects using the base
- No per-project installation needed
- Simpler postCreateCommand

**Gotcha**: Must use `sudo npm -g i` if installing at runtime (but we don't need to)

## Common Pitfalls & Solutions

### Pitfall 1: Git Config as Root vs vscode User

**Problem**: If you run `git config --global` as root, vscode user won't see it

**Solution**: Switch to vscode user BEFORE setting git config in Dockerfile

```dockerfile
# ❌ Wrong
USER root
RUN git config --global user.email "..."
USER vscode

# ✅ Correct
USER root
RUN chown vscode:vscode /home/vscode
USER vscode
RUN git config --global user.email "..."
```

### Pitfall 2: pip install wheel conflict

**Problem**: System-installed wheel package conflicts with pip upgrade

**Solution**: Add `--ignore-installed` flag

```bash
python -m pip install --upgrade --break-system-packages --ignore-installed pip setuptools wheel
```

### Pitfall 3: Auth Conflicts with Bind Mount

**Problem**: Bind mounting host `~/.claude` causes VS Code extension and terminal to fight

**Solution**: Use per-container volumes instead

```json
// ❌ Wrong - causes conflicts
"mounts": [
    "source=${localEnv:HOME}/.claude,target=/home/vscode/.claude,type=bind"
]

// ✅ Correct - isolated per container
"mounts": [
    "source=project-claude-${devcontainerId},target=/home/vscode/.claude,type=volume"
]
```

### Pitfall 4: Over-Complicating devcontainer.json

**Problem**: Trying to configure everything at runtime (git config, Claude CLI install, etc.)

**Solution**: Bake it into the base image, keep devcontainer.json minimal

```json
// ❌ Wrong - complex runtime setup
{
    "postCreateCommand": "git config --global user.email ... && git config --global user.name ... && sudo npm -g i @anthropic-ai/claude-code && ..."
}

// ✅ Correct - simple, everything pre-configured
{
    "postCreateCommand": "init-claude-settings.sh && claude --version"
}
```

## File Checklist

**Claudio Repo**:
- [ ] `Dockerfile.base` - Base image definition
- [ ] `build-base.sh` - Build script (loads .env)
- [ ] `.env.example` - Template for git config
- [ ] `.env` - Actual git config (gitignored)
- [ ] `.devcontainer/devcontainer.json` - Simplified config
- [ ] `.gitignore` - Add `.env`, scripts
- [ ] `test-sync.sh` - Test script (gitignored)

**Trainer2 Repo**:
- [ ] `.devcontainer/Dockerfile` - Extends claudio-base
- [ ] `.devcontainer/devcontainer.json` - Build config

**Updated**:
- [ ] `.agents/feature-requests/devcontainer-template-and-trainer2-integration.md` - Non-technical summary
- [ ] `.agents/plans/devcontainer-template-and-trainer2-integration.md` - This file

## Success Metrics

- Base image builds in < 5 minutes
- Devcontainer rebuild in < 2 minutes (using cached base)
- Zero manual configuration needed (except one-time .env setup)
- Authentication works immediately after OAuth
- Both projects can run simultaneously with isolated auth
- Pattern is reusable for future projects

## Next Actions

1. ✅ Create all Claudio files listed above
2. ✅ Build base image and verify
3. ✅ Test Claudio devcontainer
4. ✅ Create Trainer2 devcontainer files
5. ✅ Test Trainer2 devcontainer
6. ✅ Push to GitHub
7. Run end-to-end test from clean environment
8. Document any issues and iterate

