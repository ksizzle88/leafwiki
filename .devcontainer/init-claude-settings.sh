#!/bin/bash
set -e

# Initialize Claude settings with defaults
# Configure via environment variables

# Auto-detect current user and set defaults
CURRENT_USER=$(whoami)
if [ "$CURRENT_USER" = "root" ]; then
    DEFAULT_HOME="/root"
else
    DEFAULT_HOME="/home/$CURRENT_USER"
fi

CLAUDE_HOME="${CLAUDE_HOME:-$DEFAULT_HOME/.claude}"
IMAGE_DEFAULTS="${IMAGE_DEFAULTS:-/opt/claudio-defaults/.claude}"
PROJECT_CLAUDE="${PROJECT_CLAUDE:-/workspace/.claude}"

echo "Initializing Claude settings..."
echo "  Claude Home: $CLAUDE_HOME"

# Create CLAUDE_HOME if it doesn't exist
mkdir -p "$CLAUDE_HOME"

# Only initialize if CLAUDE_HOME is empty (first run for this container)
if [ -z "$(ls -A "$CLAUDE_HOME" 2>/dev/null)" ]; then
    echo "First run detected for this container."

    # Step 1: Copy image defaults (shared commands, reference, settings)
    if [ -d "$IMAGE_DEFAULTS" ] && [ -n "$(ls -A "$IMAGE_DEFAULTS" 2>/dev/null)" ]; then
        echo "Copying shared defaults from image ($IMAGE_DEFAULTS)..."
        cp -r "$IMAGE_DEFAULTS"/* "$CLAUDE_HOME/"
    fi

    # Step 2: Overlay project-specific .claude/ (overrides image defaults)
    if [ -d "$PROJECT_CLAUDE" ] && [ -n "$(ls -A "$PROJECT_CLAUDE" 2>/dev/null)" ]; then
        echo "Overlaying project-specific settings from $PROJECT_CLAUDE..."

        # Copy everything except credentials
        find "$PROJECT_CLAUDE" -maxdepth 1 -type f ! -name ".credentials.json" -exec cp {} "$CLAUDE_HOME/" \;

        # Merge directories (commands, reference, skills) - project files override image defaults
        for dir in commands reference skills; do
            if [ -d "$PROJECT_CLAUDE/$dir" ]; then
                mkdir -p "$CLAUDE_HOME/$dir"
                cp -r "$PROJECT_CLAUDE/$dir"/* "$CLAUDE_HOME/$dir/" 2>/dev/null || true
            fi
        done
    fi

    echo "Claude settings initialized."
else
    echo "$CLAUDE_HOME already initialized, skipping."
fi

# ALWAYS add CLAUDE_CONFIG_DIR to shell profile (even if CLAUDE_HOME existed)
SHELL_RC="$DEFAULT_HOME/.bashrc"
if [ -f "$SHELL_RC" ] && ! grep -q "CLAUDE_CONFIG_DIR" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# Claude Code configuration" >> "$SHELL_RC"
    echo "export CLAUDE_CONFIG_DIR=$CLAUDE_HOME" >> "$SHELL_RC"
    echo "Added CLAUDE_CONFIG_DIR to $SHELL_RC"
fi

echo ""
echo "Authentication: Authenticate using VS Code extension or 'claude login'"
echo "CLAUDE_CONFIG_DIR: ${CLAUDE_CONFIG_DIR:-$CLAUDE_HOME}"
