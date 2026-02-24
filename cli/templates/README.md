# Claudio Templates

Templates for integrating Claudio into existing projects. All files are gitignored and local-only.

## v2.1 Simplified Architecture

Claudio v2.1 uses a simplified volume strategy:
- **1 per-container volume**: `claudio-${devcontainerId}` for all local state
- **1 shared volume** (optional): `claudio-shared` for auth/plugins across containers
- **Default user**: `dev` (configurable)

## Quick Start

### Option 1: Simple Image (Recommended)

Just use the Claudio image directly:

```json
{
    "name": "My Project",
    "image": "ghcr.io/ksizzle88/claudio:latest",
    "remoteUser": "dev",
    "mounts": [
        "source=claudio-${devcontainerId},target=/home/dev/.claudio,type=volume"
    ],
    "postCreateCommand": "init-claudio"
}
```

### Option 2: Extended Dockerfile

When you need project-specific dependencies:

```dockerfile
# Dockerfile.local
FROM ghcr.io/ksizzle88/claudio:latest

# Add your dependencies
RUN apt-get update && apt-get install -y your-packages
RUN pip install your-python-packages
```

### Option 3: Docker Compose

For projects with multiple services, add Claudio to your compose:

```yaml
# docker-compose.override.yml
services:
  app:
    build:
      dockerfile: Dockerfile.local
    environment:
      - CLAUDE_CONFIG_DIR=/home/dev/.claude
```

## Template Files

### simple-image/
- `devcontainer.local.json.example` → Copy to `.devcontainer/devcontainer.json`

### extended-dockerfile/
- `devcontainer.local.json.example` → Copy to `.devcontainer/devcontainer.json`
- `Dockerfile.local.example` → Copy to `.devcontainer/Dockerfile.local`

### docker-compose/
- `devcontainer.local.json.example` → Copy to `.devcontainer/devcontainer.json`
- `docker-compose.override.yml.example` → Copy to `docker-compose.override.yml`
- `Dockerfile.local.example` → Copy to `.devcontainer/Dockerfile.local`

## Volume Strategy

```
/home/dev/
├── .claudio/              # Per-container volume (claudio-${devcontainerId})
│   ├── claude/            # Claude config, credentials, history
│   ├── bash-history/      # Shell history
│   └── .initialized       # First-run marker
├── .claude -> .claudio/claude  # Symlink for Claude Code compatibility
└── .claudio-shared/       # Shared volume (optional)
    ├── auth/              # Shared credentials
    └── plugins/           # Shared skills and commands
```

## Shared Volume (Optional)

To share auth/plugins across all containers:

```bash
# Create shared volume once
docker volume create claudio-shared

# Add to devcontainer.json mounts:
"source=claudio-shared,target=/home/dev/.claudio-shared,type=volume"
```

## Notes

- All template files should be gitignored (they contain local paths)
- Default user is `dev` (UID 1000)
- SSH/GPG keys are bind-mounted read-only from host
- `init-claudio` handles all initialization automatically
