#!/bin/bash
# Task 46 verification: init-claudio.sh syncs hooks on every container start
# Tests that hooks (and commands, skills, agents) sync OUTSIDE the first-init guard
#
# The active init script is /workspace/cli/scripts/init-claudio.sh (called via
# docker-entrypoint.sh). It uses a .initialized marker file for first-run gating.
# Phase 2 (shared volume sync) runs on EVERY start. Currently it only syncs
# skills and commands back to shared -- hooks and agents are missing.

set -euo pipefail

SCRIPT="/workspace/cli/scripts/init-claudio.sh"
PASS=0
FAIL=0
TESTS=0

pass() { PASS=$((PASS + 1)); TESTS=$((TESTS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); TESTS=$((TESTS + 1)); echo "  FAIL: $1"; }

echo "========================================"
echo "Task 46 - Hooks sync on every start"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# Helper: extract the always-run section (everything after the first-init fi)
#
# The first-init guard is:
#   if [ ! -f "$CLAUDIO_HOME/.initialized" ]; then ... fi
#
# We find the "touch .initialized" line, then the closing fi, and treat
# everything after that as the always-run section.
# ---------------------------------------------------------------------------
extract_always_run_section() {
    local marker_line
    marker_line=$(grep -n 'touch.*\.initialized' "$SCRIPT" | tail -1 | cut -d: -f1)
    if [ -z "$marker_line" ]; then
        echo ""
        return 1
    fi

    local fi_offset
    fi_offset=$(tail -n +"$marker_line" "$SCRIPT" | grep -n '^fi$' | head -1 | cut -d: -f1)
    if [ -z "$fi_offset" ]; then
        echo ""
        return 1
    fi

    local always_start=$(( marker_line + fi_offset ))
    tail -n +"$always_start" "$SCRIPT"
}

ALWAYS_RUN_SECTION=""

# ---------------------------------------------------------------------------
# Test 1: Script exists
# ---------------------------------------------------------------------------
echo "--- Test 1: Script exists ---"
if [ -f "$SCRIPT" ]; then
    pass "init-claudio.sh exists"
else
    fail "init-claudio.sh is missing"
fi

# ---------------------------------------------------------------------------
# Test 2: Extract always-run section and verify hooks sync is present
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 2: Hooks sync in always-run section (Phase 2+) ---"

ALWAYS_RUN_SECTION=$(extract_always_run_section)
if [ -z "$ALWAYS_RUN_SECTION" ]; then
    fail "Could not extract always-run section from script"
else
    if echo "$ALWAYS_RUN_SECTION" | grep -q 'hooks'; then
        pass "Hooks sync logic found in always-run section (after first-init guard)"
    else
        fail "No hooks sync logic found in always-run section"
    fi
fi

# ---------------------------------------------------------------------------
# Test 3: commands, skills, and agents also sync in always-run section
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 3: commands/skills/agents sync in always-run section ---"

if [ -n "$ALWAYS_RUN_SECTION" ]; then
    for dir in commands skills agents; do
        if echo "$ALWAYS_RUN_SECTION" | grep -q "$dir"; then
            pass "'$dir' sync found in always-run section"
        else
            fail "'$dir' sync NOT found in always-run section"
        fi
    done
else
    fail "Cannot check -- always-run section was not extracted"
    fail "Cannot check -- always-run section was not extracted"
    fail "Cannot check -- always-run section was not extracted"
fi

# ---------------------------------------------------------------------------
# Test 4: The sync uses cp -ru or equivalent (update-only, preserve newer)
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 4: Sync mechanism uses cp -ru ---"

if [ -n "$ALWAYS_RUN_SECTION" ]; then
    if echo "$ALWAYS_RUN_SECTION" | grep -qE 'cp\s+(-\S*r\S*u|-\S*u\S*r)'; then
        pass "cp -ru (update-only) found in always-run section"
    else
        fail "cp -ru NOT found in always-run section -- sync may overwrite newer files"
    fi
else
    fail "Cannot check -- always-run section was not extracted"
fi

# ---------------------------------------------------------------------------
# Test 5: Project hooks directory syncs to CLAUDE_DIR on every start
#         The fix should copy /workspace/.claude/hooks/ -> $CLAUDE_DIR/hooks/
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 5: Project hooks overlay to CLAUDE_DIR ---"

if [ -n "$ALWAYS_RUN_SECTION" ]; then
    # Look for patterns that copy from /workspace/.claude (or a variable pointing
    # to it) into CLAUDE_DIR, specifically including hooks. Accept:
    #   - A loop like: for dir in ... hooks ...; do ... done
    #   - Direct copy: cp -ru /workspace/.claude/hooks  or similar
    #   - Variable-based: cp -ru "$PROJECT_DIR/hooks" etc.
    if echo "$ALWAYS_RUN_SECTION" | grep -qE '(hooks.*cp|cp.*hooks|for\s+dir\s+in\s+\S*\s*.*hooks|/workspace/\.claude.*hooks)'; then
        pass "Project hooks -> CLAUDE_DIR sync found in always-run section"
    else
        fail "No project hooks -> CLAUDE_DIR sync found in always-run section"
    fi
else
    fail "Cannot check -- always-run section was not extracted"
fi

# ---------------------------------------------------------------------------
# Test 6: Functional test -- bidirectional sync: local hooks -> shared volume
#
# This is the critical missing piece. Put hooks in CLAUDE_DIR (local), run the
# script, and verify they get pushed to the shared plugins volume.
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 6: Functional test -- local hooks pushed to shared volume ---"

TEST_DIR=$(mktemp -d)
trap "rm -rf '$TEST_DIR'" EXIT

# Build a fake CLAUDIO_HOME that looks like a previous init already ran
FAKE_CLAUDIO_HOME="$TEST_DIR/claudio-home"
FAKE_CLAUDE_DIR="$FAKE_CLAUDIO_HOME/claude"
mkdir -p "$FAKE_CLAUDE_DIR"
echo '{}' > "$FAKE_CLAUDE_DIR/settings.json"
touch "$FAKE_CLAUDIO_HOME/.initialized"  # <-- signals "not first run"

# Put hooks in the LOCAL CLAUDE_DIR (simulating hooks that came from project overlay)
mkdir -p "$FAKE_CLAUDE_DIR/hooks"
echo '#!/bin/bash
echo "local hook"' > "$FAKE_CLAUDE_DIR/hooks/local-hook.sh"
chmod +x "$FAKE_CLAUDE_DIR/hooks/local-hook.sh"

# Put agents in the LOCAL CLAUDE_DIR too
mkdir -p "$FAKE_CLAUDE_DIR/agents"
echo '# local agent' > "$FAKE_CLAUDE_DIR/agents/local-agent.md"

# Build a fake shared volume (empty plugins -- no hooks there yet)
FAKE_SHARED="$TEST_DIR/claudio-shared"
mkdir -p "$FAKE_SHARED/auth"
mkdir -p "$FAKE_SHARED/plugins/skills"
mkdir -p "$FAKE_SHARED/plugins/commands"
mkdir -p "$FAKE_SHARED/caches/npm"
mkdir -p "$FAKE_SHARED/caches/pip"

# Create a fake HOME
FAKE_HOME="$TEST_DIR/fakehome"
mkdir -p "$FAKE_HOME"
touch "$FAKE_HOME/.bashrc"
touch "$FAKE_HOME/.zshrc"

# Run the script
(
    export HOME="$FAKE_HOME"
    export CLAUDIO_HOME="$FAKE_CLAUDIO_HOME"
    export CLAUDIO_SHARED="$FAKE_SHARED"

    bash "$SCRIPT" > "$TEST_DIR/output.log" 2>&1 || true
)

# Verify hooks were pushed to shared plugins
if [ -f "$FAKE_SHARED/plugins/hooks/local-hook.sh" ]; then
    pass "Local hooks were pushed to shared volume (bidirectional sync works)"
else
    fail "Local hooks were NOT pushed to shared volume"
    echo "    Shared plugins contents:"
    find "$FAKE_SHARED/plugins" -type f 2>/dev/null | sort | while read -r f; do echo "      $f"; done
    echo "    Script output:"
    cat "$TEST_DIR/output.log" 2>/dev/null | head -20 || true
fi

# ---------------------------------------------------------------------------
# Test 7: Functional test -- local agents pushed to shared volume
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 7: Functional test -- local agents pushed to shared volume ---"

if [ -f "$FAKE_SHARED/plugins/agents/local-agent.md" ]; then
    pass "Local agents were pushed to shared volume (bidirectional sync works)"
else
    fail "Local agents were NOT pushed to shared volume"
    echo "    Shared plugins contents:"
    find "$FAKE_SHARED/plugins" -type f 2>/dev/null | sort | while read -r f; do echo "      $f"; done
fi

# ---------------------------------------------------------------------------
# Test 8: First-init was correctly skipped (proving sync was via Phase 2)
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 8: First-init was skipped (Phase 2 path verified) ---"

if [ -f "$TEST_DIR/output.log" ]; then
    if grep -q "First run" "$TEST_DIR/output.log"; then
        fail "Script triggered first-run even though .initialized marker existed"
        echo "    Script output:"
        cat "$TEST_DIR/output.log" 2>/dev/null | head -20 || true
    else
        pass "Script correctly skipped first-run setup (.initialized marker respected)"
    fi
else
    fail "No script output captured"
fi

# ---------------------------------------------------------------------------
# Test 9: Bidirectional sync -- script text explicitly syncs hooks back
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 9: Script text explicitly syncs hooks back to shared ---"

if [ -n "$ALWAYS_RUN_SECTION" ]; then
    # The current pattern for skills/commands is:
    #   cp -ru "$CLAUDE_DIR/skills" "$CLAUDIO_SHARED/plugins/" 2>/dev/null || true
    #   cp -ru "$CLAUDE_DIR/commands" "$CLAUDIO_SHARED/plugins/" 2>/dev/null || true
    # The fix should add similar for hooks (and agents).
    # Accept either explicit lines or a loop that includes hooks.
    if echo "$ALWAYS_RUN_SECTION" | grep -qE 'cp\s+-ru\s+.*CLAUDE_DIR.*hooks|cp\s+-ru\s+.*hooks.*CLAUDIO_SHARED|for\s+dir\s+in\s+.*hooks.*do'; then
        pass "Explicit bidirectional hooks sync (local -> shared) found in script"
    else
        fail "No explicit bidirectional hooks sync (local -> shared) found in script"
    fi
else
    fail "Cannot check -- always-run section was not extracted"
fi

# ---------------------------------------------------------------------------
# Test 10: Project directory overlay for hooks on every start
#          The script should copy /workspace/.claude/hooks/ to CLAUDE_DIR
#          on every start, not just first-run.
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 10: Functional test -- project hooks overlay on every start ---"

TEST_DIR2=$(mktemp -d)

FAKE_CLAUDIO_HOME2="$TEST_DIR2/claudio-home"
FAKE_CLAUDE_DIR2="$FAKE_CLAUDIO_HOME2/claude"
mkdir -p "$FAKE_CLAUDE_DIR2"
echo '{}' > "$FAKE_CLAUDE_DIR2/settings.json"
touch "$FAKE_CLAUDIO_HOME2/.initialized"

# Create shared volume (empty plugins)
FAKE_SHARED2="$TEST_DIR2/claudio-shared"
mkdir -p "$FAKE_SHARED2/auth"
mkdir -p "$FAKE_SHARED2/plugins"
mkdir -p "$FAKE_SHARED2/caches/npm"
mkdir -p "$FAKE_SHARED2/caches/pip"

FAKE_HOME2="$TEST_DIR2/fakehome"
mkdir -p "$FAKE_HOME2"
touch "$FAKE_HOME2/.bashrc"
touch "$FAKE_HOME2/.zshrc"

# The script hardcodes /workspace/.claude for project overlay. If we are running
# inside the actual workspace, /workspace/.claude/hooks/ has real hooks.
if [ -d "/workspace/.claude/hooks" ] && [ -n "$(ls -A /workspace/.claude/hooks 2>/dev/null)" ]; then
    REAL_HOOKS=$(ls /workspace/.claude/hooks/ 2>/dev/null)

    (
        export HOME="$FAKE_HOME2"
        export CLAUDIO_HOME="$FAKE_CLAUDIO_HOME2"
        export CLAUDIO_SHARED="$FAKE_SHARED2"

        bash "$SCRIPT" > "$TEST_DIR2/output.log" 2>&1 || true
    )

    # Check if any hook from /workspace/.claude/hooks/ landed in CLAUDE_DIR
    FOUND_HOOK=false
    for hook_file in /workspace/.claude/hooks/*; do
        hook_name=$(basename "$hook_file")
        if [ -f "$FAKE_CLAUDE_DIR2/hooks/$hook_name" ]; then
            FOUND_HOOK=true
            break
        fi
    done

    if $FOUND_HOOK; then
        pass "Project hooks from /workspace/.claude/hooks/ synced on non-first-run"
    else
        fail "Project hooks from /workspace/.claude/hooks/ NOT synced on non-first-run"
        echo "    Expected hooks: $REAL_HOOKS"
        echo "    CLAUDE_DIR contents:"
        find "$FAKE_CLAUDE_DIR2" -type f 2>/dev/null | sort | while read -r f; do echo "      $f"; done
        echo "    Script output:"
        cat "$TEST_DIR2/output.log" 2>/dev/null | head -20 || true
    fi
else
    pass "Skipped (no hooks in /workspace/.claude/hooks/ to test with)"
fi

rm -rf "$TEST_DIR2"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed (out of $TESTS tests)"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

echo ""
echo "All tests passed."
exit 0
