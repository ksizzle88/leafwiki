#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# Verification test script for Task 29: Migrate task management to GitHub Issues
# =============================================================================
# Tests all 6 acceptance criteria. Prints PASS/FAIL per criterion.
# Exit 0 if all pass, exit 1 if any fail.
# =============================================================================

PASS_COUNT=0
FAIL_COUNT=0
ERRORS=""

pass() {
  echo "  PASS: $1"
  ((PASS_COUNT++))
}

fail() {
  echo "  FAIL: $1"
  ((FAIL_COUNT++))
  ERRORS="${ERRORS}\n  - $1"
}

section() {
  echo ""
  echo "=== Criterion $1: $2 ==="
}

# ---------------------------------------------------------------------------
# Criterion 1: All 37 tasks exist as GitHub Issues with correct labels/state
# ---------------------------------------------------------------------------
section 1 "All 37 tasks exist as GitHub Issues with correct labels and state"

ISSUES_JSON=$(gh issue list --state all --limit 200 --json number,title,labels,state 2>&1)
if [ $? -ne 0 ]; then
  fail "Failed to fetch issues from GitHub: ${ISSUES_JSON}"
else
  ISSUE_COUNT=$(echo "$ISSUES_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

  if [ "$ISSUE_COUNT" -ge 37 ]; then
    pass "At least 37 issues exist (found ${ISSUE_COUNT})"
  else
    fail "Expected at least 37 issues, found ${ISSUE_COUNT}"
  fi

  # Check that issues with status:done label are CLOSED
  DONE_OPEN=$(echo "$ISSUES_JSON" | python3 -c "
import sys, json
issues = json.load(sys.stdin)
bad = []
for i in issues:
    label_names = [l['name'] for l in i.get('labels', [])]
    if 'status:done' in label_names and i['state'] != 'CLOSED':
        bad.append(f'#{i[\"number\"]} ({i[\"title\"][:40]})')
print(len(bad))
for b in bad[:5]:
    print(f'  {b}')
")
  DONE_OPEN_COUNT=$(echo "$DONE_OPEN" | head -1)
  if [ "$DONE_OPEN_COUNT" -eq 0 ]; then
    pass "All status:done issues are CLOSED"
  else
    fail "Found ${DONE_OPEN_COUNT} issues with status:done that are not CLOSED"
    echo "$DONE_OPEN" | tail -n +2
  fi

  # Check that issues with status:pending or status:in-progress are OPEN
  PENDING_CLOSED=$(echo "$ISSUES_JSON" | python3 -c "
import sys, json
issues = json.load(sys.stdin)
bad = []
for i in issues:
    label_names = [l['name'] for l in i.get('labels', [])]
    if ('status:pending' in label_names or 'status:in-progress' in label_names) and i['state'] != 'OPEN':
        bad.append(f'#{i[\"number\"]} ({i[\"title\"][:40]})')
print(len(bad))
for b in bad[:5]:
    print(f'  {b}')
")
  PENDING_CLOSED_COUNT=$(echo "$PENDING_CLOSED" | head -1)
  if [ "$PENDING_CLOSED_COUNT" -eq 0 ]; then
    pass "All status:pending / status:in-progress issues are OPEN"
  else
    fail "Found ${PENDING_CLOSED_COUNT} pending/in-progress issues that are not OPEN"
    echo "$PENDING_CLOSED" | tail -n +2
  fi

  # Check that every issue has at least one status label and one priority label
  MISSING_LABELS=$(echo "$ISSUES_JSON" | python3 -c "
import sys, json
issues = json.load(sys.stdin)
bad = []
for i in issues:
    label_names = [l['name'] for l in i.get('labels', [])]
    has_status = any(l.startswith('status:') for l in label_names)
    has_priority = any(l.startswith('priority:') for l in label_names)
    if not has_status or not has_priority:
        missing = []
        if not has_status: missing.append('status')
        if not has_priority: missing.append('priority')
        bad.append(f'#{i[\"number\"]}: missing {\" and \".join(missing)}')
print(len(bad))
for b in bad[:5]:
    print(f'  {b}')
")
  MISSING_LABELS_COUNT=$(echo "$MISSING_LABELS" | head -1)
  if [ "$MISSING_LABELS_COUNT" -eq 0 ]; then
    pass "All issues have both status and priority labels"
  else
    fail "Found ${MISSING_LABELS_COUNT} issues missing status and/or priority labels"
    echo "$MISSING_LABELS" | tail -n +2
  fi

  # Spot-check: task 29's title should appear in issues
  TASK29_FOUND=$(echo "$ISSUES_JSON" | python3 -c "
import sys, json
issues = json.load(sys.stdin)
found = any('Migrate task management' in i['title'] for i in issues)
print('yes' if found else 'no')
")
  if [ "$TASK29_FOUND" = "yes" ]; then
    pass "Spot-check: Task 29 title found in issues"
  else
    fail "Spot-check: Task 29 title NOT found in issues"
  fi

  # Spot-check: task 1's title should appear
  TASK1_FOUND=$(echo "$ISSUES_JSON" | python3 -c "
import sys, json
issues = json.load(sys.stdin)
found = any('Merge PR #15' in i['title'] or 'entrypoint backport' in i['title'] for i in issues)
print('yes' if found else 'no')
")
  if [ "$TASK1_FOUND" = "yes" ]; then
    pass "Spot-check: Task 1 title found in issues"
  else
    fail "Spot-check: Task 1 title NOT found in issues"
  fi
fi

# ---------------------------------------------------------------------------
# Criterion 2: Dependencies noted as 'Depends on #X' cross-references
# ---------------------------------------------------------------------------
section 2 "Dependencies are noted as 'Depends on #X' cross-references"

ID_MAP_FILE="/workspace/.taskmaster/migration/id-map.json"

if [ ! -f "$ID_MAP_FILE" ]; then
  fail "id-map.json not found (needed to check dependency cross-refs)"
else
  # Define the known dependencies from tasks.json
  # Task 5 depends on 4, Task 7 depends on 6, Task 8 depends on 6, Task 12 depends on 7 and 11
  DEP_CHECK_RESULT=$(python3 -c "
import json, subprocess, sys

with open('$ID_MAP_FILE') as f:
    id_map = json.load(f)

# Dependencies to check: (task_id, [dep_task_ids])
deps_to_check = [
    ('5', ['4']),
    ('7', ['6']),
    ('8', ['6']),
    ('12', ['7', '11']),
]

failures = []
passes = 0

for task_id, dep_ids in deps_to_check:
    if task_id not in id_map:
        failures.append(f'Task {task_id} not in id-map')
        continue

    issue_num = id_map[task_id]
    # Fetch the issue body
    result = subprocess.run(
        ['gh', 'issue', 'view', str(issue_num), '--json', 'body'],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        failures.append(f'Failed to fetch issue #{issue_num} for task {task_id}')
        continue

    body = json.loads(result.stdout).get('body', '')

    for dep_id in dep_ids:
        if dep_id not in id_map:
            failures.append(f'Dependency task {dep_id} not in id-map')
            continue
        dep_issue_num = id_map[dep_id]
        # Check for 'Depends on #N' pattern (case-insensitive)
        if f'#{dep_issue_num}' in body and 'depend' in body.lower():
            passes += 1
        else:
            failures.append(f'Issue #{issue_num} (task {task_id}) missing \"Depends on #{dep_issue_num}\" for dep task {dep_id}')

print(f'passes={passes}')
print(f'failures={len(failures)}')
for f_msg in failures:
    print(f'  {f_msg}')
")

  DEP_PASSES=$(echo "$DEP_CHECK_RESULT" | grep '^passes=' | cut -d= -f2)
  DEP_FAILURES=$(echo "$DEP_CHECK_RESULT" | grep '^failures=' | cut -d= -f2)

  if [ "$DEP_FAILURES" -eq 0 ]; then
    pass "All checked dependencies have correct cross-references (${DEP_PASSES} refs verified)"
  else
    fail "Missing dependency cross-references (${DEP_FAILURES} failures)"
    echo "$DEP_CHECK_RESULT" | grep '^ '
  fi
fi

# ---------------------------------------------------------------------------
# Criterion 3: Coordinator agent uses 'gh issue' instead of 'task-master'
# ---------------------------------------------------------------------------
section 3 "Coordinator agent uses 'gh issue' commands instead of task-master"

COORD_FILE="/workspace/.claude/agents/coordinator.md"

if [ ! -f "$COORD_FILE" ]; then
  fail "Coordinator agent file not found at ${COORD_FILE}"
else
  TM_COUNT=$(grep -ci 'task-master' "$COORD_FILE" || true)
  GH_COUNT=$(grep -ci 'gh issue' "$COORD_FILE" || true)

  if [ "$TM_COUNT" -eq 0 ]; then
    pass "No 'task-master' references in coordinator.md"
  else
    fail "Found ${TM_COUNT} 'task-master' reference(s) in coordinator.md"
  fi

  if [ "$GH_COUNT" -gt 0 ]; then
    pass "Found ${GH_COUNT} 'gh issue' reference(s) in coordinator.md"
  else
    fail "No 'gh issue' references found in coordinator.md"
  fi
fi

# ---------------------------------------------------------------------------
# Criterion 4: All slash commands use 'gh issue' commands
# ---------------------------------------------------------------------------
section 4 "Slash commands use 'gh issue' instead of task-master"

COMMANDS_DIR="/workspace/.claude/commands"
SLASH_COMMANDS=("do-task.md" "flesh-out.md" "plan.md")

for cmd_file in "${SLASH_COMMANDS[@]}"; do
  CMD_PATH="${COMMANDS_DIR}/${cmd_file}"
  if [ ! -f "$CMD_PATH" ]; then
    fail "Slash command file not found: ${cmd_file}"
    continue
  fi

  TM_COUNT=$(grep -ci 'task-master' "$CMD_PATH" || true)
  GH_COUNT=$(grep -ci 'gh issue' "$CMD_PATH" || true)

  if [ "$TM_COUNT" -eq 0 ]; then
    pass "${cmd_file}: no 'task-master' references"
  else
    fail "${cmd_file}: found ${TM_COUNT} 'task-master' reference(s)"
  fi

  if [ "$GH_COUNT" -gt 0 ]; then
    pass "${cmd_file}: has 'gh issue' references"
  else
    fail "${cmd_file}: no 'gh issue' references found"
  fi
done

# ---------------------------------------------------------------------------
# Criterion 5: All agent definitions have updated tool permissions for 'gh'
# ---------------------------------------------------------------------------
section 5 "Agent definitions have updated tool permissions for gh"

AGENTS_DIR="/workspace/.claude/agents"

for agent_file in "$AGENTS_DIR"/*.md; do
  agent_name=$(basename "$agent_file")

  # Check for old task-master tool permission patterns
  TM_TOOL=$(grep -ci 'Bash(task-master' "$agent_file" || true)
  # Check for new gh tool permission patterns (gh issue or just gh)
  GH_TOOL=$(grep -cE 'Bash\(gh (issue|api|pr)' "$agent_file" || true)
  # Also check broader gh permission
  GH_BROAD=$(grep -cE 'Bash\(gh ' "$agent_file" || true)

  if [ "$TM_TOOL" -gt 0 ]; then
    fail "${agent_name}: still has Bash(task-master ...) tool permission(s)"
  else
    pass "${agent_name}: no Bash(task-master ...) tool permissions"
  fi

  if [ "$GH_TOOL" -gt 0 ] || [ "$GH_BROAD" -gt 0 ]; then
    pass "${agent_name}: has Bash(gh ...) tool permission(s)"
  else
    fail "${agent_name}: no Bash(gh ...) tool permissions found"
  fi
done

# ---------------------------------------------------------------------------
# Criterion 6: Migration mapping file exists with correct structure
# ---------------------------------------------------------------------------
section 6 "Migration mapping file at .taskmaster/migration/id-map.json"

if [ ! -f "$ID_MAP_FILE" ]; then
  fail "id-map.json does not exist at ${ID_MAP_FILE}"
else
  pass "id-map.json exists"

  # Valid JSON check
  if python3 -c "import json; json.load(open('$ID_MAP_FILE'))" 2>/dev/null; then
    pass "id-map.json is valid JSON"
  else
    fail "id-map.json is not valid JSON"
  fi

  # Check entry count
  ENTRY_COUNT=$(python3 -c "
import json
with open('$ID_MAP_FILE') as f:
    data = json.load(f)
print(len(data))
" 2>/dev/null || echo "0")

  if [ "$ENTRY_COUNT" -eq 37 ]; then
    pass "id-map.json has exactly 37 entries"
  else
    fail "id-map.json has ${ENTRY_COUNT} entries (expected 37)"
  fi

  # Check structure: keys are strings, values are integers
  STRUCTURE_CHECK=$(python3 -c "
import json
with open('$ID_MAP_FILE') as f:
    data = json.load(f)
bad = []
for k, v in data.items():
    if not isinstance(k, str):
        bad.append(f'Key {k} is not a string')
    if not isinstance(v, int):
        bad.append(f'Value for key {k} is not an integer: {v} ({type(v).__name__})')
print(len(bad))
for b in bad[:5]:
    print(f'  {b}')
" 2>/dev/null || echo "error")

  STRUCTURE_BAD=$(echo "$STRUCTURE_CHECK" | head -1)
  if [ "$STRUCTURE_BAD" = "0" ]; then
    pass "id-map.json structure correct (string keys -> integer values)"
  else
    fail "id-map.json structure issues: ${STRUCTURE_BAD} problems"
    echo "$STRUCTURE_CHECK" | tail -n +2
  fi
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==========================================="
echo "  RESULTS: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "==========================================="

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
  echo ""
  exit 1
else
  echo ""
  echo "All acceptance criteria verified successfully."
  exit 0
fi
