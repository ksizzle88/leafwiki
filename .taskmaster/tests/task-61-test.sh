#!/usr/bin/env bash
# Task 61 verification: jtbl 2.0 TUI — Rust-based JSON Exploration & Table Tool
# Tests that the Rust project builds, produces correct CLI output, and meets
# all acceptance criteria from Issue #61.
#
# Usage: bash .taskmaster/tests/task-61-test.sh

set -euo pipefail

JTBL_DIR="/workspace/tools/jtbl"
PASS=0
FAIL=0
SKIP=0
TESTS=0

pass() { PASS=$((PASS + 1)); TESTS=$((TESTS + 1)); echo "  [PASS] $1"; }
fail() { FAIL=$((FAIL + 1)); TESTS=$((TESTS + 1)); echo "  [FAIL] $1"; }
skip() { SKIP=$((SKIP + 1)); TESTS=$((TESTS + 1)); echo "  [SKIP] $1"; }

# ---------------------------------------------------------------------------
# Setup: temporary directory for test data
# ---------------------------------------------------------------------------
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Create test JSON fixtures
cat > "$TEST_DIR/data.json" <<'FIXTURE'
{
  "items": [
    {"id": 1, "name": "Alice", "meta": {"team": "backend", "level": 3}},
    {"id": 2, "name": "Bob",   "meta": {"team": "frontend", "level": 2}},
    {"id": 3, "name": "Carol", "meta": {"team": "backend", "level": 4}},
    {"id": 4, "name": "Dave",  "meta": {"team": "infra", "level": 5}},
    {"id": 5, "name": "Eve",   "meta": {"team": "frontend", "level": 1}}
  ]
}
FIXTURE

cat > "$TEST_DIR/flat_array.json" <<'FIXTURE'
[
  {"name": "foo", "value": 42},
  {"name": "bar", "value": 99},
  {"name": "baz", "value": 7}
]
FIXTURE

cat > "$TEST_DIR/nested.json" <<'FIXTURE'
{
  "results": {
    "data": [
      {"host": "srv-1", "cpu": 0.82, "memory": {"used_gb": 12.4, "total_gb": 32}},
      {"host": "srv-2", "cpu": 0.45, "memory": {"used_gb": 8.1,  "total_gb": 64}},
      {"host": "srv-3", "cpu": 0.91, "memory": {"used_gb": 30.2, "total_gb": 32}}
    ]
  }
}
FIXTURE

echo "========================================"
echo "Task 61 - jtbl 2.0 TUI Verification"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# Check: Rust toolchain available
# ---------------------------------------------------------------------------
CARGO_BIN=""
if command -v cargo &>/dev/null; then
    CARGO_BIN="cargo"
elif [ -x "$HOME/.cargo/bin/cargo" ]; then
    CARGO_BIN="$HOME/.cargo/bin/cargo"
    export PATH="$HOME/.cargo/bin:$PATH"
fi

HAS_RUST=false
if [ -n "$CARGO_BIN" ]; then
    HAS_RUST=true
    echo "Rust toolchain found: $($CARGO_BIN --version)"
else
    echo "WARNING: Rust toolchain not found. Build/clippy/unit-test checks will be skipped."
    echo "         Install with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
fi
echo ""

# =====================================================================
# SECTION 1: Project Structure & Dependencies
# =====================================================================
echo "--- Section 1: Project Structure & Dependencies ---"

# 1.1 Cargo.toml exists
if [ -f "$JTBL_DIR/Cargo.toml" ]; then
    pass "Cargo.toml exists at tools/jtbl/"
else
    fail "Cargo.toml missing at tools/jtbl/"
fi

