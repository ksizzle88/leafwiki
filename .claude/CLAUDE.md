# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Claudio** is a production-ready devcontainer environment for Claude Code development. It provides isolated, reproducible Docker-based development environments with:

- Persistent Claude Code authentication and settings across container rebuilds
- Shared volume system for authentication, plugins, and MCP servers across all Claudio containers
- Integration with VS Code extension and terminal Claude CLI
- Support for multiple project workspaces
- Optional shared services (PostgreSQL, Redis)

## Essential Commands

### Building and Publishing

```bash
# Build the base image locally
./build-base.sh

# Build with specific tags
./build-base.sh --tags latest v1.0.0

# Build and push to GitHub Container Registry (ghcr.io)
./build-base.sh --push

# Build with custom tags and push
./build-base.sh --tags latest v1.0.0 --push
```

### First-Time Setup

```bash
# Create shared volumes (one-time setup required before building)
./cli/scripts/create-volumes.sh

# Verify Claudio installation and configuration
claudio verify

# Show version information
claudio version

# Diagnose common issues
claudio doctor
```

### Container Management

```bash
# Rebuild container after Dockerfile or devcontainer.json changes
# Command Palette (Ctrl+Shift+P) → "Dev Containers: Rebuild Container"

# Run side-by-side container for testing (different project name)
docker compose -p claudio_sandbox up -d --build

# Stop side-by-side container
docker compose -p claudio_sandbox down
```

### Git Workflow

```bash
# Normal workflow (automated build/push hook runs on git push if REGISTRY_ENABLED=true)
git add .
git commit -m "feat: description"
git push origin branch-name

# Skip automated build
git push --no-verify origin branch-name
# OR
SKIP_IMAGE_BUILD=true git push origin branch-name
```

### Volume Management

```bash
# List volumes
docker volume ls

# Clean unused volumes
docker volume prune

# Reset Claude settings (forces re-initialization from defaults)
docker volume rm claudio-claude-config-<devcontainerId>
```

## Architecture

### Multi-Layer Volume Strategy

Claudio uses a sophisticated volume system with three isolation levels:

#### 1. Per-Container Volumes (Isolated)
- `claudio-claude-config-${devcontainerId}` → `/home/vscode/.claude`
- `claudio-bashhistory-${devcontainerId}` → `/commandhistory`

**Purpose**: Each devcontainer instance gets its own isolated Claude settings and bash history. Prevents conflicts when working on multiple projects simultaneously.

#### 2. Shared Volumes (Cross-Container)
Created via `./cli/scripts/create-volumes.sh`:

- `claudio-shared-auth` → `/home/vscode/.claude-shared-auth` - Shared Claude authentication
- `claudio-gh-auth` → `/home/vscode/.config/gh-shared` - Shared GitHub CLI authentication
- `claudio-shared-plugins` → `/home/vscode/.claude-shared-plugins` - Custom skills and commands
- `claudio-shared-mcp` → `/home/vscode/.mcp-shared` - MCP server configurations
- `claudio-shared-gitconfig` → `/home/vscode/.gitconfig-shared` - Git configuration (when not using project-specific config)
- `shell-history` → `/home/vscode/.history` - Shell history across all containers

**Purpose**: Enables "configure once, use everywhere" workflow. Authenticate in one container, plugins and credentials sync to all others automatically.

#### 3. Bind Mounts (Live Editing)
- `.:/workspace:cached` - Project root with cached mode for performance
- `workspace/` - User project repositories (gitignored)
- `~/.ssh` → `/home/vscode/.ssh-host` (read-only) - SSH keys from host
- `~/.gnupg` → `/home/vscode/.gnupg-host` (read-only) - GPG keys from host

### Configuration Sync Mechanism

The `init-claude-settings.sh` script runs on container start and performs bidirectional sync:

1. **Credentials Sync**: Newer credentials (by timestamp) propagate between local and shared volumes
2. **Plugin Sync**: Skills, commands, and MCP configs sync bidirectionally using `cp -ru` (update only newer files)
3. **Git Config Sync**: Two modes:
   - `GIT_USE_PROJECT_CONFIG=true` - Uses environment variables (GIT_USER_NAME, GIT_USER_EMAIL) from .env
   - `GIT_USE_PROJECT_CONFIG=false` - Syncs with shared gitconfig volume

**Key Insight**: This architecture enables single authentication for all containers while maintaining per-project isolation where needed.

### Image Build Strategy

**Base Image**: `Dockerfile.base` creates `claudio-base:latest` with:
- Node.js, Python 3.12, GitHub CLI
- Claude Code CLI globally installed
- Claudio management CLI at `/usr/local/bin/claudio`
- Default Claude settings at `/opt/claudio-defaults/.claude/`

