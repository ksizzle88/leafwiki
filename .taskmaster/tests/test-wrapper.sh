#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# test-wrapper.sh - Validate the task-master wrapper at /usr/local/bin/task-master
# =============================================================================

TASKS_FILE="/workspace/.taskmaster/tasks/tasks.json"
BACKUP_FILE="$(mktemp /tmp/tasks-backup.XXXXXX.json)"
TASK_ID="28"
PASS_COUNT=0
FAIL_COUNT=0
TOTAL=11

# ---------- helpers ----------

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "  PASS: $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "  FAIL: $1"
}

get_field() {
  # $1 = field name (title, description, details)
  jq -r --arg id "${TASK_ID}" \
    '.master.tasks[] | select(.id == $id) | .'"$1" \
    "${TASKS_FILE}"
}

restore_backup() {
  cp "${BACKUP_FILE}" "${TASKS_FILE}"
}

# ---------- setup ----------

echo "=== task-master wrapper test suite ==="
echo ""
echo "Backing up tasks.json to ${BACKUP_FILE}"
cp "${TASKS_FILE}" "${BACKUP_FILE}"

# Ensure we always restore on exit
trap 'echo ""; echo "Restoring original tasks.json from backup..."; cp "${BACKUP_FILE}" "${TASKS_FILE}"; rm -f "${BACKUP_FILE}"; echo "Restored."' EXIT

# ---------- tests ----------

# Test 1: PATH resolution
echo ""
echo "Test 1: PATH resolution"
WHICH_RESULT="$(which task-master 2>/dev/null || true)"
if [[ "${WHICH_RESULT}" == "/usr/local/bin/task-master" ]]; then
  pass "which task-master returns /usr/local/bin/task-master"
else
  fail "which task-master returned '${WHICH_RESULT}' (expected /usr/local/bin/task-master)"
fi

# Test 2: Passthrough version
echo ""
echo "Test 2: Passthrough version"
VERSION_OUTPUT="$(task-master --version 2>&1 || true)"
if [[ "${VERSION_OUTPUT}" =~ ^[0-9]+\.[0-9]+ ]]; then
  pass "task-master --version returned '${VERSION_OUTPUT}'"
else
  fail "task-master --version returned '${VERSION_OUTPUT}' (expected a version string)"
fi

# Test 3: Replace description
echo ""
echo "Test 3: Replace description"
restore_backup
task-master update-task --id="${TASK_ID}" --description "test replace" --replace >/dev/null 2>&1
DESC="$(get_field description)"
if [[ "${DESC}" == "test replace" ]]; then
  pass "description is exactly 'test replace' after --replace"
else
  fail "description is '${DESC}' (expected exactly 'test replace')"
fi

# Test 4: Append description
echo ""
echo "Test 4: Append description"
# Task still has "test replace" from test 3
task-master update-task --id="${TASK_ID}" --description "appended text" >/dev/null 2>&1
DESC="$(get_field description)"
if [[ "${DESC}" == *"test replace"* && "${DESC}" == *"appended text"* ]]; then
  pass "description contains both 'test replace' and 'appended text'"
else
  fail "description is '${DESC}' (expected both 'test replace' and 'appended text')"
fi

# Test 5: Agent pattern (update <id> --prompt)
echo ""
echo "Test 5: Agent pattern"
restore_backup
task-master update "${TASK_ID}" --prompt "agent update" >/dev/null 2>&1
DESC="$(get_field description)"
if [[ "${DESC}" == *"agent update"* ]]; then
  pass "description contains 'agent update' after agent-style command"
else
  fail "description is '${DESC}' (expected it to contain 'agent update')"
fi

# Test 6: Title update
echo ""
echo "Test 6: Title update"
restore_backup
task-master update-task --id="${TASK_ID}" --title "Test Title" >/dev/null 2>&1
TITLE="$(get_field title)"
if [[ "${TITLE}" == "Test Title" ]]; then
  pass "title is 'Test Title'"
else
  fail "title is '${TITLE}' (expected 'Test Title')"
fi

# Test 7: Details update
echo ""
echo "Test 7: Details update"
restore_backup
task-master update-task --id "${TASK_ID}" --details "test details" >/dev/null 2>&1
DETAILS="$(get_field details)"
if [[ "${DETAILS}" == *"test details"* ]]; then
  pass "details contains 'test details'"
else
  fail "details is '${DETAILS}' (expected it to contain 'test details')"
fi

# Test 8: Combined update
echo ""
echo "Test 8: Combined update"
restore_backup
task-master update-task --id="${TASK_ID}" --title "Combined" --description "desc" --details "det" --replace >/dev/null 2>&1
TITLE="$(get_field title)"
DESC="$(get_field description)"
DETAILS="$(get_field details)"
if [[ "${TITLE}" == "Combined" && "${DESC}" == "desc" && "${DETAILS}" == "det" ]]; then
  pass "title='Combined', description='desc', details='det' after combined --replace update"
else
  fail "title='${TITLE}', description='${DESC}', details='${DETAILS}' (expected 'Combined', 'desc', 'det')"
fi

# Test 9: Error - no ID
echo ""
echo "Test 9: Error - no ID"
restore_backup
if task-master update-task --description "text" >/dev/null 2>&1; then
  fail "update-task without --id should have exited non-zero"
else
  pass "update-task without --id exited non-zero"
fi

# Test 10: Error - bad ID
echo ""
echo "Test 10: Error - bad ID"
if task-master update-task --id=9999 --description "text" >/dev/null 2>&1; then
  fail "update-task with --id=9999 should have exited non-zero"
else
  pass "update-task with --id=9999 exited non-zero"
fi

# Test 11: Equals syntax for --prompt=
echo ""
echo "Test 11: Equals syntax"
restore_backup
task-master update-task --id="${TASK_ID}" --prompt="equals test" >/dev/null 2>&1
DESC="$(get_field description)"
if [[ "${DESC}" == *"equals test"* ]]; then
  pass "description contains 'equals test' using --prompt= syntax"
else
  fail "description is '${DESC}' (expected it to contain 'equals test')"
fi

# ---------- summary ----------

echo ""
echo "==========================================="
echo "  Results: ${PASS_COUNT}/${TOTAL} passed"
if [[ ${FAIL_COUNT} -gt 0 ]]; then
  echo "  ${FAIL_COUNT} test(s) FAILED"
  echo "==========================================="
  exit 1
else
  echo "  All tests passed!"
  echo "==========================================="
  exit 0
fi
