# Claudio - Claude Code Development Container

A production-ready, highly optimized devcontainer environment for Claude Code development. Built following 2026 Docker, devcontainer, and Claude Code best practices with comprehensive security, performance optimization, and developer experience enhancements.

## Features

🚀 **Performance Optimized**

- BuildKit cache mounts for 3-5x faster rebuilds
- Optimized Dockerfile layer ordering
- Cached bind mounts for better I/O on macOS/Windows
- Named volumes for package directories

🔒 **Security Hardened**

- Non-root user execution (vscode)
- Comprehensive `.dockerignore` excludes secrets
- Resource limits prevent container sprawl
- Regular security scanning recommendations (Trivy/Snyk)

🏗️ **Production-Grade Architecture**

dev- Named volumes for persistent data (settings, history)
- Healthchecks for container monitoring
- Labels for metadata and organization
- Multi-project workspace support

🛠️ **Developer Experience**

- Claude Code CLI and VS Code extension pre-installed
- Persistent shell history across sessions
- Project-specific configuration support
- Optional shared services (PostgreSQL, Redis)

## Quick Start

### Prerequisites

1. **Docker Desktop** with WSL 2 (Windows) or Docker Engine (Mac/Linux)
2. **VS Code** with [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
3. __Claude.ai Account__ (for OAuth authentication) or __ANTHROPIC_API_KEY__ (for token-based auth)

### First-Time Setup

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/claudio.git
cd claudio

# 2. (Optional) Customize defaults
# Edit .claude/settings.json and .claude/CLAUDE.md

# 3. Open in VS Code
code .

# 4. Reopen in Container
# Command Palette (Ctrl+Shift+P) → "Dev Containers: Reopen in Container"

# 5. Verify installation (inside container)
claude --version
node --version
npm --version

# 6. Authenticate Claude Code
# Option A: Using VS Code Extension (OAuth - Recommended)
# - The Claude Code extension will prompt you to authenticate via browser
# - This creates OAuth credentials shared between VS Code and terminal

# Option B: Using Terminal (Long-lived token)
claude setup-token
# Follow the prompts to authenticate

```

## Running Side-by-Side (Sandbox Testing)

This repo uses Docker Compose for the devcontainer. To test changes without disrupting your currently-running VS Code devcontainer, run Compose under a different **project name**.

- One-off sandbox run (recommended): `docker compose -p claudio_sandbox up -d --build`
- Equivalent using an env var: `COMPOSE_PROJECT_NAME=claudio_sandbox docker compose up -d --build`
- Stop/remove only the sandbox stack: `docker compose -p claudio_sandbox down`

Why this works: Compose prefixes container/network/volume names with the project name. Avoid using `container_name:` in `docker-compose.yml`, because it disables that isolation and causes collisions.

## Architecture

### Directory Structure

```ini
claudio/
├── .devcontainer/
│   ├── Dockerfile                    # Optimized with BuildKit + cache mounts
│   ├── devcontainer.json             # VS Code devcontainer configuration
│   └── init-claude-settings.sh       # First-run initialization script
├── .claude/                          # Claude Code configuration (committed)
│   ├── settings.json                 # Team-wide permissions & preferences
│   ├── settings.local.json           # Personal overrides (gitignored)
│   ├── CLAUDE.md                     # Project documentation & guidelines
│   └── reference/                    # Best practices documentation
│       ├── deployment-best-practices.md
│       ├── fastapi-best-practices.md
│       ├── react-frontend-best-practices.md
│       ├── testing-and-logging.md
│       └── sqlite-best-practices.md
├── workspace/                        # User projects (gitignored except .gitkeep)
│   ├── .gitkeep
│   └── (your-projects/)              # Clone your repos here
├── .dockerignore                     # Excludes from build context
├── docker-compose.yml                # Service orchestration with healthchecks
├── .gitignore
└── README.md                         # This file

```

### Volume Strategy

**Per-Container Volumes** (isolated per devcontainer instance):

- `claudio-claude-config-${devcontainerId}` → `/home/vscode/.claude` - Claude settings and credentials (isolated per container)
- `claudio-bashhistory-${devcontainerId}` → `/commandhistory` - Command history (isolated per container)

**Shared Volumes** (persist across all containers):

- `shell-history` → `/home/vscode/.history` - Shared shell history

**Bind Mounts** (live editing):

- `.:/workspace:cached` - Project source with cached mode for performance
- `workspace/` contains your project repositories (gitignored)

**Why Per-Container Volumes?**

- Isolates authentication credentials between different projects
- Prevents conflicts between VS Code extension and terminal Claude CLI
- Follows official Claude Code devcontainer pattern
- More secure for multi-client or multi-project work

### Configuration Hierarchy

Claude Code reads configuration in this order (highest precedence first):

1. **Project settings**: `workspace/your-project/.claude/settings.json`
2. **User settings**: `~/.claude/settings.json` (in per-container volume)
3. **Local overrides**: `~/.claude/settings.local.json` (gitignored)

### Authentication

**Unified Authentication**: VS Code extension and terminal Claude CLI share the same authentication stored in `/home/vscode/.claude/.credentials.json`. Both use OAuth via Claude.ai by default.

**Authentication Methods**:

- **OAuth (Recommended)**: Log in via browser when prompted by VS Code extension
- **Long-lived Token**: Run `claude setup-token` in terminal for API token authentication

## Working with Projects

### Mounting Local Projects

You can mount local projects from your host machine into the workspace using Docker Compose overrides:

**1. Create override file** (first time only):

```bash
cp docker-compose.override.yml.template docker-compose.override.yml
```

**2. Edit `docker-compose.override.yml`** and add your projects:

```yaml
version: '3.8'

services:
  devcontainer:
    volumes:
      - /home/username/workspaces/project1:/workspace/workspace/project1:cached
      - /home/username/workspaces/project2:/workspace/workspace/project2:cached
      - /home/username/sites/my-website:/workspace/workspace/my-website:cached
```

**3. Rebuild container**:

```sh
Command Palette → "Dev Containers: Rebuild Container"
```

Your projects will be available at `/workspace/workspace/<project-name>/`

**Note**: `docker-compose.override.yml` is gitignored and automatically merged with `docker-compose.yml`, so your local paths won't affect other developers.

### Adding Projects

Clone your projects into the `workspace/` directory:

```bash
cd /workspace/workspace
git clone https://github.com/yourorg/your-project.git
cd your-project

```

### Opening Projects

**Single Project**:

- File → Open Folder → `/workspace/workspace/your-project`

**Multi-Project Workspace**:

- File → Add Folder to Workspace → Select multiple projects
- Save as `workspace.code-workspace`

### Project-Specific Configuration

Override global settings for specific projects:

```bash
cd /workspace/workspace/your-project
mkdir .claude
cat > .claude/settings.json <<EOF
{
  "permissions": {
    "allow": [
      "Bash(pytest:*)",
      "Bash(make:*)"
    ]
  }
}
EOF

```

## Advanced Configuration

### Resource Limits

Adjust in `docker-compose.yml`:

```yaml
deploy:
  resources:
    limits:
      cpus: '2.0'      # Maximum CPU cores
      memory: 4G       # Maximum memory
    reservations:
      cpus: '1.0'      # Guaranteed CPU cores
      memory: 2G       # Guaranteed memory

```

### Shared Services

Uncomment services in `docker-compose.yml` for shared databases:

```yaml
postgres:
  image: postgres:16-alpine
  environment:
    POSTGRES_PASSWORD: dev
  # ...

redis:
  image: redis:7-alpine
  # ...

```

Access from projects using service names as hostnames:

```python
# Example: PostgreSQL connection
DATABASE_URL = "postgresql://postgres:dev@postgres:5432/mydb"

```

### Custom Node.js Version

Change the `NODE_VERSION` build arg in `docker-compose.yml`:

```yaml
services:
  devcontainer:
    build:
      args:
        NODE_VERSION: 22  # Change to desired version

```

## Maintenance

### Container Rebuild

After changes to Dockerfile or devcontainer.json:

```sh
Command Palette → "Dev Containers: Rebuild Container"

```

### Volume Management

```bash
# List volumes
docker volume ls

# Clean unused volumes
docker volume prune

# Reset Claude settings (starts fresh from defaults)
docker volume rm claudio_claude-settings

```

### Updating Dependencies

- **Claude Code**: Automatically updated via `postCreateCommand`
- __Node.js__: Change `NODE_VERSION` in docker-compose.yml
- **System packages**: Add to Dockerfile and rebuild

## Best Practices Applied

This project implements current best practices from:

### Docker

- ✅ Multi-stage build strategy (where applicable)
- ✅ BuildKit cache mounts (`--mount=type=cache`)
- ✅ Optimized layer ordering (least → most frequently changing)
- ✅ Comprehensive `.dockerignore`
- ✅ Non-root user execution
- ✅ Security scanning recommendations

### Docker Compose

- ✅ Healthchecks for service monitoring
- ✅ Resource limits and reservations
- ✅ Labels for metadata
- ✅ Named volumes for performance
- ✅ Network isolation

### Devcontainers

- ✅ Features for reusable components
- ✅ Separate postCreateCommand vs postStartCommand
- ✅ Named volumes for node_modules and dependencies
- ✅ Docker-outside-of-docker support

### Claude Code

- ✅ Settings hierarchy (project → user → local)
- ✅ Named volume persistence
- ✅ Initialization script for first-run setup
- ✅ Permission management with wildcards
- ✅ Comprehensive reference documentation

## Security

### Implemented Measures

- Container runs as non-root user (`vscode`)
- `.dockerignore` prevents secret exposure
- Environment variables for sensitive data
- Resource limits prevent DoS
- Regular dependency updates recommended

### Recommended Tools

```bash
# Scan images for vulnerabilities
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image claudio-devcontainer:latest

# Alternative: Snyk (requires account)
snyk container test claudio-devcontainer:latest

```

## Troubleshooting

### Container won't start

1. Check Docker is running: `docker ps`
2. Verify ANTHROPIC_API_KEY is set: `echo $ANTHROPIC_API_KEY`
3. Rebuild container: Dev Containers → Rebuild Container

### Performance issues

1. Enable WSL 2 integration (Windows)
2. Allocate more resources in Docker Desktop settings
3. Adjust resource limits in docker-compose.yml

### Settings not persisting

1. Verify per-container volumes exist: `docker volume ls | grep claudio-claude-config`

2. Check initialization script ran: `ls ~/.claude`

3. Check CLAUDE_CONFIG_DIR is set: `echo $CLAUDE_CONFIG_DIR`

4. Reset settings volume if corrupted:

```bash
# Find your container ID
docker ps -a | grep claudio
# Remove the specific volume (replace with actual volume name)
docker volume rm claudio-claude-config-<your-devcontainerId>

```

### Authentication not working

**Symptom**: VS Code Claude works but terminal `claude` command doesn't authenticate

**Solution**:

1. Verify CLAUDE_CONFIG_DIR is set: `echo $CLAUDE_CONFIG_DIR` (should be `/home/vscode/.claude`)

2. Check credentials exist: `ls -la ~/.claude/.credentials.json`

3. Try terminal authentication:

```bash
claude setup-token

```

4. If VS Code extension authenticated, the terminal should automatically use the same credentials

5. Rebuild container if issue persists:

```sh
Command Palette → Dev Containers: Rebuild Container

```

## Contributing

Contributions welcome! Please:

1. Follow conventional commit format: `type: description`
2. Update documentation for significant changes
3. Test in a clean container rebuild
4. Review [.claude/CLAUDE.md](.claude/CLAUDE.md) for project guidelines

## Resources

**Documentation**:

- [Claude Code Documentation](https://docs.anthropic.com/claude-code)
- [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)

**Best Practices Sources**:

- [Ultimate Guide to Dev Containers](https://www.daytona.io/dotfiles/ultimate-guide-to-dev-containers)
- [Docker Build Secrets Guide](https://www.datacamp.com/tutorial/docker-build-secrets-guide)
- [Dev Containers: Multiple Projects](https://dev.to/graezykev/dev-containers-part-5-multiple-projects-shared-container-configuration-2hoi)

**Security**:

- [Trivy Container Scanner](https://github.com/aquasecurity/trivy)
- [Snyk Container Security](https://snyk.io/product/container-vulnerability-management/)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)

## License

[MIT License](LICENSE)

## Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/claudio/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/claudio/discussions)
- **Claude Code**: [Anthropic Support](https://support.anthropic.com/)