**Initialization Flow**:
1. Container starts → `postCreateCommand` runs `init-claude-settings.sh`
2. If `~/.claude` is empty (first run):
   - Copy from `/opt/claudio-defaults/.claude/` (image defaults)
   - Overlay with `/workspace/.claude/` (project-specific)
3. Sync credentials/plugins/git config with shared volumes
4. Set up SSH/GPG from host mounts

### Configuration Hierarchy

Claude Code reads configuration in order (highest precedence first):

1. **Project settings**: `/workspace/<project>/.claude/settings.json` (project-specific overrides)
2. **User settings**: `~/.claude/settings.json` (persisted in per-container volume)
3. **Local overrides**: `~/.claude/settings.local.json` (gitignored personal customizations)

## Using Claudio in External Repositories

Claudio can be integrated into any repository using **local, gitignored files only** (never commits to version control):

### Integration Files (all gitignored)

1. **Dockerfile.local** - Extends `ghcr.io/ksizzle88/claudio:latest` with project dependencies
2. **devcontainer.local.json** - Adds Claudio volume mounts and configuration
3. **docker-compose.override.yml** - For docker-compose projects

### Templates Available

See `cli/templates/` (or `/usr/local/lib/claudio/templates/` inside containers):

- **simple-image/** - Direct image reference, no custom Dockerfile
- **extended-dockerfile/** - Add project-specific dependencies
- **docker-compose/** - For projects using docker-compose orchestration

### Multi-Stage Build Pattern

When extending existing project images:

```dockerfile
# syntax=docker/dockerfile:1
FROM ghcr.io/ksizzle88/claudio:latest AS claudio
FROM your-existing-image:latest

# Copy Claudio components
COPY --from=claudio /usr/bin/node /usr/bin/node
COPY --from=claudio /usr/lib/node_modules /usr/lib/node_modules
COPY --from=claudio /usr/local/bin/init-claude-settings.sh /usr/local/bin/
COPY --from=claudio /usr/local/bin/install-claudio.sh /usr/local/bin/
COPY --from=claudio /opt/claudio-defaults/.claude/ /opt/claudio-defaults/.claude/

# Run installation script (handles symlinks, permissions, environment)
RUN /usr/local/bin/install-claudio.sh
```

## Automated Build System

### Two Complementary Systems

1. **GitHub Actions** (`.github/workflows/build-push-image.yml`)
   - Triggers on push to `main`/`master`
   - No setup required - uses `GITHUB_TOKEN` automatically
   - Builds on GitHub infrastructure

2. **Git Pre-Push Hook** (`.devcontainer/hooks/pre-push`)
   - Triggers on `git push` from local machine
   - Requires setup via `.env` configuration
   - Builds locally before pushing code
   - Aborts git push if build fails

### Configuration (.env file)

```bash
# Enable/disable automated builds
REGISTRY_ENABLED=true

# Registry configuration
REGISTRY_URL=ghcr.io
REGISTRY_USERNAME=your-github-username
REGISTRY_IMAGE_NAME=claudio  # Auto-detected from git remote, override if needed

# GitHub PAT with write:packages scope
GITHUB_PACKAGE_PAT=ghp_your_token_here

# Git configuration (for project-specific identity)
GIT_USER_EMAIL=your.email@example.com
GIT_USER_NAME=Your Name
GIT_GPG_SIGN=false
GIT_SIGNING_KEY=
```

## Key Architectural Decisions

### Why Per-Container Volumes for Claude Config?

- **Isolation**: Different projects can use different Claude authentication (e.g., different API keys, different organizations)
- **Conflict Prevention**: VS Code extension and terminal CLI never conflict
- **Security**: Multi-client work keeps credentials separate

### Why Shared Volumes for Auth/Plugins?

- **DX Improvement**: Log in once, works everywhere
- **Consistency**: Same MCP servers, skills, and commands across all projects
- **Efficiency**: No redundant configuration

### Why Two Git Config Modes?

- **Project-specific** (`GIT_USE_PROJECT_CONFIG=true`): For repos like Claudio that need their own identity
- **Shared** (`GIT_USE_PROJECT_CONFIG=false`): For general development using host's git identity

## Common Development Workflows

### Adding a New MCP Server

```bash
# In any Claudio container
npm install -g @anthropic/mcp-server-filesystem

# Configure (syncs to all containers automatically)
cat > ~/.claude/mcp.json <<EOF
{
  "mcpServers": {
    "filesystem": {
      "command": "mcp-server-filesystem",
      "args": ["--root", "/workspace"]
    }
  }
}
EOF

# All other Claudio containers get this config on next start
```

### Working with Multiple Projects

```bash
# Clone projects into workspace directory
cd /workspace/workspace
git clone https://github.com/yourorg/project1.git
git clone https://github.com/yourorg/project2.git

# Open in VS Code
# File → Open Folder → /workspace/workspace/project1

# Or create multi-project workspace
# File → Add Folder to Workspace
```

### Testing Changes Without Disrupting Current Container

```bash
# Run side-by-side with different project name
docker compose -p claudio_test up -d --build

# VS Code: Attach to the test container
# Remote Explorer → Containers → claudio_test-devcontainer

# Clean up when done
docker compose -p claudio_test down
```

## Agent Teams (Parallel Pipeline)

Claudio supports two complementary modes for multi-agent work:

- **`/pipeline`** (sequential): Runs research -> plan -> implement -> review stages one at a time using subagents. Best for standard feature implementation where each stage depends on the previous.
- **`/pipeline-team`** (parallel): Creates an Agent Team where multiple teammates work simultaneously. Best for tasks with independent sub-problems.

### When to Use Agent Teams vs Subagents

| Criteria | Subagents (/pipeline) | Agent Teams (/pipeline-team) |
|----------|----------------------|------------------------------|
| Task type | Linear, dependent stages | Independent, parallelizable work |
| Communication | Report results back to coordinator only | Teammates message each other directly |
| Best for | Standard features, bug fixes | Research, multi-module refactoring, parallel review |
| Token cost | Lower | Higher (each teammate has its own context window) |
| Coordination | Coordinator manages everything | Shared task list with self-coordination |

### Quick Start

```bash
# Sequential pipeline (existing)
/pipeline 7

# Parallel team pipeline (new)
/pipeline-team 7
```

### Configuration

Agent Teams are enabled via settings.json:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

The `teammateMode` setting controls display:
- `"auto"` (default): Uses split panes if inside a tmux session, in-process otherwise
- `"in-process"`: All teammates in one terminal. Use Shift+Down to cycle.
- `"tmux"`: Force split-pane mode (requires tmux, which is installed in the base image)

### Quality Gate Hooks

Two hooks enforce basic quality gates for Agent Teams:

- **TeammateIdle** (`.claude/hooks/teammate-idle.sh`): Runs when a teammate is about to go idle. Currently a no-op placeholder for future quality gates.
- **TaskCompleted** (`.claude/hooks/task-completed.sh`): Runs when a task is marked complete. Currently a no-op placeholder for future quality gates.

These hooks exit with code 2 to block the action and provide feedback to the teammate. Exit 0 allows the action to proceed.

### Team Patterns

Common team structures for different task types:

1. **Research Team** (3-4 teammates): Investigate different aspects of a problem simultaneously
2. **Implementation Team** (2-4 teammates): Each teammate owns a separate module or file set
3. **Review Team** (3 teammates): Security, quality, and test coverage reviewers in parallel

### Tips

- Keep teams small: 3-5 teammates is the sweet spot
- Assign distinct file sets to each teammate to avoid conflicts
- Use `Ctrl+T` to view the shared task list
- The lead coordinates everything; interact with the lead to steer the team
- Clean up the team after the task is complete

## Troubleshooting

### Authentication Not Working

```bash
# Verify CLAUDE_CONFIG_DIR
echo $CLAUDE_CONFIG_DIR  # Should be /home/vscode/.claude

# Check credentials exist
ls -la ~/.claude/.credentials.json

# Try manual authentication
claude login

# Rebuild if persistent
# Command Palette → "Dev Containers: Rebuild Container"
```

### Shared Volumes Not Syncing

```bash
# Verify volumes exist
docker volume ls | grep claudio-shared

# Create if missing
./cli/scripts/create-volumes.sh

# Check sync occurred
claudio verify
```

### Build Failures

```bash
# Test Dockerfile locally
docker build -f Dockerfile.base .

# Check for syntax errors
docker build -f Dockerfile.base --check .

# View build logs
docker compose logs devcontainer
```

## Security Considerations

- Container runs as non-root user (`vscode`)
- `.dockerignore` excludes secrets from build context
- Environment variables for sensitive data (never commit .env)
- Resource limits prevent container sprawl
- SSH/GPG keys mounted read-only from host
- Commit signing supported via GPG_TTY configuration

## Reference Documentation

Detailed best practices in `.claude/reference/`:

- `cli-best-practices.md` - Shell scripting and CLI development
- `deployment-best-practices.md` - Production deployment strategies
- `docker-devcontainer-best-practices.md` - Container development patterns
- `fastapi-best-practices.md` - Python FastAPI development
- `github-cicd-best-practices.md` - CI/CD and GitHub Actions
- `react-frontend-best-practices.md` - React frontend development
- `sqlite-best-practices.md` - SQLite database usage
- `testing-and-logging.md` - Testing strategies and logging patterns

## Git Conventions

- Use conventional commit format: `type: description`
  - `feat:` - New features
  - `fix:` - Bug fixes
  - `docs:` - Documentation changes
  - `chore:` - Maintenance tasks
  - `refactor:` - Code restructuring
- Keep commits focused and atomic
- All commits are signed (GPG) when `GIT_GPG_SIGN=true`
