#!/bin/bash
# smoke-test-image.sh - Build and smoke-test the Claudio base image
#
# Usage:
#   ./tests/smoke-test-image.sh                          # Build and test
#   ./tests/smoke-test-image.sh --skip-build             # Test an already-built image
#   ./tests/smoke-test-image.sh --image myimage:tag      # Test a specific image
#   ./tests/smoke-test-image.sh --skip-build --image img # Combine flags
#   ./tests/smoke-test-image.sh -h                       # Show this help

set -euo pipefail

# --- Defaults ---
IMAGE="claudio-base:test"
SKIP_BUILD=false
CONTAINER_NAME="claudio-smoke-test-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Colors ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# --- Counters ---
PASS=0
FAIL=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }

# --- Usage ---
usage() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Build and smoke-test the Claudio base image."
    echo ""
    echo "Options:"
    echo "  --skip-build    Skip the Docker build step (test an already-built image)"
    echo "  --image NAME    Image name to build/test (default: claudio-base:test)"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")                              # Build and test"
    echo "  $(basename "$0") --skip-build                 # Test existing image"
    echo "  $(basename "$0") --image claudio-base:dev     # Test a specific tag"
    exit 0
}

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --image)
            IMAGE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# --- Cleanup trap ---
cleanup() {
    echo ""
    echo -e "${BOLD}Cleaning up...${NC}"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# --- Helper: run a command inside the container as the dev user ---
dexec() {
    docker exec -u dev "$CONTAINER_NAME" "$@"
}

# --- Build ---
if [ "$SKIP_BUILD" = false ]; then
    echo -e "${BOLD}=== Building image: ${IMAGE} ===${NC}"
    docker build \
        -f "$REPO_ROOT/Dockerfile.base" \
        -t "$IMAGE" \
        "$REPO_ROOT"
    echo ""
fi

# --- Start container ---
echo -e "${BOLD}=== Starting container: ${CONTAINER_NAME} ===${NC}"
docker run -d \
    --name "$CONTAINER_NAME" \
    "$IMAGE" \
    sleep infinity
echo ""

# Wait briefly for the container to be ready
sleep 1

# ========================================================
# CHECK SECTION 1: Tools present
# ========================================================
echo -e "${BOLD}--- Tools present ---${NC}"

if dexec node --version >/dev/null 2>&1; then
    pass "node $(dexec node --version 2>&1)"
else
    fail "node not found"
fi

if dexec python --version >/dev/null 2>&1; then
    pass "python $(dexec python --version 2>&1)"
else
    fail "python not found"
fi

if dexec which claude >/dev/null 2>&1; then
    pass "claude found at $(dexec which claude 2>&1)"
else
    fail "claude not found"
fi

if dexec which codex >/dev/null 2>&1; then
    pass "codex found at $(dexec which codex 2>&1)"
else
    fail "codex not found"
fi

if dexec gh --version >/dev/null 2>&1; then
    pass "gh $(dexec gh --version 2>&1 | head -1)"
else
    fail "gh (GitHub CLI) not found"
fi

if dexec aws --version >/dev/null 2>&1; then
    pass "aws $(dexec aws --version 2>&1 | head -1)"
else
    fail "aws CLI not found"
fi

if dexec doppler --version >/dev/null 2>&1; then
    pass "doppler $(dexec doppler --version 2>&1 | head -1)"
else
    fail "doppler not found"
fi

if dexec tmux -V >/dev/null 2>&1; then
    pass "tmux $(dexec tmux -V 2>&1)"
else
    fail "tmux not found"
fi

if dexec git --version >/dev/null 2>&1; then
    pass "git $(dexec git --version 2>&1)"
else
    fail "git not found"
fi

if dexec jq --version >/dev/null 2>&1; then
    pass "jq $(dexec jq --version 2>&1)"
else
    fail "jq not found"
fi

echo ""

# ========================================================
# CHECK SECTION 2: Init scripts syntax check
# ========================================================
echo -e "${BOLD}--- Init scripts ---${NC}"

if dexec bash -n /usr/local/bin/init-claudio >/dev/null 2>&1; then
    pass "init-claudio passes syntax check"
else
    fail "init-claudio has syntax errors"
fi

if dexec bash -n /usr/local/bin/init-claude-settings.sh >/dev/null 2>&1; then
    pass "init-claude-settings.sh passes syntax check"
else
    fail "init-claude-settings.sh has syntax errors"
fi

# Run init-claudio as dev user and verify it completes successfully
if dexec bash -c 'init-claudio' >/dev/null 2>&1; then
    pass "init-claudio runs successfully as dev user"
else
    fail "init-claudio failed to run as dev user"
fi

echo ""

# ========================================================
# CHECK SECTION 3: Directory structure after init
# ========================================================
echo -e "${BOLD}--- Directory structure after init ---${NC}"

# ~/.claudio/claude/ is the CLAUDE_DIR set by init-claudio
CLAUDE_DIR="\$HOME/.claudio/claude"

if dexec bash -c "[ -d $CLAUDE_DIR/hooks ] && [ \"\$(ls -A $CLAUDE_DIR/hooks 2>/dev/null)\" ]"; then
    pass "~/.claudio/claude/hooks/ exists and has files"
else
    fail "~/.claudio/claude/hooks/ missing or empty"
fi

if dexec bash -c "[ -d $CLAUDE_DIR/agents ] && [ \"\$(ls -A $CLAUDE_DIR/agents 2>/dev/null)\" ]"; then
    pass "~/.claudio/claude/agents/ exists and has files"
else
    fail "~/.claudio/claude/agents/ missing or empty"
fi

if dexec bash -c "[ -d $CLAUDE_DIR/skills ] && [ \"\$(find $CLAUDE_DIR/skills -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)\" ]"; then
    pass "~/.claudio/claude/skills/ exists and has subdirs"
else
    fail "~/.claudio/claude/skills/ missing or has no subdirs"
fi

if dexec bash -c "[ -d $CLAUDE_DIR/commands ] && [ \"\$(ls -A $CLAUDE_DIR/commands 2>/dev/null)\" ]"; then
    pass "~/.claudio/claude/commands/ exists and has files"
else
    fail "~/.claudio/claude/commands/ missing or empty"
fi

if dexec bash -c "[ -f $CLAUDE_DIR/settings.json ]"; then
    pass "~/.claudio/claude/settings.json exists"
else
    fail "~/.claudio/claude/settings.json missing"
fi

# No flat-copy bug: hooks files should NOT appear in the claude/ root
# e.g., task-completed.sh should be in hooks/ not in the root
if dexec bash -c "[ ! -f $CLAUDE_DIR/task-completed.sh ] && [ ! -f $CLAUDE_DIR/teammate-idle.sh ]"; then
    pass "no flat-copy bug: hook scripts are not in claude/ root"
else
    fail "flat-copy bug detected: hook scripts found in claude/ root instead of hooks/"
fi

echo ""

# ========================================================
# CHECK SECTION 4: Image defaults
# ========================================================
echo -e "${BOLD}--- Image defaults ---${NC}"

if dexec bash -c '[ -d /opt/claudio-defaults/.claude ] && [ "$(ls -A /opt/claudio-defaults/.claude 2>/dev/null)" ]'; then
    pass "/opt/claudio-defaults/.claude/ exists and is populated"
else
    fail "/opt/claudio-defaults/.claude/ missing or empty"
fi

# Check that defaults have proper subdirectory structure (not just flat files)
DEFAULTS_HAS_SUBDIRS=true
for subdir in hooks agents skills commands; do
    if ! dexec bash -c "[ -d /opt/claudio-defaults/.claude/$subdir ]" 2>/dev/null; then
        DEFAULTS_HAS_SUBDIRS=false
        break
    fi
done
if [ "$DEFAULTS_HAS_SUBDIRS" = true ]; then
    pass "/opt/claudio-defaults/.claude/ has proper subdirectories (hooks, agents, skills, commands)"
else
    fail "/opt/claudio-defaults/.claude/ missing expected subdirectories"
fi

if dexec bash -c '[ -f /etc/claudio-release ]'; then
    pass "/etc/claudio-release exists"
else
    fail "/etc/claudio-release missing"
fi

echo ""

# ========================================================
# CHECK SECTION 5: User and permissions
# ========================================================
echo -e "${BOLD}--- User/permissions ---${NC}"

if dexec id dev >/dev/null 2>&1; then
    DEV_UID=$(dexec id -u dev 2>&1 | tr -d '[:space:]')
    if [ "$DEV_UID" = "1000" ]; then
        pass "dev user exists with UID 1000"
    else
        fail "dev user exists but UID is $DEV_UID (expected 1000)"
    fi
else
    fail "dev user does not exist"
fi

DEV_HOME=$(dexec bash -c 'echo $HOME' 2>&1)
if [ "$DEV_HOME" = "/home/dev" ]; then
    pass "HOME is /home/dev"
else
    fail "HOME is '$DEV_HOME' (expected /home/dev)"
fi

if dexec sudo true >/dev/null 2>&1; then
    pass "passwordless sudo works"
else
    fail "passwordless sudo does not work"
fi

echo ""

# ========================================================
# Summary
# ========================================================
TOTAL=$((PASS + FAIL))
echo -e "${BOLD}=== Summary ===${NC}"
echo -e "  Total:  $TOTAL"
echo -e "  ${GREEN}Passed: $PASS${NC}"
if [ "$FAIL" -gt 0 ]; then
    echo -e "  ${RED}Failed: $FAIL${NC}"
    echo ""
    echo -e "${RED}SMOKE TEST FAILED${NC}"
    exit 1
else
    echo -e "  Failed: 0"
    echo ""
    echo -e "${GREEN}ALL SMOKE TESTS PASSED${NC}"
    exit 0
fi
