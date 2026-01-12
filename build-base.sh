#!/bin/bash
# Build the claudio-base:latest Docker image
#
# Usage:
#   ./build-base.sh
#
# Loads git configuration from .env file (if present):
#   GIT_USER_EMAIL=your.email@example.com
#   GIT_USER_NAME=Your Name

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "Building claudio-base:latest..."

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

# Build the image
docker build \
    -f Dockerfile.base \
    -t claudio-base:latest \
    --build-arg NODE_VERSION=20 \
    --build-arg GIT_USER_EMAIL="${GIT_USER_EMAIL:-}" \
    --build-arg GIT_USER_NAME="${GIT_USER_NAME:-}" \
    .

echo ""
echo -e "${GREEN}Build complete!${NC}"
echo ""
echo "Image: claudio-base:latest"
echo ""
echo "Verify with:"
echo "  docker run --rm claudio-base:latest claude --version"
echo "  docker run --rm claudio-base:latest python --version"
echo "  docker run --rm claudio-base:latest node --version"
echo "  docker run --rm claudio-base:latest git config --global --list"