# 1.2 Required dependencies in Cargo.toml
if [ -f "$JTBL_DIR/Cargo.toml" ]; then
    REQUIRED_DEPS=("ratatui" "crossterm" "serde_json" "clap" "comfy-table")
    for dep in "${REQUIRED_DEPS[@]}"; do
        if grep -q "$dep" "$JTBL_DIR/Cargo.toml"; then
            pass "Cargo.toml lists dependency: $dep"
        else
            fail "Cargo.toml missing dependency: $dep"
        fi
    done

    # Check for a jq engine (jaq-core or jaq-interpret or jaq)
    if grep -qE '(jaq-core|jaq-interpret|jaq)' "$JTBL_DIR/Cargo.toml"; then
        pass "Cargo.toml lists a jq engine (jaq crate)"
    else
        fail "Cargo.toml missing a jq engine (expected jaq-core, jaq-interpret, or jaq)"
    fi
else
    for i in 1 2 3 4 5 6; do
        skip "Cannot check dependencies — Cargo.toml missing"
    done
fi

# 1.3 Key source files exist
echo ""
echo "--- Section 1b: Source File Structure ---"

if [ -d "$JTBL_DIR/src" ]; then
    if [ -f "$JTBL_DIR/src/main.rs" ]; then
        pass "src/main.rs exists"
    else
        fail "src/main.rs missing"
    fi

    # Check for modular structure (at least a few modules)
    SRC_FILES=$(find "$JTBL_DIR/src" -name '*.rs' | wc -l)
    if [ "$SRC_FILES" -ge 3 ]; then
        pass "Modular source structure ($SRC_FILES .rs files)"
    else
        fail "Expected modular source structure (>= 3 .rs files), found $SRC_FILES"
    fi
else
    fail "src/ directory missing at tools/jtbl/"
    skip "Cannot check source file structure"
fi

# =====================================================================
# SECTION 2: Build & Compile
# =====================================================================
echo ""
echo "--- Section 2: Build & Compile ---"

JTBL_BINARY=""

if $HAS_RUST && [ -f "$JTBL_DIR/Cargo.toml" ]; then
    # 2.1 cargo build --release
    echo "  Building (cargo build --release)... this may take a while on first run."
    if (cd "$JTBL_DIR" && $CARGO_BIN build --release 2>"$TEST_DIR/build_stderr.log"); then
        pass "cargo build --release succeeded"
    else
        fail "cargo build --release failed: $(head -5 "$TEST_DIR/build_stderr.log")"
    fi

    # 2.2 Binary exists
    if [ -f "$JTBL_DIR/target/release/jtbl" ]; then
        JTBL_BINARY="$JTBL_DIR/target/release/jtbl"
        pass "Release binary exists at target/release/jtbl"
    else
        fail "Release binary not found at target/release/jtbl"
    fi
else
    skip "cargo build — Rust toolchain not available or Cargo.toml missing"
    skip "Binary existence — build skipped"
fi

# =====================================================================
# SECTION 3: Binary Properties
# =====================================================================
echo ""
echo "--- Section 3: Binary Properties ---"

