#!/bin/bash
# setup-host-dirs.sh — Create ~/.claudio host directory structure
# Run once on the host before first container build.
# Replaces create-volumes.sh — no more Docker named volumes needed.

set -e

CLAUDIO_ROOT="${CLAUDIO_ROOT:-$HOME/.claudio}"

echo "Setting up Claudio host directories at $CLAUDIO_ROOT..."

# Shared (cross-container)
mkdir -p "$CLAUDIO_ROOT/shared/auth/gh"
mkdir -p "$CLAUDIO_ROOT/shared/config"
mkdir -p "$CLAUDIO_ROOT/shared/plugins/skills"
mkdir -p "$CLAUDIO_ROOT/shared/plugins/commands"
mkdir -p "$CLAUDIO_ROOT/shared/plugins/agents"
mkdir -p "$CLAUDIO_ROOT/shared/plugins/hooks"
mkdir -p "$CLAUDIO_ROOT/shared/plugins/reference"
mkdir -p "$CLAUDIO_ROOT/shared/plugins/bin"
mkdir -p "$CLAUDIO_ROOT/shared/caches/npm"
mkdir -p "$CLAUDIO_ROOT/shared/caches/pip"

# Per-container sessions
mkdir -p "$CLAUDIO_ROOT/sessions/claudio"
mkdir -p "$CLAUDIO_ROOT/sessions/mpulse"

echo ""
echo "Created:"
echo "  $CLAUDIO_ROOT/shared/      — auth, config, plugins, caches (shared across containers)"
echo "  $CLAUDIO_ROOT/sessions/claudio/ — Claudio container sessions"
echo "  $CLAUDIO_ROOT/sessions/mpulse/  — mpulse container sessions"
echo ""
echo "Done. You can now run docker compose up."
