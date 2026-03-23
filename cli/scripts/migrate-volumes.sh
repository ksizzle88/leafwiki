#!/bin/bash
# migrate-volumes.sh — Migrate old Docker volumes to new host directory layout
# Run once from the host (or inside a container with docker access).
#
# Usage: ./migrate-volumes.sh [CLAUDIO_ROOT]
#   Default CLAUDIO_ROOT: ~/.claudio

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CLAUDIO_ROOT="${1:-${CLAUDIO_ROOT:-$HOME/.claudio}}"

echo "Migrating old Docker volumes to $CLAUDIO_ROOT"
echo ""

# Ensure target directories exist
./cli/scripts/setup-host-dirs.sh 2>/dev/null || bash "$(dirname "$0")/setup-host-dirs.sh" 2>/dev/null || {
    echo "Creating directories manually..."
    mkdir -p "$CLAUDIO_ROOT/shared/auth/gh"
    mkdir -p "$CLAUDIO_ROOT/shared/config"
    mkdir -p "$CLAUDIO_ROOT/shared/plugins"/{skills,commands,agents,hooks,reference,bin}
    mkdir -p "$CLAUDIO_ROOT/shared/caches"/{npm,pip}
    mkdir -p "$CLAUDIO_ROOT/sessions/claudio"
    mkdir -p "$CLAUDIO_ROOT/sessions/mpulse"
}

# Helper: extract files from a Docker volume to a host path
extract_volume() {
    local vol="$1"
    local dest="$2"
    local desc="$3"

    if docker volume inspect "$vol" &>/dev/null; then
        echo -e "  ${GREEN}Extracting${NC} $vol → $dest ($desc)"
        docker run --rm -v "$vol":/source -v "$dest":/dest alpine \
            sh -c 'cp -a /source/. /dest/' 2>/dev/null || {
            echo -e "  ${YELLOW}Warning${NC}: Could not extract $vol"
            return 1
        }
    else
        echo -e "  ${YELLOW}Skipping${NC} $vol (not found)"
        return 1
    fi
}

# --- Migrate shared volume ---
echo "=== Shared Volume ==="

if docker volume inspect claudio-shared &>/dev/null; then
    # Extract to temp, then move pieces to new layout
    TMPDIR=$(mktemp -d)
    extract_volume "claudio-shared" "$TMPDIR" "shared auth/plugins/caches"

    # Auth
    [ -f "$TMPDIR/auth/.credentials.json" ] && cp "$TMPDIR/auth/.credentials.json" "$CLAUDIO_ROOT/shared/auth/"
    [ -d "$TMPDIR/auth/gh" ] && cp -r "$TMPDIR/auth/gh/"* "$CLAUDIO_ROOT/shared/auth/gh/" 2>/dev/null || true

    # Plugins
    for d in skills commands agents hooks; do
        [ -d "$TMPDIR/plugins/$d" ] && cp -r "$TMPDIR/plugins/$d/"* "$CLAUDIO_ROOT/shared/plugins/$d/" 2>/dev/null || true
    done

    # Caches
    [ -d "$TMPDIR/caches/npm" ] && cp -r "$TMPDIR/caches/npm/"* "$CLAUDIO_ROOT/shared/caches/npm/" 2>/dev/null || true
    [ -d "$TMPDIR/caches/pip" ] && cp -r "$TMPDIR/caches/pip/"* "$CLAUDIO_ROOT/shared/caches/pip/" 2>/dev/null || true

    rm -rf "$TMPDIR"
    echo -e "  ${GREEN}Done${NC}"
else
    echo -e "  ${YELLOW}No claudio-shared volume found${NC}"
fi

# --- Migrate Claudio container session data ---
echo ""
echo "=== Claudio Container Sessions ==="