if [ -n "$JTBL_BINARY" ] && [ -f "$JTBL_BINARY" ]; then
    # 3.1 Binary size < 50MB
    BINARY_SIZE=$(stat -c%s "$JTBL_BINARY" 2>/dev/null || stat -f%z "$JTBL_BINARY" 2>/dev/null || echo 0)
    BINARY_SIZE_MB=$((BINARY_SIZE / 1048576))
    if [ "$BINARY_SIZE" -gt 0 ] && [ "$BINARY_SIZE_MB" -lt 50 ]; then
        pass "Binary size is reasonable (${BINARY_SIZE_MB}MB < 50MB)"
    elif [ "$BINARY_SIZE" -eq 0 ]; then
        fail "Could not determine binary size"
    else
        fail "Binary too large (${BINARY_SIZE_MB}MB >= 50MB)"
    fi

    # 3.2 Check runtime dependencies (ldd)
    if command -v ldd &>/dev/null; then
        LDD_OUTPUT=$(ldd "$JTBL_BINARY" 2>&1 || true)
        if echo "$LDD_OUTPUT" | grep -q "not a dynamic executable\|statically linked"; then
            pass "Binary is statically linked (no runtime dependencies)"
        else
            # Dynamic is acceptable if deps are standard libc only
            NON_LIBC_DEPS=$(echo "$LDD_OUTPUT" | grep -cvE '(linux-vdso|libpthread|libdl|librt|libm|libc|libgcc|ld-linux)' || true)
            if [ "$NON_LIBC_DEPS" -le 1 ]; then
                pass "Binary has minimal runtime dependencies (standard libc only)"
            else
                fail "Binary has non-standard runtime dependencies: $(echo "$LDD_OUTPUT" | grep -vE '(linux-vdso|libpthread|libdl|librt|libm|libc|libgcc|ld-linux)' | head -5)"
            fi
        fi
    else
        skip "ldd not available — cannot check runtime dependencies"
    fi

    # 3.3 --help flag works
    if "$JTBL_BINARY" --help &>"$TEST_DIR/help_output.txt"; then
        pass "Binary --help runs without error"
    else
        fail "Binary --help exited with error"
    fi

    # 3.4 --help mentions key features
    if [ -f "$TEST_DIR/help_output.txt" ]; then
        if grep -qi "interactive\|tui\|-i" "$TEST_DIR/help_output.txt"; then
            pass "--help mentions interactive/TUI mode"
        else
            fail "--help does not mention interactive/TUI mode"
        fi
    fi

    # 3.5 --version flag works
    if VERSION_OUT=$("$JTBL_BINARY" --version 2>&1) && [ -n "$VERSION_OUT" ]; then
        pass "Binary --version outputs version info: $VERSION_OUT"
    else
        fail "Binary --version produced no output or errored"
    fi
else
    skip "Binary size — binary not available"
    skip "Runtime dependencies — binary not available"
    skip "--help — binary not available"
    skip "--help TUI mention — binary not available"
    skip "--version — binary not available"
fi

# =====================================================================
# SECTION 4: Non-Interactive Mode (Core Acceptance Criteria)
# =====================================================================
echo ""
echo "--- Section 4: Non-Interactive CLI Output ---"

