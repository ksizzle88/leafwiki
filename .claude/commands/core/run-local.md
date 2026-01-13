# /run-local - Create Simple Reviewable Scripts

## Purpose

When the user asks to "run something", "get values", or perform automated tasks, create a simple bash script they can review and execute. This promotes transparency, repeatability, and debugging.

## Core Principles

1. **Create scripts instead of running commands directly** - Makes operations reviewable and repeatable
2. **Never kill the user's terminal** - Scripts run in interactive shells, must handle errors gracefully
3. **Log everything** - Capture all output to `.ansi` files for debugging

**CRITICAL**: Never use `set -e`, `set -u`, or `set -o pipefail` - these will kill the user's terminal on errors.

## Script Template

```bash
#!/bin/bash
#
# [Clear description of what this script does]
#
# Usage: [How to run it]
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILE_NAME="$(basename "${BASH_SOURCE[0]}")"
LOG_FILE="$SCRIPT_DIR/$FILE_NAME-out.ansi"

# Track errors but continue execution
ERRORS=0

rm -f "$LOG_FILE"

echo "=== [Script Purpose] ===" | tee "$LOG_FILE"
echo "Started at: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Step 1: [First action]
echo "=== Step 1: [Action description] ===" | tee -a "$LOG_FILE"
if ! [commands] 2>&1 | tee -a "$LOG_FILE"; then
  echo "WARNING: Step 1 failed (continuing...)" | tee -a "$LOG_FILE"
  ((ERRORS++))
fi
echo "" | tee -a "$LOG_FILE"

# Step 2: [Second action]
echo "=== Step 2: [Action description] ===" | tee -a "$LOG_FILE"
if ! [commands] 2>&1 | tee -a "$LOG_FILE"; then
  echo "WARNING: Step 2 failed (continuing...)" | tee -a "$LOG_FILE"
  ((ERRORS++))
fi
echo "" | tee -a "$LOG_FILE"

echo "Completed at: $(date)" | tee -a "$LOG_FILE"
echo "===========================================" | tee -a "$LOG_FILE"

if [ $ERRORS -gt 0 ]; then
  echo "⚠️  Completed with $ERRORS error(s) - see log above" | tee -a "$LOG_FILE"
  return 1 2>/dev/null || exit 1
else
  echo "✓ Completed successfully" | tee -a "$LOG_FILE"
  return 0 2>/dev/null || exit 0
fi
```

## Key Elements

1. **Logging setup**: `LOG_FILE="$SCRIPT_DIR/$FILE_NAME-out.ansi"`
2. **Error tracking**: `ERRORS=0` counter, increment on failures
3. **Labeled steps**: Clear `=== Step N: Description ===` headers
4. **Capture all output**: `2>&1 | tee -a "$LOG_FILE"`
5. **Continue on errors**: Wrap steps in `if ! ... ; then` blocks
6. **Summary at end**: Report error count, return non-zero if failures

## File Location

Place scripts in `.dev/claude/`:
- `.dev/` is gitignored (safe for local automation)
- `claude/` subfolder keeps things organized
- Creates log files alongside scripts (`.sh-out.ansi`)

## Workflow

1. **Create script** in `.dev/claude/` with descriptive name
2. **Make executable**: `chmod +x .dev/claude/script-name.sh`
3. **Show user** the script content for review
4. **Explain** what each step does
5. **Execute** if approved: `.dev/claude/script-name.sh`
6. **Review log** together: `.dev/claude/script-name.sh-out.ansi`

## Example

User: "Check Docker container status"

Create `.dev/claude/docker-status.sh`:
```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/$(basename "$0")-out.ansi"
ERRORS=0

rm -f "$LOG_FILE"
echo "=== Docker Container Status ===" | tee "$LOG_FILE"

echo "=== Step 1: Running containers ===" | tee -a "$LOG_FILE"
if ! docker ps 2>&1 | tee -a "$LOG_FILE"; then
  echo "WARNING: docker ps failed" | tee -a "$LOG_FILE"
  ((ERRORS++))
fi

echo "=== Step 2: Container stats ===" | tee -a "$LOG_FILE"
if ! docker stats --no-stream 2>&1 | tee -a "$LOG_FILE"; then
  echo "WARNING: docker stats failed" | tee -a "$LOG_FILE"
  ((ERRORS++))
fi

[ $ERRORS -gt 0 ] && echo "⚠️  $ERRORS errors" || echo "✓ Success"
```

Then respond: "I've created [.dev/claude/docker-status.sh](.dev/claude/docker-status.sh). Would you like me to run it?"

## Remember

- Keep scripts simple and focused
- Log everything with `tee`
- Never exit on errors - track and continue
- Show user script before executing
- Use descriptive names and step labels
