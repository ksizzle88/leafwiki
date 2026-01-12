# Claudio-Dev Specific Commands

This directory contains Claude Code commands and configuration specific to **claudio-dev** development.

## Purpose

- **`.claude/`** - Shared commands baked into `claudio-base:latest` (available to all projects)
- **`.claude-dev/`** - Claudio-dev only commands (NOT in base image)

## What Goes Here

Commands for developing and testing the claudio devcontainer itself:
- `/claudio-dev` - Test command to verify dev commands loaded
- `/build-base` - Build the base image
- `/test-sync` - Sync and test workflow
- Debugging and development utilities

## How It Works

1. `.claude-dev/` is excluded from base image build (via `.dockerignore`)
2. When claudio-dev container starts, `postCreateCommand` copies `.claude-dev/*` to `~/.claude/`
3. Commands become available in claudio-dev container only

## Adding New Commands

Create `.md` files in `.claude-dev/commands/`:

```markdown
# /my-command - Description

Command instructions here...
```

Rebuild container to pick up new commands.
