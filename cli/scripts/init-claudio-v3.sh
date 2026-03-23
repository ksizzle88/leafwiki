#!/bin/bash
# init-claudio-v3.sh — Symlink-based Claude Code initialization
# Assembles ~/.claude from shared + session volumes via symlinks.
# No copying, no timestamp sync, no bidirectional merge.

set -e

SHARED="${CLAUDIO_SHARED:-$HOME/.claudio-shared}"
SESSIONS="${CLAUDIO_SESSIONS:-$HOME/.claudio-sessions}"
CLAUDE_DIR="$HOME/.claude"
DEFAULTS="/opt/claudio-defaults/.claude"
PROJECT="/workspace/.claude"

echo "Claudio v3: Initializing..."

# --- Phase 1: Seed shared volume (first-ever run across any container) ---
if [ ! -f "$SHARED/.initialized" ]; then
    echo "First-ever run — seeding shared volume..."

    # Ensure directory structure
    mkdir -p "$SHARED/auth/gh"
    mkdir -p "$SHARED/config"
    mkdir -p "$SHARED/plugins"/{skills,commands,agents,hooks,reference,bin}
    mkdir -p "$SHARED/caches"/{npm,pip}

    # Copy config files from image defaults
    if [ -d "$DEFAULTS" ]; then
        for f in settings.json mcp.json CLAUDE.md statusline.sh statusline-command.sh fetch-usage.sh; do
            [ -f "$DEFAULTS/$f" ] && cp "$DEFAULTS/$f" "$SHARED/config/"
        done
    fi

    # Copy plugin directories from image defaults (only if project doesn't provide them)
    if [ -d "$DEFAULTS" ]; then
        for d in skills commands agents hooks reference; do
            if [ ! -d "$PROJECT/$d" ] && [ -d "$DEFAULTS/$d" ]; then
                cp -r "$DEFAULTS/$d/"* "$SHARED/plugins/$d/" 2>/dev/null || true
            fi
        done
    fi

    # Overlay project-specific plugins
    if [ -d "$PROJECT" ]; then
        for d in skills commands agents hooks reference; do
            [ -d "$PROJECT/$d" ] && cp -r "$PROJECT/$d/"* "$SHARED/plugins/$d/" 2>/dev/null || true
        done
    fi

    touch "$SHARED/.initialized"
    echo "Shared volume seeded."
fi

# --- Phase 2: Ensure session directories exist ---
mkdir -p "$SESSIONS"/{projects,teams,tasks,file-history,session-env,shell-snapshots,ide,backups}
mkdir -p "$SESSIONS/plugins"/{marketplaces,cache,data}
[ -f "$SESSIONS/.claude.json" ] || echo '{}' > "$SESSIONS/.claude.json"
[ -f "$SESSIONS/plugins/installed_plugins.json" ] || echo '{}' > "$SESSIONS/plugins/installed_plugins.json"
[ -f "$SESSIONS/plugins/blocklist.json" ] || echo '[]' > "$SESSIONS/plugins/blocklist.json"
[ -f "$SESSIONS/plugins/known_marketplaces.json" ] || echo '[]' > "$SESSIONS/plugins/known_marketplaces.json"

# --- Phase 3: Assemble ~/.claude via symlinks ---
# Remove old ~/.claude (symlink or directory) and rebuild fresh
if [ -L "$CLAUDE_DIR" ]; then
    rm "$CLAUDE_DIR"
elif [ -d "$CLAUDE_DIR" ]; then
    # Back up existing directory (first migration)
    mv "$CLAUDE_DIR" "$CLAUDE_DIR.bak.$(date +%s)" 2>/dev/null || true
fi
mkdir -p "$CLAUDE_DIR"

# Auth — single source of truth
ln -sf "$SHARED/auth/.credentials.json"           "$CLAUDE_DIR/.credentials.json"

# Config files
for f in settings.json settings.local.json mcp.json CLAUDE.md statusline.sh statusline-command.sh fetch-usage.sh; do
    [ -f "$SHARED/config/$f" ] && ln -sf "$SHARED/config/$f" "$CLAUDE_DIR/$f"
done

# Plugin directories
for d in skills commands agents hooks reference bin; do
    [ -d "$SHARED/plugins/$d" ] && ln -sf "$SHARED/plugins/$d" "$CLAUDE_DIR/$d"
done

# Session directories
for d in projects teams tasks file-history session-env shell-snapshots ide backups; do
    ln -sf "$SESSIONS/$d" "$CLAUDE_DIR/$d"
done

# Session files
ln -sf "$SESSIONS/.claude.json"                    "$CLAUDE_DIR/.claude.json"

# Plugin marketplace state (per-container)
ln -sf "$SESSIONS/plugins"                         "$CLAUDE_DIR/plugins"

# --- Phase 4: GitHub CLI auth ---
mkdir -p "$HOME/.config/gh"
if [ -f "$SHARED/auth/gh/hosts.yml" ]; then
    ln -sf "$SHARED/auth/gh/hosts.yml" "$HOME/.config/gh/hosts.yml"
fi

# --- Phase 5: Cache symlinks ---
if [ -d "$SHARED/caches/npm" ]; then
    rm -rf "$HOME/.npm" 2>/dev/null || true
    ln -sf "$SHARED/caches/npm" "$HOME/.npm"
fi
if [ -d "$SHARED/caches/pip" ]; then
    mkdir -p "$HOME/.cache"
    rm -rf "$HOME/.cache/pip" 2>/dev/null || true
    ln -sf "$SHARED/caches/pip" "$HOME/.cache/pip"
fi

# --- Phase 6: Skill script auto-discovery ---
for skill_dir in "$SHARED/plugins/skills"/*/scripts; do
    [ -d "$skill_dir" ] || continue
    for script in "$skill_dir"/*; do
        [ -f "$script" ] && [ -x "$script" ] && ln -sf "$script" "$SHARED/plugins/bin/"
    done
done

# --- Phase 7: Shell environment ---
export CLAUDE_CONFIG_DIR="$HOME/.claude"
for profile in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$profile" ] && ! grep -q "CLAUDE_CONFIG_DIR" "$profile" 2>/dev/null; then
        echo 'export CLAUDE_CONFIG_DIR="$HOME/.claude"' >> "$profile"
    fi
done

# Add bin to PATH
for profile in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$profile" ] && ! grep -q '\.claude/bin' "$profile" 2>/dev/null; then
        echo 'export PATH="$HOME/.claude/bin:$PATH"' >> "$profile"
    fi
done

echo ""
echo "Claudio v3 initialized (symlink mode)"
echo "  Config:   $CLAUDE_DIR"
echo "  Shared:   $SHARED"
echo "  Sessions: $SESSIONS"

if command -v claude &> /dev/null; then
    claude --version 2>/dev/null || true
fi
