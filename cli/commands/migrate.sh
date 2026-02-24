#!/bin/bash
# migrate.sh - Migrate from Claudio v1 to v2 layout
#
# Usage: claudio migrate

set -e

echo "Claudio: Migrating to v2 layout..."
echo ""

OLD_CLAUDE="$HOME/.claude"
NEW_CLAUDIO="$HOME/.claudio"

# Check if already migrated
if [ -L "$OLD_CLAUDE" ] && [ -d "$NEW_CLAUDIO/claude" ]; then
    echo "Already migrated to v2 layout."
    echo "  Config: $NEW_CLAUDIO/claude"
    echo "  Symlink: $OLD_CLAUDE -> $(readlink -f "$OLD_CLAUDE")"
    exit 0
fi

# Check if old layout exists
if [ ! -d "$OLD_CLAUDE" ] || [ -L "$OLD_CLAUDE" ]; then
    echo "No v1 layout found (or already migrated)."
    echo "Nothing to migrate."
    exit 0
fi

echo "Found v1 layout at: $OLD_CLAUDE"
echo ""

# Step 1: Create new structure
echo "Step 1: Creating new directory structure..."
mkdir -p "$NEW_CLAUDIO/claude"
mkdir -p "$NEW_CLAUDIO/bash-history"
mkdir -p "$NEW_CLAUDIO/session"

# Step 2: Copy Claude config
echo "Step 2: Copying Claude configuration..."
if [ -d "$OLD_CLAUDE" ]; then
    cp -r "$OLD_CLAUDE/"* "$NEW_CLAUDIO/claude/" 2>/dev/null || true
    echo "  Copied config files"
fi

# Step 3: Backup old directory
echo "Step 3: Backing up old layout..."
BACKUP_DIR="$OLD_CLAUDE.bak.$(date +%Y%m%d_%H%M%S)"
mv "$OLD_CLAUDE" "$BACKUP_DIR"
echo "  Backed up to: $BACKUP_DIR"

# Step 4: Create symlink
echo "Step 4: Creating symlink..."
ln -sf "$NEW_CLAUDIO/claude" "$OLD_CLAUDE"
echo "  $OLD_CLAUDE -> $NEW_CLAUDIO/claude"

# Step 5: Move bash history if exists
echo "Step 5: Migrating shell history..."
if [ -f "/commandhistory/.bash_history" ]; then
    cp /commandhistory/.bash_history "$NEW_CLAUDIO/bash-history/" 2>/dev/null || true
    echo "  Copied bash history"
fi
if [ -f "/commandhistory/.zsh_history" ]; then
    cp /commandhistory/.zsh_history "$NEW_CLAUDIO/bash-history/" 2>/dev/null || true
    echo "  Copied zsh history"
fi

# Step 6: Mark as initialized
touch "$NEW_CLAUDIO/.initialized"

echo ""
echo "Migration complete!"
echo ""
echo "New layout:"
echo "  Config:  $NEW_CLAUDIO/claude"
echo "  History: $NEW_CLAUDIO/bash-history"
echo "  Symlink: $OLD_CLAUDE -> $NEW_CLAUDIO/claude"
echo ""
echo "Backup of old layout: $BACKUP_DIR"
echo ""
echo "You can delete the backup after verifying everything works:"
echo "  rm -rf $BACKUP_DIR"
