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
        for dir in commands reference skills agents hooks; do
            if [ -d "$PROJECT_CLAUDE/$dir" ]; then
                mkdir -p "$CLAUDE_HOME/$dir"
                cp -r "$PROJECT_CLAUDE/$dir"/* "$CLAUDE_HOME/$dir/" 2>/dev/null || true
            fi
        done
    fi

    echo "Claude settings initialized."
else
    echo "$CLAUDE_HOME already initialized, skipping first-time setup."
fi

# Sync project-specific .claude/ directories on every start
# Ensures hooks, commands, skills, agents, and reference docs
# are kept up to date even on containers with existing volumes.
sync_project_dirs() {
    if [ ! -d "$PROJECT_CLAUDE" ] || [ -z "$(ls -A "$PROJECT_CLAUDE" 2>/dev/null)" ]; then
        return 0
    fi

    echo "Syncing project-specific directories from $PROJECT_CLAUDE..."

    # Sync directories -- project files override local (cp -ru = update only newer)
    for dir in commands reference skills agents hooks; do
        if [ -d "$PROJECT_CLAUDE/$dir" ] && [ -n "$(ls -A "$PROJECT_CLAUDE/$dir" 2>/dev/null)" ]; then
            mkdir -p "$CLAUDE_HOME/$dir"
            cp -ru "$PROJECT_CLAUDE/$dir/"* "$CLAUDE_HOME/$dir/" 2>/dev/null || true
            echo "  Synced $dir from project."
        fi
    done

    # Sync top-level files (settings, etc.) -- exclude credentials
    find "$PROJECT_CLAUDE" -maxdepth 1 -type f ! -name ".credentials.json" -newer "$CLAUDE_HOME" -exec cp -u {} "$CLAUDE_HOME/" \; 2>/dev/null || true
}

# Call project dir sync
sync_project_dirs

# Sync credentials from/to shared auth volume (enables single login across all containers)
sync_shared_credentials() {
    local SHARED_AUTH="${SHARED_AUTH:-$DEFAULT_HOME/.claude-shared-auth}"
    local CRED_FILE=".credentials.json"

    if [ ! -d "$SHARED_AUTH" ]; then
        echo "Shared auth volume not mounted at $SHARED_AUTH, skipping sync"
        return 0
    fi

    echo "Syncing credentials with shared auth volume..."

    # If shared credentials exist and local doesn't, copy from shared
    if [ -f "$SHARED_AUTH/$CRED_FILE" ] && [ ! -f "$CLAUDE_HOME/$CRED_FILE" ]; then
        echo "  Copying credentials from shared auth volume..."
        if cp "$SHARED_AUTH/$CRED_FILE" "$CLAUDE_HOME/$CRED_FILE" 2>/dev/null && chmod 600 "$CLAUDE_HOME/$CRED_FILE" 2>/dev/null; then
            echo "  Credentials copied from shared volume."
        else
            echo "  Warning: Could not read from shared auth volume. Continuing..."
        fi
        return 0
    fi

    # If local credentials exist but shared doesn't, copy to shared
    if [ -f "$CLAUDE_HOME/$CRED_FILE" ] && [ ! -f "$SHARED_AUTH/$CRED_FILE" ]; then
        echo "  Sharing credentials to shared auth volume..."
        if cp "$CLAUDE_HOME/$CRED_FILE" "$SHARED_AUTH/$CRED_FILE" 2>/dev/null && chmod 600 "$SHARED_AUTH/$CRED_FILE" 2>/dev/null; then
            echo "  Credentials shared to volume."
        else
            echo "  Warning: Could not write to shared auth volume (permission denied). Continuing..."
        fi
        return 0
    fi

    # If both exist, use the newer one
    if [ -f "$CLAUDE_HOME/$CRED_FILE" ] && [ -f "$SHARED_AUTH/$CRED_FILE" ]; then
        local LOCAL_MOD=$(stat -c %Y "$CLAUDE_HOME/$CRED_FILE" 2>/dev/null || echo 0)
        local SHARED_MOD=$(stat -c %Y "$SHARED_AUTH/$CRED_FILE" 2>/dev/null || echo 0)

        if [ "$SHARED_MOD" -gt "$LOCAL_MOD" ]; then
            echo "  Updating credentials from shared auth (newer)..."
            if ! cp "$SHARED_AUTH/$CRED_FILE" "$CLAUDE_HOME/$CRED_FILE" 2>/dev/null || ! chmod 600 "$CLAUDE_HOME/$CRED_FILE" 2>/dev/null; then
                echo "  Warning: Could not sync from shared auth. Continuing with local credentials..."
            fi
        elif [ "$LOCAL_MOD" -gt "$SHARED_MOD" ]; then
            echo "  Updating shared auth with local credentials (newer)..."
            if ! cp "$CLAUDE_HOME/$CRED_FILE" "$SHARED_AUTH/$CRED_FILE" 2>/dev/null || ! chmod 600 "$SHARED_AUTH/$CRED_FILE" 2>/dev/null; then
                echo "  Warning: Could not sync to shared auth. Continuing with local credentials..."
            fi
        else
            echo "  Credentials already in sync."
        fi
    fi

    # No credentials anywhere
    if [ ! -f "$CLAUDE_HOME/$CRED_FILE" ] && [ ! -f "$SHARED_AUTH/$CRED_FILE" ]; then
        echo "  No credentials found. Use 'claude login' to authenticate."
    fi
}

# Call the sync function
sync_shared_credentials

# Sync GitHub CLI authentication from/to shared auth volume
sync_github_auth() {
    local GH_CONFIG="${GH_CONFIG_DIR:-$DEFAULT_HOME/.config/gh}"
    local GH_SHARED="${GH_SHARED:-$DEFAULT_HOME/.config/gh-shared}"
    local GH_HOSTS="hosts.yml"

    if [ ! -d "$GH_SHARED" ]; then
        echo "Shared GitHub auth volume not mounted at $GH_SHARED, skipping sync"
        return 0
    fi

    echo "Syncing GitHub CLI authentication..."

    # Create gh config directory if needed
    mkdir -p "$GH_CONFIG"

    # If shared auth exists and local doesn't, copy from shared
    if [ -f "$GH_SHARED/$GH_HOSTS" ] && [ ! -f "$GH_CONFIG/$GH_HOSTS" ]; then
        echo "  Copying GitHub auth from shared volume..."
        if cp "$GH_SHARED/$GH_HOSTS" "$GH_CONFIG/$GH_HOSTS" 2>/dev/null && chmod 600 "$GH_CONFIG/$GH_HOSTS" 2>/dev/null; then
            echo "  GitHub auth copied from shared volume."
        else
            echo "  Warning: Could not read from shared GitHub auth volume. Continuing..."
        fi
        return 0
    fi

    # If local auth exists but shared doesn't, copy to shared
    if [ -f "$GH_CONFIG/$GH_HOSTS" ] && [ ! -f "$GH_SHARED/$GH_HOSTS" ]; then
        echo "  Sharing GitHub auth to shared volume..."
        if cp "$GH_CONFIG/$GH_HOSTS" "$GH_SHARED/$GH_HOSTS" 2>/dev/null && chmod 600 "$GH_SHARED/$GH_HOSTS" 2>/dev/null; then
            echo "  GitHub auth shared to volume."
        else
            echo "  Warning: Could not write to shared GitHub auth volume. Continuing..."
        fi
        return 0
    fi

    # If both exist, use the newer one
    if [ -f "$GH_CONFIG/$GH_HOSTS" ] && [ -f "$GH_SHARED/$GH_HOSTS" ]; then
        local LOCAL_MOD=$(stat -c %Y "$GH_CONFIG/$GH_HOSTS" 2>/dev/null || echo 0)
        local SHARED_MOD=$(stat -c %Y "$GH_SHARED/$GH_HOSTS" 2>/dev/null || echo 0)

        if [ "$SHARED_MOD" -gt "$LOCAL_MOD" ]; then
            echo "  Updating GitHub auth from shared volume (newer)..."
            if ! cp "$GH_SHARED/$GH_HOSTS" "$GH_CONFIG/$GH_HOSTS" 2>/dev/null || ! chmod 600 "$GH_CONFIG/$GH_HOSTS" 2>/dev/null; then
                echo "  Warning: Could not sync from shared GitHub auth. Continuing with local auth..."
            fi
        elif [ "$LOCAL_MOD" -gt "$SHARED_MOD" ]; then
            echo "  Updating shared volume with local GitHub auth (newer)..."
            if ! cp "$GH_CONFIG/$GH_HOSTS" "$GH_SHARED/$GH_HOSTS" 2>/dev/null || ! chmod 600 "$GH_SHARED/$GH_HOSTS" 2>/dev/null; then
                echo "  Warning: Could not sync to shared GitHub auth. Continuing with local auth..."
            fi
        else
            echo "  GitHub auth already in sync."
        fi
    fi

    # No auth anywhere
    if [ ! -f "$GH_CONFIG/$GH_HOSTS" ] && [ ! -f "$GH_SHARED/$GH_HOSTS" ]; then
        echo "  No GitHub auth found. Use 'gh auth login' to authenticate."
    fi
}

# Call GitHub auth sync
sync_github_auth

# Sync Claude plugins and MCP servers from/to shared volume
sync_shared_plugins() {
    local SHARED_PLUGINS="${SHARED_PLUGINS:-$DEFAULT_HOME/.claude-shared-plugins}"
    local SHARED_MCP="${SHARED_MCP:-$DEFAULT_HOME/.mcp-shared}"
    local MCP_CONFIG="mcp.json"

    if [ ! -d "$SHARED_PLUGINS" ]; then
        echo "Shared plugins volume not mounted at $SHARED_PLUGINS, skipping plugin sync"
        return 0
    fi

    echo "Syncing Claude plugins and MCP servers..."

    mkdir -p "$SHARED_PLUGINS"
    mkdir -p "$SHARED_MCP"

    # Sync MCP configuration file
    if [ -f "$SHARED_PLUGINS/$MCP_CONFIG" ] && [ ! -f "$CLAUDE_HOME/$MCP_CONFIG" ]; then
        echo "  Copying MCP config from shared volume..."
        if cp "$SHARED_PLUGINS/$MCP_CONFIG" "$CLAUDE_HOME/$MCP_CONFIG" 2>/dev/null && chmod 644 "$CLAUDE_HOME/$MCP_CONFIG" 2>/dev/null; then
            echo "  MCP config copied from shared volume."
        else
            echo "  Warning: Could not read MCP config from shared volume. Continuing..."
        fi
    elif [ -f "$CLAUDE_HOME/$MCP_CONFIG" ] && [ ! -f "$SHARED_PLUGINS/$MCP_CONFIG" ]; then
        echo "  Sharing MCP config to shared volume..."
        if cp "$CLAUDE_HOME/$MCP_CONFIG" "$SHARED_PLUGINS/$MCP_CONFIG" 2>/dev/null && chmod 644 "$SHARED_PLUGINS/$MCP_CONFIG" 2>/dev/null; then
            echo "  MCP config shared to volume."
        else
            echo "  Warning: Could not write MCP config to shared volume. Continuing..."
        fi
    elif [ -f "$CLAUDE_HOME/$MCP_CONFIG" ] && [ -f "$SHARED_PLUGINS/$MCP_CONFIG" ]; then
        # Use newer config
        local LOCAL_MOD=$(stat -c %Y "$CLAUDE_HOME/$MCP_CONFIG" 2>/dev/null || echo 0)
        local SHARED_MOD=$(stat -c %Y "$SHARED_PLUGINS/$MCP_CONFIG" 2>/dev/null || echo 0)

        if [ "$SHARED_MOD" -gt "$LOCAL_MOD" ]; then
            echo "  Updating MCP config from shared volume (newer)..."
            if ! cp "$SHARED_PLUGINS/$MCP_CONFIG" "$CLAUDE_HOME/$MCP_CONFIG" 2>/dev/null || ! chmod 644 "$CLAUDE_HOME/$MCP_CONFIG" 2>/dev/null; then
                echo "  Warning: Could not sync MCP config from shared volume. Continuing..."
            fi
        elif [ "$LOCAL_MOD" -gt "$SHARED_MOD" ]; then
            echo "  Updating shared MCP config (newer)..."
            if ! cp "$CLAUDE_HOME/$MCP_CONFIG" "$SHARED_PLUGINS/$MCP_CONFIG" 2>/dev/null || ! chmod 644 "$SHARED_PLUGINS/$MCP_CONFIG" 2>/dev/null; then
                echo "  Warning: Could not sync MCP config to shared volume. Continuing..."
            fi
        else
            echo "  MCP config already in sync."
        fi
    fi

    # Sync custom skills and commands directories (bidirectional)
    for dir in skills commands agents hooks; do
        if [ -d "$SHARED_PLUGINS/$dir" ] && [ -n "$(ls -A "$SHARED_PLUGINS/$dir" 2>/dev/null)" ]; then
            echo "  Syncing $dir from shared volume..."
            mkdir -p "$CLAUDE_HOME/$dir"
            # Use cp with update flag to only copy newer files
            cp -ru "$SHARED_PLUGINS/$dir/"* "$CLAUDE_HOME/$dir/" 2>/dev/null || true
        fi

        if [ -d "$CLAUDE_HOME/$dir" ] && [ -n "$(ls -A "$CLAUDE_HOME/$dir" 2>/dev/null)" ]; then
            echo "  Syncing $dir to shared volume..."
            mkdir -p "$SHARED_PLUGINS/$dir"
            # Copy back to shared volume (bidirectional sync)
            cp -ru "$CLAUDE_HOME/$dir/"* "$SHARED_PLUGINS/$dir/" 2>/dev/null || true
        fi
    done

    echo "  Plugin sync complete."
}

# Call plugin sync
sync_shared_plugins

# Sync Git configuration from/to shared volume
# Supports two modes:
#   1. GIT_USE_PROJECT_CONFIG=true - Use env vars (GIT_USER_NAME, GIT_USER_EMAIL) instead of shared
#   2. Default - Sync with shared gitconfig volume
sync_git_config() {
    local GITCONFIG="$DEFAULT_HOME/.gitconfig"
    local SHARED_GITCONFIG="${SHARED_GITCONFIG:-$DEFAULT_HOME/.gitconfig-shared}"

    echo "Syncing git configuration..."

    # Mode 1: Project-specific config via environment variables
    # Use this for containers that need their own git identity (claudio, homebase, homebase-infra)
    if [ "${GIT_USE_PROJECT_CONFIG:-false}" = "true" ]; then
        echo "  Using project-specific git config (GIT_USE_PROJECT_CONFIG=true)"

        # Set git identity from environment variables if provided
        if [ -n "$GIT_USER_NAME" ]; then
            git config --global user.name "$GIT_USER_NAME"
            echo "  Set user.name: $GIT_USER_NAME"
        fi

        if [ -n "$GIT_USER_EMAIL" ]; then
            git config --global user.email "$GIT_USER_EMAIL"
            echo "  Set user.email: $GIT_USER_EMAIL"
        fi

        # Set signing key if provided
        if [ -n "$GIT_SIGNING_KEY" ]; then
            git config --global user.signingkey "$GIT_SIGNING_KEY"
            git config --global commit.gpgsign true
            echo "  Set signing key and enabled commit signing"
        fi

        # Warn if no identity configured
        if [ -z "$GIT_USER_NAME" ] && [ -z "$GIT_USER_EMAIL" ]; then
            local CURRENT_NAME=$(git config --global user.name 2>/dev/null || true)
            local CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || true)
            if [ -z "$CURRENT_NAME" ] || [ -z "$CURRENT_EMAIL" ]; then
                echo "  Warning: No git identity set. Set GIT_USER_NAME and GIT_USER_EMAIL env vars or use git config."
            else
                echo "  Using existing git config: $CURRENT_NAME <$CURRENT_EMAIL>"
            fi
        fi
        return 0
    fi

    # Mode 2: Shared config sync (default for general-purpose containers)
    # Check if shared gitconfig volume is mounted (file or directory exists at mount point)
    if [ ! -e "$SHARED_GITCONFIG" ] && [ ! -e "$(dirname "$SHARED_GITCONFIG")" ]; then
        echo "  Shared git config not mounted, skipping git config sync"
        return 0
    fi

    # Ensure shared gitconfig file exists (touch it if volume is mounted but empty)
    touch "$SHARED_GITCONFIG" 2>/dev/null || true

    # If shared gitconfig exists and local doesn't (or is empty), copy from shared
    if [ -s "$SHARED_GITCONFIG" ] && [ ! -s "$GITCONFIG" ]; then
        echo "  Copying git config from shared volume..."
        if cp "$SHARED_GITCONFIG" "$GITCONFIG" 2>/dev/null; then
            echo "  Git config copied from shared volume."
        else
            echo "  Warning: Could not read from shared git config. Continuing..."
        fi
        return 0
    fi

    # If local gitconfig exists but shared doesn't (or is empty), copy to shared
    if [ -s "$GITCONFIG" ] && [ ! -s "$SHARED_GITCONFIG" ]; then
        echo "  Sharing git config to shared volume..."
        if cp "$GITCONFIG" "$SHARED_GITCONFIG" 2>/dev/null; then
            echo "  Git config shared to volume."
        else
            echo "  Warning: Could not write to shared git config. Continuing..."
        fi
        return 0
    fi

    # If both exist with content, use the newer one
    if [ -s "$GITCONFIG" ] && [ -s "$SHARED_GITCONFIG" ]; then
        local LOCAL_MOD=$(stat -c %Y "$GITCONFIG" 2>/dev/null || echo 0)
        local SHARED_MOD=$(stat -c %Y "$SHARED_GITCONFIG" 2>/dev/null || echo 0)

        if [ "$SHARED_MOD" -gt "$LOCAL_MOD" ]; then
            echo "  Updating git config from shared volume (newer)..."
            cp "$SHARED_GITCONFIG" "$GITCONFIG" 2>/dev/null || echo "  Warning: Could not sync git config."
        elif [ "$LOCAL_MOD" -gt "$SHARED_MOD" ]; then
            echo "  Updating shared git config (newer)..."
            cp "$GITCONFIG" "$SHARED_GITCONFIG" 2>/dev/null || echo "  Warning: Could not sync git config."
        else
            echo "  Git config already in sync."
        fi
        return 0
    fi

    # No config anywhere
    if [ ! -s "$GITCONFIG" ] && [ ! -s "$SHARED_GITCONFIG" ]; then
        echo "  No git config found. Use 'git config --global user.name/email' to set."
    fi
}

# Call git config sync
sync_git_config

# Setup SSH and GPG if mounted
setup_ssh_gpg() {
    # SSH agent forwarding setup
    if [ -n "$SSH_AUTH_SOCK" ]; then
        echo "SSH agent forwarding enabled: $SSH_AUTH_SOCK"
    fi

    # SSH keys symlink (if mounted at ~/.ssh-host)
    if [ -d "$DEFAULT_HOME/.ssh-host" ] && [ ! -L "$DEFAULT_HOME/.ssh" ]; then
        echo "Setting up SSH keys from host..."
        # Create symlink or copy based on presence
        if [ ! -e "$DEFAULT_HOME/.ssh" ]; then
            ln -s "$DEFAULT_HOME/.ssh-host" "$DEFAULT_HOME/.ssh"
            echo "  SSH keys linked from ~/.ssh-host"
        fi
    fi

    # GPG setup (if mounted at ~/.gnupg-host)
    if [ -d "$DEFAULT_HOME/.gnupg-host" ]; then
        echo "Setting up GPG from host..."
        mkdir -p "$DEFAULT_HOME/.gnupg"
        # Copy GPG config but not the full keyring for security
        if [ -f "$DEFAULT_HOME/.gnupg-host/gpg.conf" ]; then
            cp "$DEFAULT_HOME/.gnupg-host/gpg.conf" "$DEFAULT_HOME/.gnupg/" 2>/dev/null || true
        fi
        # Set GPG_TTY for signing
        if ! grep -q "GPG_TTY" "$DEFAULT_HOME/.bashrc" 2>/dev/null; then
            echo "" >> "$DEFAULT_HOME/.bashrc"
            echo "# GPG TTY for commit signing" >> "$DEFAULT_HOME/.bashrc"
            echo "export GPG_TTY=\$(tty)" >> "$DEFAULT_HOME/.bashrc"
        fi
        echo "  GPG configuration copied. Note: Use gpg-agent forwarding for keys."
    fi
}

# Setup SSH and GPG
setup_ssh_gpg

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
