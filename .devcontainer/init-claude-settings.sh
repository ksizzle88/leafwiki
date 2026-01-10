#!/bin/bash
set -e

# Initialize ~/.claude with defaults if it doesn't exist or is empty
# This script runs on postCreateCommand for each new container
CLAUDE_HOME="/home/vscode/.claude"
DEFAULTS_DIR="/workspace/.claude"

echo "Initializing Claude settings..."

# Create ~/.claude if it doesn't exist
mkdir -p "$CLAUDE_HOME"

# Copy defaults if ~/.claude is empty (first run for this specific devcontainer)
if [ -z "$(ls -A "$CLAUDE_HOME" 2>/dev/null)" ]; then
    echo "First run detected for this container. Copying default settings from $DEFAULTS_DIR"
    if [ -d "$DEFAULTS_DIR" ] && [ -n "$(ls -A "$DEFAULTS_DIR" 2>/dev/null)" ]; then
        # Only copy non-credential files (settings.json, reference docs, etc.)
        # Credentials (.credentials.json) will be created by Claude CLI on first auth
        find "$DEFAULTS_DIR" -type f -name "*.json" ! -name ".credentials.json" -exec cp {} "$CLAUDE_HOME/" \;
        find "$DEFAULTS_DIR" -type f -name "*.md" -exec cp {} "$CLAUDE_HOME/" \;

        # Copy reference directory if it exists
        if [ -d "$DEFAULTS_DIR/reference" ]; then
            cp -r "$DEFAULTS_DIR/reference" "$CLAUDE_HOME/"
        fi

        echo "Default settings copied to ~/.claude"
        echo "Note: Authentication is per-container. You'll need to authenticate using:"
        echo "  - VS Code: Use the Claude Code extension (will prompt for OAuth)"
        echo "  - Terminal: Run 'claude setup-token' for long-lived token"
    else
        echo "No defaults found, creating minimal settings.json"
        cat > "$CLAUDE_HOME/settings.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(npm:*)",
      "Bash(node:*)",
      "Bash(docker:*)"
    ]
  }
}
EOF
    fi
else
    echo "~/.claude already initialized for this container, skipping defaults copy"
fi

echo "Claude settings initialization complete"
echo "CLAUDE_CONFIG_DIR is set to: ${CLAUDE_CONFIG_DIR:-/home/vscode/.claude}"
