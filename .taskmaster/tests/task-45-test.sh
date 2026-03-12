#!/usr/bin/env bash
# Task 45 verification: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS should only be in settings.json
set -uo pipefail

PASS=0; FAIL=0; ERRORS=""
pass() { echo "  PASS: $1"; ((PASS++)); }
fail() { echo "  FAIL: $1"; ((FAIL++)); ERRORS="${ERRORS}\n  - $1"; }

echo "Task 45: Clean up duplicate AGENT_TEAMS env var"
echo "================================================"

# Test 1: Env var should NOT be set in Dockerfile.base
if grep -q 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' /workspace/Dockerfile.base; then
    fail "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS still found in Dockerfile.base"
else
    pass "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS not in Dockerfile.base"
fi

# Test 2: Env var SHOULD be set in .claude/settings.json
if grep -q '"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"' /workspace/.claude/settings.json; then
    pass "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS present in .claude/settings.json"
else
    fail "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS missing from .claude/settings.json"
fi

# Test 3: Env var should be set in exactly ONE config file (not counting docs/markdown/test files)
# Search all non-markdown, non-test files for the env var assignment
COUNT=$(grep -rl 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' /workspace/ \
    --include='*.json' --include='*.sh' --include='*.yml' --include='*.yaml' \
    --include='Dockerfile*' --include='*.env' --include='*.toml' \
    2>/dev/null \
    | grep -v '.taskmaster/' \
    | grep -v 'node_modules/' \
    | grep -v '.git/' \
    | wc -l)

if [ "$COUNT" -eq 1 ]; then
    pass "Env var set in exactly 1 config file (found in $COUNT file)"
else
    # Show which files contain it for debugging
    FILES=$(grep -rl 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' /workspace/ \
        --include='*.json' --include='*.sh' --include='*.yml' --include='*.yaml' \
        --include='Dockerfile*' --include='*.env' --include='*.toml' \
        2>/dev/null \
        | grep -v '.taskmaster/' \
        | grep -v 'node_modules/' \
        | grep -v '.git/')
    fail "Env var found in $COUNT config files (expected 1): $FILES"
fi

echo ""
echo "RESULTS: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -gt 0 ] && echo -e "$ERRORS" && exit 1
exit 0