if [ -n "$JTBL_BINARY" ] && [ -f "$JTBL_BINARY" ]; then
    # 4.1 AC: jtbl '.items' data.json outputs a formatted table to stdout
    TABLE_OUTPUT=$("$JTBL_BINARY" '.items' "$TEST_DIR/data.json" 2>/dev/null || true)
    if [ -n "$TABLE_OUTPUT" ]; then
        # Check that output contains expected column headers or data
        if echo "$TABLE_OUTPUT" | grep -qi "Alice\|name\|id"; then
            pass "jtbl '.items' data.json produces table with expected data"
        else
            fail "jtbl '.items' data.json produced output but missing expected data (Alice, name, id)"
            echo "    Output: $(echo "$TABLE_OUTPUT" | head -5)"
        fi
    else
        fail "jtbl '.items' data.json produced no output"
    fi

    # 4.2 Column auto-inference works for nested JSON
    NESTED_OUTPUT=$("$JTBL_BINARY" '.results.data' "$TEST_DIR/nested.json" 2>/dev/null || true)
    if [ -n "$NESTED_OUTPUT" ]; then
        if echo "$NESTED_OUTPUT" | grep -qi "host\|srv-1\|cpu"; then
            pass "Column auto-inference works for nested JSON"
        else
            fail "Nested JSON output missing expected columns (host, cpu)"
            echo "    Output: $(echo "$NESTED_OUTPUT" | head -5)"
        fi
    else
        fail "Nested JSON produced no output"
    fi

    # 4.3 Piping JSON via stdin
    STDIN_OUTPUT=$(echo '[{"a":1,"b":2},{"a":3,"b":4}]' | "$JTBL_BINARY" '.' 2>/dev/null || true)
    if [ -n "$STDIN_OUTPUT" ]; then
        pass "Piping JSON via stdin works"
    else
        fail "Piping JSON via stdin produced no output"
    fi

    # 4.4 Markdown format output
    MD_OUTPUT=$("$JTBL_BINARY" '.items' "$TEST_DIR/data.json" --fmt markdown 2>/dev/null || \
                "$JTBL_BINARY" '.items' "$TEST_DIR/data.json" --format markdown 2>/dev/null || true)
    if [ -n "$MD_OUTPUT" ]; then
        if echo "$MD_OUTPUT" | grep -q '|.*|'; then
            pass "--fmt markdown produces markdown table"
        else
            fail "--fmt markdown output does not look like markdown (no pipe characters)"
            echo "    Output: $(echo "$MD_OUTPUT" | head -5)"
        fi
    else
        fail "--fmt markdown produced no output"
    fi

    # 4.5 CSV format output
    CSV_OUTPUT=$("$JTBL_BINARY" '.items' "$TEST_DIR/data.json" --fmt csv 2>/dev/null || \
                 "$JTBL_BINARY" '.items' "$TEST_DIR/data.json" --format csv 2>/dev/null || true)
    if [ -n "$CSV_OUTPUT" ]; then
        if echo "$CSV_OUTPUT" | grep -q ','; then
            pass "--fmt csv produces CSV output"
        else
            fail "--fmt csv output does not look like CSV (no commas)"
            echo "    Output: $(echo "$CSV_OUTPUT" | head -3)"
        fi
    else
        fail "--fmt csv produced no output"
    fi

    # 4.6 JSON format output
    JSON_OUTPUT=$("$JTBL_BINARY" '.items' "$TEST_DIR/data.json" --fmt json 2>/dev/null || \
                  "$JTBL_BINARY" '.items' "$TEST_DIR/data.json" --format json 2>/dev/null || true)
    if [ -n "$JSON_OUTPUT" ]; then
        # Validate it's valid JSON
        if echo "$JSON_OUTPUT" | python3 -m json.tool &>/dev/null || echo "$JSON_OUTPUT" | jq . &>/dev/null; then
            pass "--fmt json produces valid JSON output"
        else
            fail "--fmt json output is not valid JSON"
            echo "    Output: $(echo "$JSON_OUTPUT" | head -3)"
        fi
    else
        fail "--fmt json produced no output"
    fi

    # 4.7 --limit flag
    LIMIT_OUTPUT=$("$JTBL_BINARY" '.items' "$TEST_DIR/data.json" --limit 2 2>/dev/null || true)
    if [ -n "$LIMIT_OUTPUT" ]; then
        # Count data rows (exclude header/separator lines)
        DATA_LINES=$(echo "$LIMIT_OUTPUT" | grep -c "Alice\|Bob\|Carol\|Dave\|Eve" || true)
        if [ "$DATA_LINES" -le 2 ]; then
            pass "--limit 2 restricts output to at most 2 data rows"
        else
            fail "--limit 2 produced $DATA_LINES data rows (expected <= 2)"
        fi
    else
        fail "--limit flag produced no output"
    fi

    # 4.8 --where filter
    WHERE_OUTPUT=$("$JTBL_BINARY" '.items' "$TEST_DIR/data.json" --where '.id > 3' 2>/dev/null || true)
    if [ -n "$WHERE_OUTPUT" ]; then
        # Should contain Dave (id=4) and Eve (id=5), but not Alice/Bob/Carol
        HAS_EXPECTED=$(echo "$WHERE_OUTPUT" | grep -ci "Dave\|Eve" || true)
        HAS_EXCLUDED=$(echo "$WHERE_OUTPUT" | grep -ci "Alice\|Bob\|Carol" || true)
        if [ "$HAS_EXPECTED" -ge 1 ] && [ "$HAS_EXCLUDED" -eq 0 ]; then
            pass "--where filter correctly filters rows"
        elif [ "$HAS_EXPECTED" -ge 1 ]; then
            fail "--where filter included rows that should have been excluded"
        else
            fail "--where filter output missing expected rows"
            echo "    Output: $(echo "$WHERE_OUTPUT" | head -5)"
        fi
    else
        fail "--where filter produced no output"
    fi

    # 4.9 Sort flags
    SORT_OUTPUT=$("$JTBL_BINARY" '.' "$TEST_DIR/flat_array.json" --sort value 2>/dev/null || \
                  "$JTBL_BINARY" '.' "$TEST_DIR/flat_array.json" --sort-by value 2>/dev/null || true)
    if [ -n "$SORT_OUTPUT" ]; then
        # Values should appear in order: 7, 42, 99 (ascending)
        # Check that baz (7) appears before foo (42) appears before bar (99)
        BAZ_LINE=$(echo "$SORT_OUTPUT" | grep -n "baz" | head -1 | cut -d: -f1 || echo 0)
        FOO_LINE=$(echo "$SORT_OUTPUT" | grep -n "foo" | head -1 | cut -d: -f1 || echo 0)
        BAR_LINE=$(echo "$SORT_OUTPUT" | grep -n "bar" | head -1 | cut -d: -f1 || echo 0)
        if [ "$BAZ_LINE" -gt 0 ] && [ "$FOO_LINE" -gt 0 ] && [ "$BAR_LINE" -gt 0 ] && \
           [ "$BAZ_LINE" -lt "$FOO_LINE" ] && [ "$FOO_LINE" -lt "$BAR_LINE" ]; then
            pass "Sort by value produces ascending order"
        else
            fail "Sort by value did not produce expected ascending order (baz=7, foo=42, bar=99)"
            echo "    Output: $(echo "$SORT_OUTPUT" | head -8)"
        fi
    else
        fail "Sort flag produced no output"
    fi
