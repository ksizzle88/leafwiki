#!/bin/bash
# Create all external volumes required by Claudio compose files.
# Scans docker-compose.yml and any project compose files for volumes
# marked "external: true" and creates them if they don't exist.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Claudio Volume Setup ==="
echo ""

# Find compose files: repo root + any passed as arguments
compose_files=()
for f in "$REPO_ROOT"/docker-compose.yml "$REPO_ROOT"/*/.devcontainer/docker-compose.yml; do
    [ -f "$f" ] && compose_files+=("$f")
done

# Also accept extra compose file paths as arguments
for f in "$@"; do
    [ -f "$f" ] && compose_files+=("$f")
done

if [ ${#compose_files[@]} -eq 0 ]; then
    echo "No docker-compose files found."
    exit 1
fi

# Parse external volume names from all compose files
# Looks for "name: <volume-name>" lines under "external: true" blocks
volumes=()
for f in "${compose_files[@]}"; do
    # Extract volume names where external: true is set
    # Pattern: volume block has "external: true" followed by "name: X"
    # Simple: find lines with "name:" that follow "external: true" in volume blocks
    # grep -A1 finds "external: true" + next line, then extract the name value
    while IFS= read -r name; do
        name=$(echo "$name" | sed 's/.*name: *//' | sed 's/ *$//')
        [ -n "$name" ] && volumes+=("$name")
    done < <(grep -A1 'external:.*true' "$f" | grep 'name:' || true)
done

# Deduplicate
volumes=($(printf '%s\n' "${volumes[@]}" | sort -u))

if [ ${#volumes[@]} -eq 0 ]; then
    echo "No external volumes found in compose files."
    exit 0
fi

# Create each volume if it doesn't exist
created=0
existed=0
for vol in "${volumes[@]}"; do
    if docker volume inspect "$vol" >/dev/null 2>&1; then
        echo "  exists:  $vol"
        existed=$((existed + 1))
    else
        docker volume create "$vol" >/dev/null
        echo "  created: $vol"
        created=$((created + 1))

        # Initialize claudio-shared with directory structure on first create
        if [ "$vol" = "claudio-shared" ]; then
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
            echo "           (initialized directory structure)"
        fi
    fi
done

echo ""
echo "Done: $created created, $existed already existed."
echo ""
echo "Compose files scanned:"
for f in "${compose_files[@]}"; do
    echo "  - ${f#$REPO_ROOT/}"
done