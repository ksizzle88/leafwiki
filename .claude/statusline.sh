#!/bin/bash
# Claudio status line for Claude Code
# Receives JSON session data via stdin, outputs status bar

input=$(cat)

# Parse fields
MODEL=$(echo "$input" | jq -r '.model.display_name // "unknown"')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
COST=$(echo "$input" | jq -r '.cost.total // 0')
PROJECT=$(echo "$input" | jq -r '.session.project_name // empty')

# Context bar
BAR_WIDTH=10
FILLED=$((PCT * BAR_WIDTH / 100))
EMPTY=$((BAR_WIDTH - FILLED))
BAR=""
[ "$FILLED" -gt 0 ] && BAR=$(printf "%${FILLED}s" | tr ' ' '#')
[ "$EMPTY" -gt 0 ] && BAR="${BAR}$(printf "%${EMPTY}s" | tr ' ' '-')"

# Color context bar based on usage
if [ "$PCT" -ge 80 ]; then
    BAR="\033[31m${BAR}\033[0m"  # red
elif [ "$PCT" -ge 50 ]; then
    BAR="\033[33m${BAR}\033[0m"  # yellow
else
    BAR="\033[32m${BAR}\033[0m"  # green
fi

# Build output
OUT="${MODEL} [${BAR}] ${PCT}%"
[ -n "$COST" ] && [ "$COST" != "0" ] && OUT="${OUT} | \$${COST}"
[ -n "$PROJECT" ] && OUT="${OUT} | ${PROJECT}"

echo -e "$OUT"
