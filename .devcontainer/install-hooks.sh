#!/bin/bash
# Install git hooks for automated container build/push
#
# This script copies hook files from .devcontainer/hooks/ to .git/hooks/
# and makes them executable. It runs automatically when the container starts.

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOOKS_SOURCE="/workspace/.devcontainer/hooks"
HOOKS_TARGET="/workspace/.git/hooks"

echo -e "${GREEN}[Hooks]${NC} Installing git hooks..."

# Verify we're in a git repository
if [ ! -d "/workspace/.git" ]; then
    echo -e "${YELLOW}[Hooks]${NC} Not a git repository, skipping hook installation"
    exit 0
fi

# Create hooks directory if it doesn't exist
mkdir -p "$HOOKS_TARGET"

# Install pre-push hook
if [ -f "$HOOKS_SOURCE/pre-push" ]; then
    cp "$HOOKS_SOURCE/pre-push" "$HOOKS_TARGET/pre-push"
    chmod +x "$HOOKS_TARGET/pre-push"
    echo -e "${GREEN}[Hooks]${NC} ✓ Installed pre-push hook"
else
    echo -e "${YELLOW}[Hooks]${NC} Warning: pre-push hook not found at $HOOKS_SOURCE/pre-push"
fi

# Future: Add other hooks here (pre-commit, post-merge, etc.)

echo -e "${GREEN}[Hooks]${NC} Hook installation complete"