else
    for i in $(seq 1 9); do
        skip "Non-interactive test $i — binary not available"
    done
fi

# =====================================================================
# SECTION 5: TUI Mode Checks (limited)
# =====================================================================
echo ""
echo "--- Section 5: TUI / Interactive Mode ---"

if [ -n "$JTBL_BINARY" ] && [ -f "$JTBL_BINARY" ]; then
    # 5.1 -i flag is recognized (--help mentions it)
    if [ -f "$TEST_DIR/help_output.txt" ] && grep -qE '\-i[ ,]|--interactive' "$TEST_DIR/help_output.txt"; then
        pass "-i / --interactive flag is documented in --help"
    else
        fail "-i / --interactive flag not found in --help output"
    fi

    # 5.2 Binary doesn't crash immediately with -i (use timeout)
    if command -v timeout &>/dev/null; then
        # Run with a very short timeout; we expect it to either start TUI (and get killed by timeout)
        # or exit cleanly if no TTY is available. Either way, exit code 124 (timeout) or 0 is fine.
        # A crash would produce a different exit code (segfault=139, panic=101, etc.)
        timeout 2 "$JTBL_BINARY" -i '.' "$TEST_DIR/flat_array.json" &>"$TEST_DIR/tui_output.txt" || TUI_EXIT=$?
        TUI_EXIT=${TUI_EXIT:-0}
        if [ "$TUI_EXIT" -eq 124 ] || [ "$TUI_EXIT" -eq 0 ] || [ "$TUI_EXIT" -eq 1 ]; then
            pass "Binary with -i flag does not crash (exit code: $TUI_EXIT)"
        else
            fail "Binary with -i flag crashed (exit code: $TUI_EXIT)"
            echo "    Output: $(head -5 "$TEST_DIR/tui_output.txt" 2>/dev/null)"
        fi
    else
        skip "timeout command not available — cannot test TUI launch"
    fi
else
    skip "TUI -i flag — binary not available"
    skip "TUI launch test — binary not available"
