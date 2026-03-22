#!/bin/bash
# Build the mpulse devcontainer image
#
# Usage:
#   ./build-mpulse.sh                    # Builds mpulse-claudio:<current-branch> using claudio-base:<current-branch>
#   ./build-mpulse.sh --tags local       # Builds mpulse-claudio:local using claudio-base:local
#   ./build-mpulse.sh --base-only        # Build base image only, skip mpulse
#   ./build-mpulse.sh --skip-base        # Skip base image, build mpulse only
#
# By default, builds both base and mpulse images with the same tag.
# Loads .env from mpulse/.devcontainer/ for CLAUDIO_IMAGE/CLAUDIO_TAG overrides.

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MPULSE_DIR="$SCRIPT_DIR/mpulse/.devcontainer"

# Parse arguments
TAG_ARRAY=()
SKIP_BASE=false
BASE_ONLY=false
PASSTHROUGH_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --tags)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                TAG_ARRAY+=("$1")
                shift
            done
            ;;
        --skip-base)
            SKIP_BASE=true
            shift
            ;;
        --base-only)
            BASE_ONLY=true
            shift
            ;;
        --push|--registry)
            PASSTHROUGH_ARGS+=("$1")
            if [[ "$1" == "--registry" ]]; then
                PASSTHROUGH_ARGS+=("$2")
                shift
            fi
            shift
            ;;
        *)
            echo -e "${RED}Unknown argument: $1${NC}"
            echo "Usage: $0 [--tags TAG1 [TAG2 ...]] [--skip-base] [--base-only] [--push]"
            exit 1
            ;;
    esac
done

# Default to current branch name
if [ ${#TAG_ARRAY[@]} -eq 0 ]; then
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | sed 's/[^a-zA-Z0-9._-]/-/g')
    TAG_ARRAY=("${CURRENT_BRANCH:-dev}")
fi

PRIMARY_TAG="${TAG_ARRAY[0]}"

# Step 1: Build base image
if [ "$SKIP_BASE" = false ]; then
    echo -e "${GREEN}=== Step 1: Building claudio-base:${PRIMARY_TAG} ===${NC}"
    echo ""
    "$SCRIPT_DIR/build-base.sh" --tags "${TAG_ARRAY[@]}" "${PASSTHROUGH_ARGS[@]}"
    echo ""
fi

if [ "$BASE_ONLY" = true ]; then
    echo -e "${GREEN}Base-only build complete.${NC}"
    exit 0
fi

# Step 2: Build mpulse image
echo -e "${GREEN}=== Step 2: Building mpulse-claudio:${PRIMARY_TAG} ===${NC}"
echo ""

if [ ! -f "$MPULSE_DIR/Dockerfile" ]; then
    echo -e "${RED}Error: $MPULSE_DIR/Dockerfile not found${NC}"
    exit 1
fi

# Build tags
BUILD_TAGS=()
for tag in "${TAG_ARRAY[@]}"; do
    BUILD_TAGS+=("-t" "mpulse-claudio:$tag")
done

docker build \
    -f "$MPULSE_DIR/Dockerfile" \
    "${BUILD_TAGS[@]}" \
    --build-arg CLAUDIO_IMAGE=claudio-base \
    --build-arg CLAUDIO_TAG="$PRIMARY_TAG" \
    "$MPULSE_DIR"

echo ""
echo -e "${GREEN}Build complete!${NC}"
echo ""
echo "Image tags:"
for tag in "${TAG_ARRAY[@]}"; do
    echo "  - claudio-base:$tag"
    echo "  - mpulse-claudio:$tag"
done
echo ""
echo "Verify with:"
echo "  docker run --rm mpulse-claudio:$PRIMARY_TAG claude --version"
echo "  docker run --rm mpulse-claudio:$PRIMARY_TAG dbt --version"
echo "  docker run --rm mpulse-claudio:$PRIMARY_TAG snow --version"
echo "  docker run --rm mpulse-claudio:$PRIMARY_TAG ruff --version"
