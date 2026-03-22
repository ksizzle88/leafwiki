#!/bin/bash
# Build the claudio-base Docker image
#
# Usage:
#   ./build-base.sh                                    # Builds claudio-base:<current-branch>
#   ./build-base.sh --tags latest                      # Builds claudio-base:latest
#   ./build-base.sh --tags latest v1.0.0               # Builds with multiple tags
#   ./build-base.sh --push                             # Builds and pushes to ghcr.io/ksizzle88/claudio
#   ./build-base.sh --tags latest v1.0.0 --push        # Builds with tags and pushes to registry
#   ./build-base.sh --push --registry custom.io/repo   # Push to custom registry
#
# Loads git configuration from .env file (if present):
#   GIT_USER_EMAIL=your.email@example.com
#   GIT_USER_NAME=Your Name
#   REGISTRY_URL=ghcr.io/ksizzle88/claudio  # Default registry (optional)
#   GHCR_TOKEN=ghp_your_token_here          # For registry authentication (optional)

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Parse arguments
TAG_ARRAY=()
PUSH_TO_REGISTRY=false
REGISTRY_URL="${REGISTRY_URL:-ghcr.io/ksizzle88/claudio}"

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
        --push)
            PUSH_TO_REGISTRY=true
            shift
            ;;
        --registry)
            REGISTRY_URL="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown argument: $1${NC}"
            echo "Usage: $0 [--tags TAG1 [TAG2 ...]] [--push] [--registry REGISTRY_URL]"
            exit 1
            ;;
    esac
done

# Default to current branch name if no tags specified
if [ ${#TAG_ARRAY[@]} -eq 0 ]; then
    # Get current branch name (sanitize for Docker tag format)
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | sed 's/[^a-zA-Z0-9._-]/-/g')

    if [ -n "$CURRENT_BRANCH" ]; then
        TAG_ARRAY=("$CURRENT_BRANCH")
    else
        # Fallback to 'dev' if not in a git repo
        TAG_ARRAY=("dev")
    fi
fi

# Compute build provenance
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BUILD_HOSTNAME=$(hostname -s 2>/dev/null || echo "unknown")

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BUILD_COMMIT=$(git rev-parse --short=7 HEAD 2>/dev/null || echo "unknown")
    BUILD_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

    # Append -dirty suffix if there are uncommitted changes
    if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet HEAD 2>/dev/null; then
        BUILD_COMMIT="${BUILD_COMMIT}-dirty"
    fi

    # Try to get a version tag
    BUILD_TAG=$(git describe --exact-match --tags 2>/dev/null || echo "dev")
else
    BUILD_COMMIT="unknown"
    BUILD_BRANCH="unknown"
    BUILD_TAG="dev"
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

echo "  Build provenance:"
echo "    Commit: $BUILD_COMMIT"
echo "    Branch: $BUILD_BRANCH"
echo "    Tag:    $BUILD_TAG"
echo "    Date:   $BUILD_DATE"
echo "    Host:   $BUILD_HOSTNAME"

# If pushing to registry, authenticate first
if [ "$PUSH_TO_REGISTRY" = true ]; then
    echo ""
    echo "Authenticating with registry..."

    # Try GHCR_TOKEN, then GITHUB_PACKAGE_PAT, then gh auth token
    REGISTRY_TOKEN="${GHCR_TOKEN:-${GITHUB_PACKAGE_PAT:-}}"
    if [ -n "$REGISTRY_TOKEN" ]; then
        echo "$REGISTRY_TOKEN" | docker login ghcr.io -u ksizzle88 --password-stdin
    elif command -v gh >/dev/null 2>&1; then
        gh auth token | docker login ghcr.io -u ksizzle88 --password-stdin
    else
        echo -e "${RED}Error: No authentication method available${NC}"
        echo "Set GHCR_TOKEN environment variable or authenticate with 'gh auth login'"
        exit 1
    fi
    echo ""
fi

# Build with both local and registry tags
PRIMARY_TAG="${TAG_ARRAY[0]}"
BUILD_TAGS=()
for tag in "${TAG_ARRAY[@]}"; do
    BUILD_TAGS+=("-t" "claudio-base:$tag")
    if [ "$PUSH_TO_REGISTRY" = true ]; then
        BUILD_TAGS+=("-t" "$REGISTRY_URL:$tag")
    fi
done

docker build \
    -f Dockerfile.base \
    "${BUILD_TAGS[@]}" \
    --build-arg NODE_VERSION="${NODE_VERSION:-22}" \
    --build-arg ZSH_IN_DOCKER_VERSION="${ZSH_IN_DOCKER_VERSION:-1.2.0}" \
    --build-arg GIT_USER_EMAIL="${GIT_USER_EMAIL:-}" \
    --build-arg GIT_USER_NAME="${GIT_USER_NAME:-}" \
    --build-arg GIT_GPG_SIGN="${GIT_GPG_SIGN:-false}" \
    --build-arg GIT_SIGNING_KEY="${GIT_SIGNING_KEY:-}" \
    --build-arg BUILD_COMMIT="${BUILD_COMMIT}" \
    --build-arg BUILD_DATE="${BUILD_DATE}" \
    --build-arg BUILD_BRANCH="${BUILD_BRANCH}" \
    --build-arg BUILD_TAG="${BUILD_TAG}" \
    --build-arg BUILD_HOSTNAME="${BUILD_HOSTNAME}" \
    .

# Push to registry if requested
if [ "$PUSH_TO_REGISTRY" = true ]; then
    echo ""
    echo "Pushing to registry..."
    for tag in "${TAG_ARRAY[@]}"; do
        echo "  Pushing $REGISTRY_URL:$tag"
        docker push "$REGISTRY_URL:$tag"
    done
    echo ""
fi

echo ""
echo -e "${GREEN}Build complete!${NC}"
echo ""
echo "Image tags:"
for tag in "${TAG_ARRAY[@]}"; do
    echo "  - claudio-base:$tag"
    if [ "$PUSH_TO_REGISTRY" = true ]; then
        echo "  - $REGISTRY_URL:$tag"
    fi
done
echo ""

if [ "$PUSH_TO_REGISTRY" = true ]; then
    echo -e "${GREEN}Push complete!${NC}"
    echo ""
    echo "All external repos can now use:"
    echo "  \"image\": \"$REGISTRY_URL:${TAG_ARRAY[0]}\""
    echo ""
fi

echo "Verify with:"
echo "  docker run --rm claudio-base:$PRIMARY_TAG claude --version"
echo "  docker run --rm claudio-base:$PRIMARY_TAG codex --version"
echo "  docker run --rm claudio-base:$PRIMARY_TAG python --version"
echo "  docker run --rm claudio-base:$PRIMARY_TAG node --version"
echo "  docker run --rm claudio-base:$PRIMARY_TAG gh --version"
echo "  docker run --rm claudio-base:$PRIMARY_TAG git config --global --list"
