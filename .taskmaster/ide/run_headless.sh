#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_FILE="${SCRIPT_DIR}/prompt.md"
LOG_FILE="${SCRIPT_DIR}/run.log"

if [[ ! -s "${PROMPT_FILE}" ]]; then
  echo "Error: ${PROMPT_FILE} is empty or missing" >&2
  exit 1
fi

echo "=== Run started: $(date -Iseconds) ===" | tee "${LOG_FILE}"
claude -p "$(cat "${PROMPT_FILE}")" --agent coordinator --dangerously-skip-permissions --output-format stream-json --verbose "$@" 2>&1 | tee -a "${LOG_FILE}"
echo "=== Run finished: $(date -Iseconds) ===" | tee -a "${LOG_FILE}"