#!/bin/bash
#
# Test-Sync Script - Pull repos, build base image, and open Trainer2
#
# Usage: ./claudio-dev/test-sync.sh [claudio-branch] [trainer2-branch]
#
# Default: Claudio on feature-setup2, Trainer2 on feature/dev_container_setup
#

set -e

CLAUDIO_BRANCH="${1:-feature-setup2}"
TRAINER2_BRANCH="${2:-feature/dev_container_setup}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
CLAUDIO_DIR="$SCRIPT_DIR"
TRAINER2_DIR="$PARENT_DIR/trainer2"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Claudio + Trainer2 Sync & Build${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "Claudio branch: $CLAUDIO_BRANCH"
echo "Trainer2 branch: $TRAINER2_BRANCH"
echo "Claudio dir: $CLAUDIO_DIR"
echo "Trainer2 dir: $TRAINER2_DIR"
echo ""

# Step 1: Pull Claudio
echo -e "${YELLOW}[1/4]${NC} Updating Claudio repo..."
cd "$CLAUDIO_DIR"
git fetch origin
git checkout "$CLAUDIO_BRANCH"
git pull origin "$CLAUDIO_BRANCH"
echo -e "${GREEN}✓${NC} Claudio updated to $CLAUDIO_BRANCH"
echo ""

# Step 2: Pull Trainer2
echo -e "${YELLOW}[2/4]${NC} Updating Trainer2 repo..."
cd "$TRAINER2_DIR"
git fetch origin
git checkout "$TRAINER2_BRANCH"
git pull origin "$TRAINER2_BRANCH"
echo -e "${GREEN}✓${NC} Trainer2 updated to $TRAINER2_BRANCH"
echo ""

# Step 3: Build base image
echo -e "${YELLOW}[3/4]${NC} Building claudio-base:latest image..."
cd "$CLAUDIO_DIR"
./build-base.sh

echo -e "${GREEN}✓${NC} Base image built"
echo ""

# Step 4: Open Trainer2
echo -e "${YELLOW}[4/4]${NC} Opening Trainer2 in VS Code..."
cd "$TRAINER2_DIR"
code .

echo ""
echo -e "${GREEN}✓${NC} VS Code opened"
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Next Steps${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "1. Click 'Reopen in Container' when prompted"
echo ""
echo "2. Inside the container you'll have:"
echo "   - claude --version"
echo "   - python --version (3.12)"
echo "   - node --version (20)"
echo ""
echo "3. Run Trainer2 services:"
echo "   docker compose up -d"
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Rebuilding After Claudio Updates${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "When you improve Claudio's Dockerfile.base:"
echo "  cd $CLAUDIO_DIR"
echo "  ./build-base.sh"
echo ""
echo "Then rebuild containers in your projects:"
echo "  VS Code: Cmd+Shift+P → 'Rebuild Container'"
echo ""
