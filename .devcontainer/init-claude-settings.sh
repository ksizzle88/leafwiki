#!/bin/bash
set -e

# Initialize ~/.claude with defaults if it doesn't exist or is empty
CLAUDE_HOME="/home/vscode/.claude"
DEFAULTS_DIR="/workspace/.claude-defaults"

echo "Initializing Claude settings..."

# Create ~/.claude if it doesn't exist
mkdir -p "$CLAUDE_HOME"

# Copy defaults if ~/.claude is empty (first run)
if [ -z "$(ls -A "$CLAUDE_HOME" 2>/dev/null)" ]; then
    echo "First run detected. Copying default settings from $DEFAULTS_DIR"
    if [ -d "$DEFAULTS_DIR" ] && [ -n "$(ls -A "$DEFAULTS_DIR" 2>/dev/null)" ]; then
        cp -r "$DEFAULTS_DIR"/* "$CLAUDE_HOME/"
        echo "Default settings copied to ~/.claude"
    else
        echo "No defaults found, creating minimal settings.json"
        cat > "$CLAUDE_HOME/settings.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(npm:*)",
      "Bash(node:*)"
    ]
  }
}
EOF
    fi
else
    echo "~/.claude already initialized, skipping defaults copy"
fi

echo "Claude settings initialization complete"
