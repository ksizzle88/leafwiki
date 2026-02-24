#!/bin/bash
# init-claudio.sh - Simplified initialization for Claudio v2
# Replaces the 414-line init-claude-settings.sh

set -e

# Configuration
CLAUDIO_HOME="${CLAUDIO_HOME:-$HOME/.claudio}"
CLAUDIO_SHARED="${CLAUDIO_SHARED:-$HOME/.claudio-shared}"
DEFAULTS="/opt/claudio-defaults"
CLAUDE_DIR="$CLAUDIO_HOME/claude"

echo "Claudio: Initializing..."

# Phase 1: First-run setup
if [ ! -f "$CLAUDIO_HOME/.initialized" ]; then
    echo "First run - setting up directory structure..."

    # Create directory structure
    mkdir -p "$CLAUDE_DIR"
    mkdir -p "$CLAUDIO_HOME/bash-history"

    # Copy defaults from image
    if [ -d "$DEFAULTS/.claude" ]; then
        cp -r "$DEFAULTS/.claude/"* "$CLAUDE_DIR/" 2>/dev/null || true
        echo "Copied defaults from image"
    fi

    # Copy project-specific overrides (if any)
    if [ -d "/workspace/.claude" ]; then
        # Skip credentials when copying project settings
        find /workspace/.claude -type f ! -name ".credentials.json" -exec cp {} "$CLAUDE_DIR/" \; 2>/dev/null || true
        echo "Applied project-specific settings"
    fi

    touch "$CLAUDIO_HOME/.initialized"
    echo "First-run setup complete"
fi

# Phase 2: Sync with shared volume (if mounted)
if [ -d "$CLAUDIO_SHARED" ]; then
    echo "Syncing with shared volume..."

    # Ensure shared directories exist
    mkdir -p "$CLAUDIO_SHARED/auth"
    mkdir -p "$CLAUDIO_SHARED/plugins/skills"
    mkdir -p "$CLAUDIO_SHARED/plugins/commands"
    mkdir -p "$CLAUDIO_SHARED/caches/npm"
    mkdir -p "$CLAUDIO_SHARED/caches/pip"

    # Credentials sync: newer wins
    LOCAL_CREDS="$CLAUDE_DIR/.credentials.json"
    SHARED_CREDS="$CLAUDIO_SHARED/auth/.credentials.json"

    if [ -f "$SHARED_CREDS" ] && [ -f "$LOCAL_CREDS" ]; then
        # Both exist - use newer
        if [ "$SHARED_CREDS" -nt "$LOCAL_CREDS" ]; then
            cp "$SHARED_CREDS" "$LOCAL_CREDS"
            echo "Updated local credentials from shared"
        elif [ "$LOCAL_CREDS" -nt "$SHARED_CREDS" ]; then
            cp "$LOCAL_CREDS" "$SHARED_CREDS"
            echo "Updated shared credentials from local"
        fi
    elif [ -f "$SHARED_CREDS" ]; then
        # Only shared exists
        cp "$SHARED_CREDS" "$LOCAL_CREDS"
        echo "Copied credentials from shared"
    elif [ -f "$LOCAL_CREDS" ]; then
        # Only local exists
        cp "$LOCAL_CREDS" "$SHARED_CREDS"
        echo "Copied credentials to shared"
    fi

    # GitHub CLI sync
    if [ -d "$CLAUDIO_SHARED/auth/gh" ]; then
        mkdir -p "$HOME/.config/gh"
        cp -ru "$CLAUDIO_SHARED/auth/gh/"* "$HOME/.config/gh/" 2>/dev/null || true
    fi

    # Plugins sync: copy newer files bidirectionally
    if [ -d "$CLAUDIO_SHARED/plugins" ]; then
        cp -ru "$CLAUDIO_SHARED/plugins/"* "$CLAUDE_DIR/" 2>/dev/null || true
        cp -ru "$CLAUDE_DIR/skills" "$CLAUDIO_SHARED/plugins/" 2>/dev/null || true
        cp -ru "$CLAUDE_DIR/commands" "$CLAUDIO_SHARED/plugins/" 2>/dev/null || true
    fi

    # Setup cache symlinks
    if [ -d "$CLAUDIO_SHARED/caches/npm" ]; then
        rm -rf "$HOME/.npm" 2>/dev/null || true
        ln -sf "$CLAUDIO_SHARED/caches/npm" "$HOME/.npm"
    fi

    if [ -d "$CLAUDIO_SHARED/caches/pip" ]; then
        mkdir -p "$HOME/.cache"
        rm -rf "$HOME/.cache/pip" 2>/dev/null || true
        ln -sf "$CLAUDIO_SHARED/caches/pip" "$HOME/.cache/pip"
    fi

    echo "Shared volume sync complete"
else
    echo "No shared volume mounted (standalone mode)"
fi

# Phase 3: Setup symlinks
if [ ! -L "$HOME/.claude" ]; then
    # Remove old directory if it exists and isn't a symlink
    if [ -d "$HOME/.claude" ]; then
        echo "Warning: Old ~/.claude directory found. Run 'claudio migrate' to upgrade."
        # Backup and replace
        mv "$HOME/.claude" "$HOME/.claude.bak.$(date +%s)" 2>/dev/null || true
    fi
    ln -sf "$CLAUDE_DIR" "$HOME/.claude"
fi

# Set environment variable
export CLAUDE_CONFIG_DIR="$HOME/.claude"

# Add to shell profile if not present
for profile in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$profile" ] && ! grep -q "CLAUDE_CONFIG_DIR" "$profile" 2>/dev/null; then
        echo 'export CLAUDE_CONFIG_DIR="$HOME/.claude"' >> "$profile"
    fi
done

# Phase 4: Setup shell history
HISTDIR="$CLAUDIO_HOME/bash-history"
mkdir -p "$HISTDIR"

if [ -n "$ZSH_VERSION" ] || [ "$SHELL" = "/bin/zsh" ]; then
    export HISTFILE="$HISTDIR/.zsh_history"
else
    export HISTFILE="$HISTDIR/.bash_history"
fi

# Phase 5: Verify
echo ""
echo "Claudio initialization complete!"
echo "  Config: $CLAUDE_DIR"
echo "  Shared: ${CLAUDIO_SHARED:-not mounted}"
echo ""

if command -v claude &> /dev/null; then
    claude --version
else
    echo "Warning: Claude Code CLI not found in PATH"
fi
