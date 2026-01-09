# Claudio: Claude Code Development Environment

This file documents the purpose, architecture, and conventions for the Claudio project - a production-ready devcontainer environment for Claude Code development.

## Project Overview

**Claudio** is a containerized development environment optimized for working with Claude Code (Anthropic's CLI tool). It follows Docker and devcontainer best practices to provide:

- Isolated, reproducible development environments
- Persistent user settings across container rebuilds
- Support for multiple project workspaces
- Integration with Claude Code CLI and VS Code extension
- Optional shared services (PostgreSQL, Redis, etc.)

## Architecture

### Container Strategy

- **Base Image**: Microsoft's devcontainer Ubuntu 24.04 image
- **Build Optimization**: Dockerfile layers ordered from least to most frequently changing
- **Performance**: BuildKit cache mounts for faster rebuilds
- **Security**: Non-root user (vscode), explicit permissions

### Volume Management

#### Named Volumes (Persistent Data)
- `claude-settings` → `/home/vscode/.claude` - User Claude settings persist across rebuilds
- `shell-history` → `/home/vscode/.history` - Command history persistence

#### Bind Mounts (Live Editing)
- `.:/workspace:cached` - Project root with cached mode for better performance on macOS/Windows
- `workspace/` directory contains user project repositories (gitignored)

### Configuration Hierarchy

1. **Project defaults** (committed): `.claude/` directory with reference documentation
2. **User settings** (persisted): `~/.claude/` in named volume (copied from defaults on first run)
3. **Local overrides** (gitignored): `~/.claude/settings.local.json` for personal customizations

## Development Guidelines

### Code Style

- Write clean, readable code with descriptive variable names
- Prefer functional programming patterns where appropriate
- Keep functions small and focused on a single responsibility
- Follow language-specific best practices (see [.claude/reference/](reference/) directory)

### Docker Best Practices

- Always use `.dockerignore` to exclude unnecessary files from build context
- Order Dockerfile instructions from least to most frequently changing
- Use BuildKit cache mounts for package managers (apt, npm, pip)
- Run containers as non-root users
- Add meaningful HEALTHCHECK instructions
- Set resource limits in docker-compose.yml

### Testing

- Write tests for new features and bug fixes
- Use descriptive test names that explain what is being tested
- Aim for meaningful test coverage (see [testing-and-logging.md](reference/testing-and-logging.md))

### Documentation

- Document architectural decisions and non-obvious logic
- Keep comments up-to-date with code changes
- Update README when making structural changes
- Maintain reference documentation in `.claude/reference/`

### Git Conventions

- Write clear, concise commit messages
- Use conventional commit format: `type: description`
  - `feat:` for new features
  - `fix:` for bug fixes
  - `docs:` for documentation changes
  - `chore:` for maintenance tasks
  - `refactor:` for code restructuring
- Keep commits focused on a single logical change

## Claude Code Configuration

### Permissions

This project grants Claude Code the following permissions by default:

```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(npm:*)",
      "Bash(node:*)",
      "Bash(docker:*)",
      "Bash(ls:*)",
      "Bash(find:*)"
    ]
  }
}
```

Additional permissions can be added in `settings.local.json` without affecting team settings.

### Model Configuration

Default model: **claude-sonnet-4-5-20250929**

This can be overridden in `settings.local.json` for personal preference.

## Project Structure

```
claudio/
├── .devcontainer/
│   ├── Dockerfile                    # Optimized with BuildKit caching
│   ├── devcontainer.json             # VS Code devcontainer config
│   └── init-claude-settings.sh       # First-run initialization
├── .claude/                          # Project defaults (committed)
│   ├── settings.json                 # Team-wide settings
│   ├── CLAUDE.md                     # This file
│   └── reference/                    # Best practices documentation
├── workspace/                        # User projects (gitignored)
│   ├── .gitkeep
│   └── (your-projects/)              # Clone repos here
├── .dockerignore                     # Excludes from build context
├── docker-compose.yml                # Service orchestration
└── README.md                         # Setup instructions
```

## Working with Projects

### Adding New Projects

Clone projects into the `workspace/` directory:

```bash
cd /workspace/workspace
git clone https://github.com/yourorg/your-project.git
```

### Project-Specific Settings

Projects can override user settings by creating a `.claude/` directory:

```
workspace/your-project/
└── .claude/
    ├── settings.json     # Project-specific permissions
    └── CLAUDE.md         # Project documentation
```

## Resource Management

### Container Resources

Current limits (adjust in docker-compose.yml as needed):
- **CPU**: 2.0 cores limit, 1.0 core reservation
- **Memory**: 4GB limit, 2GB reservation

### Volume Cleanup

Periodically clean unused volumes:
```bash
docker volume prune
```

To reset Claude settings:
```bash
docker volume rm claudio_claude-settings
```

## Shared Services

The docker-compose.yml includes optional services (commented out):
- PostgreSQL 16
- Redis 7

Uncomment and configure as needed for your projects.

## Maintenance

### Updating Dependencies

1. **Node.js version**: Change `NODE_VERSION` arg in docker-compose.yml
2. **Base image**: Update `FROM` in Dockerfile
3. **Claude Code**: Runs `npm -g i @anthropic-ai/claude-code` via postCreateCommand

### Container Rebuild

After Dockerfile or devcontainer.json changes:
- Command Palette → **Dev Containers: Rebuild Container**

## Security Considerations

- Never commit secrets to `.env` files
- Use environment variables for sensitive configuration
- Claude settings volumes are user-specific
- Containers run as non-root user (vscode)
- Regular security scanning recommended (Trivy, Snyk)

## Reference Documentation

See [.claude/reference/](reference/) for detailed best practices:
- [deployment-best-practices.md](reference/deployment-best-practices.md)
- [fastapi-best-practices.md](reference/fastapi-best-practices.md)
- [react-frontend-best-practices.md](reference/react-frontend-best-practices.md)
- [testing-and-logging.md](reference/testing-and-logging.md)
- [sqlite-best-practices.md](reference/sqlite-best-practices.md)

## Contributing

When contributing to this project:
1. Follow the established architecture patterns
2. Update documentation for significant changes
3. Test changes in a clean container
4. Use conventional commit messages
5. Keep changes focused and atomic

## Support

For issues or questions:
- GitHub Issues: (repository URL)
- Claude Code Documentation: https://docs.anthropic.com/claude-code
- VS Code Devcontainers: https://code.visualstudio.com/docs/devcontainers/containers