fi

# =====================================================================
# SECTION 6: Code Quality
# =====================================================================
echo ""
echo "--- Section 6: Code Quality ---"

if $HAS_RUST && [ -f "$JTBL_DIR/Cargo.toml" ]; then
    # 6.1 cargo clippy
    if (cd "$JTBL_DIR" && $CARGO_BIN clippy -- -D warnings 2>"$TEST_DIR/clippy_stderr.log" >/dev/null); then
        pass "cargo clippy passes with no warnings"
    else
        fail "cargo clippy has warnings or errors: $(tail -3 "$TEST_DIR/clippy_stderr.log")"
    fi

    # 6.2 cargo test
    if (cd "$JTBL_DIR" && $CARGO_BIN test 2>"$TEST_DIR/test_stderr.log" >"$TEST_DIR/test_stdout.log"); then
        TEST_SUMMARY=$(grep -E "test result:" "$TEST_DIR/test_stdout.log" | tail -1 || echo "unknown")
        pass "cargo test passes ($TEST_SUMMARY)"
    else
        fail "cargo test failed: $(tail -5 "$TEST_DIR/test_stderr.log")"
    fi

    # 6.3 No unsafe blocks (or minimal)
    UNSAFE_COUNT=$(grep -r 'unsafe ' "$JTBL_DIR/src/" 2>/dev/null | grep -cv '^\s*//' || true)
    if [ "$UNSAFE_COUNT" -eq 0 ]; then
        pass "No unsafe blocks in source code"
    else
        fail "Found $UNSAFE_COUNT unsafe blocks in source code (review for justification)"
    fi
else
    skip "cargo clippy — Rust toolchain not available"
    skip "cargo test — Rust toolchain not available"
    skip "unsafe block check — Rust toolchain not available"
fi

# =====================================================================
# SECTION 7: Integration — Builds in Claudio Devcontainer
# =====================================================================
echo ""
echo "--- Section 7: Devcontainer Integration ---"

# 7.1 Project is within the workspace
if [[ "$JTBL_DIR" == /workspace/* ]]; then
    pass "Project is within /workspace (devcontainer workspace root)"
else
    fail "Project is not within /workspace"
fi

# 7.2 No hardcoded paths outside workspace
if [ -d "$JTBL_DIR/src" ]; then
    HARDCODED_PATHS=$(grep -rn '/Users/\|/home/[a-z]' "$JTBL_DIR/src/" 2>/dev/null || true)
    if [ -z "$HARDCODED_PATHS" ]; then
        pass "No hardcoded user-specific paths in source"
    else
        fail "Found hardcoded paths in source: $(echo "$HARDCODED_PATHS" | head -3)"
    fi
else
    skip "Cannot check for hardcoded paths — src/ missing"
fi

# 7.3 .gitignore includes target/
if [ -f "$JTBL_DIR/.gitignore" ]; then
    if grep -q 'target' "$JTBL_DIR/.gitignore"; then
        pass ".gitignore excludes target/ directory"
    else
        fail ".gitignore does not exclude target/ directory"
    fi
elif [ -f "/workspace/.gitignore" ]; then
    if grep -q 'target\|tools/jtbl/target' "/workspace/.gitignore"; then
        pass "Root .gitignore excludes target/ directory"
    else
        fail "No .gitignore rule for target/ build artifacts"
    fi
else
    fail "No .gitignore found for build artifacts"
fi

# =====================================================================
# Summary
# =====================================================================
echo ""
echo "========================================"
echo "=== RESULTS ==="
TOTAL=$((PASS + FAIL + SKIP))
echo "PASSED: $PASS/$TOTAL"
echo "FAILED: $FAIL/$TOTAL"
if [ "$SKIP" -gt 0 ]; then
    echo "SKIPPED: $SKIP/$TOTAL"
fi
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

echo ""
echo "All tests passed."
exit 0
