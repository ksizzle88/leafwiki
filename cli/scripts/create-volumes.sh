#!/bin/bash
# Create all required shared volumes for Claudio v2
#
# v2 uses a single consolidated shared volume instead of multiple separate ones

set -e

echo "=== Claudio v2 Shared Volume Setup ==="
echo ""

# New consolidated volume
if docker volume inspect "claudio-shared" >/dev/null 2>&1; then
    echo "✓ claudio-shared (exists)"
else
    docker volume create "claudio-shared"
    echo "✓ claudio-shared (created)"

    # Initialize directory structure
    echo "  Initializing directory structure..."
    docker run --rm -v claudio-shared:/shared alpine sh -c "
        mkdir -p /shared/auth
        mkdir -p /shared/plugins/skills
        mkdir -p /shared/plugins/commands
        mkdir -p /shared/plugins/mcp
        mkdir -p /shared/caches/npm
        mkdir -p /shared/caches/pip
        mkdir -p /shared/config
        chown -R 1000:1000 /shared
    "
    echo "  ✓ Directory structure created"
fi

# Shell history (still separate for compatibility)
if docker volume inspect "shell-history" >/dev/null 2>&1; then
    echo "✓ shell-history (exists)"
else
    docker volume create "shell-history"
    echo "✓ shell-history (created)"
fi

echo ""
echo "Claudio v2 volumes ready!"
echo ""

# Check for old v1 volumes and offer migration
OLD_VOLUMES=(
    "claudio-shared-auth"
    "claudio-gh-auth"
    "claudio-shared-plugins"
    "claudio-shared-mcp"
    "claudio-shared-gitconfig"
)

has_old_volumes=false
for vol in "${OLD_VOLUMES[@]}"; do
    if docker volume inspect "$vol" >/dev/null 2>&1; then
        has_old_volumes=true
        break
    fi
done

if [ "$has_old_volumes" = true ]; then
    echo "Note: Old v1 volumes detected."
    echo "To migrate data from old volumes, run:"
    echo ""
    echo "  docker run --rm \\"
    echo "    -v claudio-shared-auth:/old/auth:ro \\"
    echo "    -v claudio-shared-plugins:/old/plugins:ro \\"
    echo "    -v claudio-shared-mcp:/old/mcp:ro \\"
    echo "    -v claudio-shared:/new \\"
    echo "    alpine sh -c '"
    echo "      cp -r /old/auth/* /new/auth/ 2>/dev/null || true"
    echo "      cp -r /old/plugins/* /new/plugins/ 2>/dev/null || true"
    echo "      cp -r /old/mcp/* /new/plugins/mcp/ 2>/dev/null || true"
    echo "    '"
    echo ""
    echo "After verifying migration, remove old volumes:"
    echo "  docker volume rm claudio-shared-auth claudio-gh-auth \\"
    echo "    claudio-shared-plugins claudio-shared-mcp claudio-shared-gitconfig"
    echo ""
fi

echo "Next steps:"
echo "  1. Build Claudio base image: ./build-base.sh"
echo "  2. Rebuild container: Dev Containers > Rebuild Container"
echo "  3. Run verification: claudio verify"
