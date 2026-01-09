# Claudio - Claude Code Devcontainer

A portable, modular devcontainer environment for Claude Code development.

## Structure

```
claudio/
├── .devcontainer/           # Devcontainer configuration
├── .claude/                 # Your default Claude settings (mounted to ~/.claude)
│   ├── settings.json        # Global preferences for all projects
│   ├── settings.local.json  # Personal overrides (gitignored)
│   └── CLAUDE.md            # Your coding style/preferences
├── workspace/               # Mount point for project repositories
│   ├── .gitkeep
│   └── (your-projects/)     # Clone your projects here (gitignored)
└── README.md
```

## Philosophy

- **Single devcontainer** with Claude Code installed globally
- **workspace/** directory for all your projects (gitignored)
- **.claude/** contains your personal defaults, applied to all projects
- **Lightweight, modular, portable** - clone anywhere and rebuild

## Setup

### Prerequisites (Windows)

1. **Docker Desktop** with WSL 2 integration
2. **VS Code** with Dev Containers extension (`ms-vscode-remote.remote-containers`)
3. **ANTHROPIC_API_KEY** environment variable set on host:
   ```powershell
   setx ANTHROPIC_API_KEY "YOUR_KEY_HERE"
   ```
   (Restart VS Code after setting)

### Open the Devcontainer

1. Clone this repo
2. Open in VS Code
3. Command Palette → **Dev Containers: Reopen in Container**
4. Wait for `postCreateCommand` to install Claude Code

Verify installation:
```bash
claude --version
```

## Working with Projects

### Add a Project

Clone your project repos into `workspace/`:

```bash
cd /workspaces/claudio/workspace
git clone https://github.com/yourusername/your-project.git
```

### Open a Project

**Option 1: Single folder**
- File → Open Folder → `/workspaces/claudio/workspace/your-project`

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

These override your defaults in `/workspaces/claudio/.claude/` (your `~/.claude`).

## Configuration Hierarchy

Claude Code reads settings in this order (highest precedence first):

1. **Project settings**: `workspace/your-project/.claude/settings.json`
2. **Your defaults**: `/workspaces/claudio/.claude/settings.json` (mounted to `~/.claude`)
3. **Local overrides**: `.claude/settings.local.json` (gitignored)

## Features

- Docker-outside-of-docker support (access host Docker from container)
- Claude Code CLI and VS Code extension pre-installed
- Persistent user settings via mounted `.claude/` directory
- Clean separation between devcontainer config and project code

## Usage

Inside the container:
```bash
claude              # Start interactive session
claude --help       # View available commands
```

In VS Code:
- Use the Claude Code extension sidebar
- Open files, Claude can access entire workspace

## Notes

- The `workspace/` directory is gitignored (except `.gitkeep`)
- Your `.claude/` settings are committed and portable across machines
- Local overrides (`.claude/settings.local.json`) stay private
- Rebuild container after changing devcontainer configuration