# Find the best source: claudio-dev has newest credentials
for vol in claudio-dev claudio_claudio-1de0htfpkbvho59i197b067huiq7de2c27u17crd6jh9du1nd0d8; do
    if docker volume inspect "$vol" &>/dev/null; then
        TMPDIR=$(mktemp -d)
        extract_volume "$vol" "$TMPDIR" "claudio sessions"

        CLAUDE="$TMPDIR/claude"
        if [ -d "$CLAUDE" ]; then
            # Session data → claudio sessions dir
            for d in projects teams tasks file-history session-env shell-snapshots; do
                [ -d "$CLAUDE/$d" ] && cp -r "$CLAUDE/$d/"* "$CLAUDIO_ROOT/sessions/claudio/$d/" 2>/dev/null || true
            done

            # Config files → shared (if not already there)
            for f in settings.json settings.local.json mcp.json CLAUDE.md statusline.sh statusline-command.sh fetch-usage.sh; do
                if [ -f "$CLAUDE/$f" ] && [ ! -f "$CLAUDIO_ROOT/shared/config/$f" ]; then
                    cp "$CLAUDE/$f" "$CLAUDIO_ROOT/shared/config/"
                fi
            done

            # Credentials → shared (use newest)
            if [ -f "$CLAUDE/.credentials.json" ]; then
                if [ ! -f "$CLAUDIO_ROOT/shared/auth/.credentials.json" ] || \
                   [ "$CLAUDE/.credentials.json" -nt "$CLAUDIO_ROOT/shared/auth/.credentials.json" ]; then
                    cp "$CLAUDE/.credentials.json" "$CLAUDIO_ROOT/shared/auth/"
                    echo -e "  ${GREEN}Updated shared credentials from $vol${NC}"
                fi
            fi

            # Plugin marketplace state → sessions
            if [ -d "$CLAUDE/plugins" ]; then
                mkdir -p "$CLAUDIO_ROOT/sessions/claudio/plugins"
                cp -r "$CLAUDE/plugins/"* "$CLAUDIO_ROOT/sessions/claudio/plugins/" 2>/dev/null || true
            fi

            # .claude.json → sessions
            [ -f "$CLAUDE/.claude.json" ] && cp "$CLAUDE/.claude.json" "$CLAUDIO_ROOT/sessions/claudio/"

            # Reference docs → shared plugins
            if [ -d "$CLAUDE/reference" ]; then
                cp -r "$CLAUDE/reference/"* "$CLAUDIO_ROOT/shared/plugins/reference/" 2>/dev/null || true
            fi

            # Bin scripts → shared plugins
            if [ -d "$CLAUDE/bin" ]; then
                cp -r "$CLAUDE/bin/"* "$CLAUDIO_ROOT/shared/plugins/bin/" 2>/dev/null || true
            fi
        fi

        rm -rf "$TMPDIR"
        echo -e "  ${GREEN}Done${NC} ($vol)"
        break  # Use first found
    fi
done

# --- Migrate mpulse container session data ---
echo ""
echo "=== mpulse Container Sessions ==="

if docker volume inspect mpulse-claudio &>/dev/null; then
    TMPDIR=$(mktemp -d)
    extract_volume "mpulse-claudio" "$TMPDIR" "mpulse sessions"

    CLAUDE="$TMPDIR/claude"
    if [ -d "$CLAUDE" ]; then
        # Session data → mpulse sessions dir
        for d in projects teams tasks file-history session-env shell-snapshots; do
            mkdir -p "$CLAUDIO_ROOT/sessions/mpulse/$d"
            [ -d "$CLAUDE/$d" ] && cp -r "$CLAUDE/$d/"* "$CLAUDIO_ROOT/sessions/mpulse/$d/" 2>/dev/null || true
        done

        # Plugin marketplace state → sessions
        if [ -d "$CLAUDE/plugins" ]; then
            mkdir -p "$CLAUDIO_ROOT/sessions/mpulse/plugins"
            cp -r "$CLAUDE/plugins/"* "$CLAUDIO_ROOT/sessions/mpulse/plugins/" 2>/dev/null || true
        fi

        # .claude.json → sessions
        [ -f "$CLAUDE/.claude.json" ] && cp "$CLAUDE/.claude.json" "$CLAUDIO_ROOT/sessions/mpulse/"

        # Credentials → shared (if newer)
        if [ -f "$CLAUDE/.credentials.json" ]; then
            if [ ! -f "$CLAUDIO_ROOT/shared/auth/.credentials.json" ] || \
               [ "$CLAUDE/.credentials.json" -nt "$CLAUDIO_ROOT/shared/auth/.credentials.json" ]; then
                cp "$CLAUDE/.credentials.json" "$CLAUDIO_ROOT/shared/auth/"
                echo -e "  ${GREEN}Updated shared credentials from mpulse-claudio${NC}"
            fi
        fi
    fi

    rm -rf "$TMPDIR"
    echo -e "  ${GREEN}Done${NC}"
else
    echo -e "  ${YELLOW}No mpulse-claudio volume found${NC}"
fi

# --- Summary ---
echo ""
echo "=== Migration Complete ==="
echo ""
echo "New layout:"
find "$CLAUDIO_ROOT" -maxdepth 3 -type f | head -30
echo "..."
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "  1. Update docker-compose.yml files to use bind mounts"
echo "  2. Rebuild containers"
echo "  3. Verify with: ls -la ~/.claude/  (should show symlinks)"
echo "  4. Once verified, old volumes can be removed with: docker volume rm <name>"
