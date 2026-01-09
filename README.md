# Claudio - Claude Code Devcontainer

A production-ready, modular devcontainer environment for Claude Code development following Docker and devcontainer best practices.

## Structure

```
claudio/
├── .devcontainer/
│   ├── Dockerfile                    # Optimized layer caching
│   ├── devcontainer.json             # VS Code devcontainer config
│   └── init-claude-settings.sh       # Initialization script
├── .claude-defaults/                 # Default Claude settings (committed)
│   ├── settings.json                 # Your global preferences
│   └── CLAUDE.md                     # Your coding style
├── workspace/                        # Mount point for projects (gitignored)
│   ├── .gitkeep
│   └── (your-projects/)              # Clone repos here
├── docker-compose.yml                # Service orchestration
├── .gitignore
└── README.md
```

## Architecture & Best Practices

### Named Volumes for Persistence
Following Docker best practices, user settings persist in **named volumes** rather than bind mounts:
- `claude-settings` volume → `~/.claude` (survives container rebuilds)
- `shell-history` volume → `~/.history` (persistent command history)
- On first run, `.claude-defaults/` is copied into the volume

### Docker Compose for Multi-Project Support
The setup uses `docker-compose.yml` for:
- Shared service definitions (postgres, redis, etc.)
- Network isolation between projects
- Consistent volume management
- Easy service scaling

### Optimized Dockerfile Layer Caching
Layers are ordered from least to most frequently changing:
1. Base image (rarely changes)
2. System dependencies (infrequent)
3. Node.js installation (infrequent)
4. Environment config (rare)
5. Init scripts (occasional)
6. Claude Code (installed via postCreateCommand for flexibility)

## Setup

### Prerequisites (Windows)

1. **Docker Desktop** with WSL 2 integration
2. **VS Code** with Dev Containers extension (`ms-vscode-remote.remote-containers`)
3. **ANTHROPIC_API_KEY** environment variable set on host:
   ```powershell
   setx ANTHROPIC_API_KEY "YOUR_KEY_HERE"
   ```
   (Restart VS Code after setting)

### First-Time Setup

1. Clone this repo:
   ```bash
   git clone https://github.com/yourusername/claudio.git
   cd claudio
   ```

2. Customize your defaults (optional):
   - Edit `.claude-defaults/settings.json` for permissions and preferences
   - Edit `.claude-defaults/CLAUDE.md` for your coding style

3. Open in VS Code:
   - Command Palette → **Dev Containers: Reopen in Container**
   - Wait for initialization (copies defaults, installs Claude Code)

4. Verify installation:
   ```bash
   claude --version
   ```

## Working with Projects

### Add a Project

Clone your project repos into `workspace/`:

```bash
cd /workspace/workspace
git clone https://github.com/yourusername/your-project.git
```

### Open a Project

**Option 1: Single folder**
- File → Open Folder → `/workspace/workspace/your-project`

**Option 2: Multi-folder workspace**
- File → Add Folder to Workspace → Add multiple projects
- Save as `workspace.code-workspace`

### Project-Specific Settings

Each project can have its own `.claude/` configuration:

```
workspace/your-project/
└── .claude/
    ├── settings.json     # Project-specific permissions
    └── CLAUDE.md         # Project documentation
```

These override your user defaults stored in the `claude-settings` volume.

## Configuration Hierarchy

Claude Code reads settings in this order (highest precedence first):

1. **Project settings**: `workspace/your-project/.claude/settings.json`
2. **User settings**: `~/.claude/settings.json` (in `claude-settings` volume)
3. **Local overrides**: `~/.claude/settings.local.json` (personal, not synced)

## Shared Services

Uncomment services in `docker-compose.yml` as needed:

```yaml
# PostgreSQL
postgres:
  image: postgres:16-alpine
  # ... configuration

# Redis
redis:
  image: redis:7-alpine
  # ... configuration
```

Projects in `workspace/` can connect to these shared services via the `dev-network`.

## Features

✅ **Docker best practices**
- Named volumes for persistent data
- Optimized layer caching for fast rebuilds
- Docker Compose for service orchestration

✅ **Development optimized**
- Docker-outside-of-docker support
- Persistent shell history
- Shared services across projects

✅ **Claude Code integration**
- CLI and VS Code extension pre-installed
- User settings persist across rebuilds
- Project-specific configuration support

## Usage

### Inside the container:
```bash
claude              # Start interactive session
claude --help       # View available commands
```

### In VS Code:
- Use the Claude Code extension sidebar
- Open files, Claude can access entire workspace
- Multi-folder workspaces supported

## Advanced Topics

### Customizing Your Defaults

Edit files in `.claude-defaults/` and rebuild the container. On next initialization (or delete the `claude-settings` volume), new defaults will be copied.

### Resetting Settings

To start fresh:
```bash
docker volume rm claudio_claude-settings
```
Then rebuild the container to reinitialize from `.claude-defaults/`.

### Adding Shared Services

1. Add service definition to `docker-compose.yml`
2. Rebuild container: Command Palette → **Dev Containers: Rebuild Container**
3. Connect from projects using service name as hostname

## Notes

- The `workspace/` directory is gitignored (except `.gitkeep`)
- Settings in `.claude-defaults/` are committed and portable
- Named volumes persist data even if container is deleted
- Rebuild container after changing Dockerfile or devcontainer.json

## Best Practices Sources

This setup follows recommendations from:
- [Ultimate Guide to Dev Containers](https://www.daytona.io/dotfiles/ultimate-guide-to-dev-containers)
- [VS Code Dev Containers Documentation](https://code.visualstudio.com/docs/devcontainers/containers)
- [Docker Volumes Best Practices](https://docs.docker.com/engine/storage/volumes/)
- [Dev Containers: Multiple Projects & Shared Configuration](https://dev.to/graezykev/dev-containers-part-5-multiple-projects-shared-container-configuration-2hoi)
