#!/bin/bash
set -e

# Initialize ~/.claude with defaults from:
# 1. Image defaults (/opt/claudio-defaults/.claude/) - shared commands, reference docs
# 2. Project .claude/ (/workspace/.claude/) - project-specific overrides
#
# This script runs on postCreateCommand for each new container

CLAUDE_HOME="/home/vscode/.claude"
IMAGE_DEFAULTS="/opt/claudio-defaults/.claude"
PROJECT_CLAUDE="/workspace/.claude"

echo "Initializing Claude settings..."

# Create ~/.claude if it doesn't exist
mkdir -p "$CLAUDE_HOME"

# Only initialize if ~/.claude is empty (first run for this container)
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

        # Merge directories (commands, reference) - project files override image defaults
        for dir in commands reference; do
            if [ -d "$PROJECT_CLAUDE/$dir" ]; then
                mkdir -p "$CLAUDE_HOME/$dir"
                cp -r "$PROJECT_CLAUDE/$dir"/* "$CLAUDE_HOME/$dir/" 2>/dev/null || true
            fi
        done
    fi

    echo "Claude settings initialized."
    echo "  - Shared commands from base image"
    echo "  - Project-specific overrides applied"
else
    echo "~/.claude already initialized for this container, skipping."
fi

# ALWAYS add CLAUDE_CONFIG_DIR to shell profile (even if ~/.claude existed)
# This ensures terminal sessions can find credentials
if ! grep -q "CLAUDE_CONFIG_DIR" ~/.bashrc 2>/dev/null; then
    echo "" >> ~/.bashrc
    echo "# Claude Code configuration" >> ~/.bashrc
    echo "export CLAUDE_CONFIG_DIR=/home/vscode/.claude" >> ~/.bashrc
    echo "Added CLAUDE_CONFIG_DIR to ~/.bashrc for terminal sessions"
fi

echo ""
echo "Authentication: You'll need to authenticate using:"
echo "  - VS Code: Claude Code extension (OAuth prompt)"
echo "  - Terminal: claude login"
echo ""
echo "CLAUDE_CONFIG_DIR: ${CLAUDE_CONFIG_DIR:-/home/vscode/.claude}"
