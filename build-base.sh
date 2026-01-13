#!/bin/bash
# Build the claudio-base Docker image
#
# Usage:
#   ./build-base.sh                    # Builds claudio-base:latest
#   ./build-base.sh --tags dev         # Builds claudio-base:dev
#   ./build-base.sh --tags latest v1.0.0  # Builds with primary tag 'latest' and additional tag 'v1.0.0'
#
# Loads git configuration from .env file (if present):
#   GIT_USER_EMAIL=your.email@example.com
#   GIT_USER_NAME=Your Name

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Parse arguments
TAG_ARRAY=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --tags)
            shift
            # Collect all remaining arguments as tags
            while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                TAG_ARRAY+=("$1")
                shift
            done
            ;;
        *)
            echo -e "${RED}Unknown argument: $1${NC}"
            echo "Usage: $0 [--tags TAG1 [TAG2 ...]]"
            exit 1
            ;;
    esac
done

# Default to 'latest' if no tags specified
if [ ${#TAG_ARRAY[@]} -eq 0 ]; then
    TAG_ARRAY=("latest")
fi

echo "Building claudio-base with tags: ${TAG_ARRAY[@]}..."

# Load .env if it exists
if [ -f .env ]; then
    echo -e "${GREEN}Found .env file, loading git configuration...${NC}"
    export $(grep -v '^#' .env | grep -v '^$' | xargs)
else
    echo -e "${YELLOW}No .env file found. Git config will not be baked into image.${NC}"
    echo -e "${YELLOW}Create .env from .env.example if you want git config in the image.${NC}"
fi

# Show what we're building with
if [ -n "$GIT_USER_EMAIL" ]; then
    echo "  GIT_USER_EMAIL: $GIT_USER_EMAIL"
fi
if [ -n "$GIT_USER_NAME" ]; then
    echo "  GIT_USER_NAME: $GIT_USER_NAME"
fi

# Build the image with the first tag
PRIMARY_TAG="${TAG_ARRAY[0]}"
docker build \
    -f Dockerfile.base \
    -t "claudio-base:$PRIMARY_TAG" \
    --build-arg NODE_VERSION=20 \
    --build-arg GIT_USER_EMAIL="${GIT_USER_EMAIL:-}" \
    --build-arg GIT_USER_NAME="${GIT_USER_NAME:-}" \
    .

# Tag with additional tags if specified
if [ ${#TAG_ARRAY[@]} -gt 1 ]; then
    echo ""
    echo "Creating additional tags..."
    for tag in "${TAG_ARRAY[@]:1}"; do
        echo "  Tagging as claudio-base:$tag"
        docker tag "claudio-base:$PRIMARY_TAG" "claudio-base:$tag"
    done
fi

echo ""
echo -e "${GREEN}Build complete!${NC}"
echo ""
echo "Image tags:"
for tag in "${TAG_ARRAY[@]}"; do
    echo "  - claudio-base:$tag"
done
echo ""
echo "Verify with:"
echo "  docker run --rm claudio-base:$PRIMARY_TAG claude --version"
echo "  docker run --rm claudio-base:$PRIMARY_TAG python --version"
echo "  docker run --rm claudio-base:$PRIMARY_TAG node --version"
echo "  docker run --rm claudio-base:$PRIMARY_TAG git config --global --list"
