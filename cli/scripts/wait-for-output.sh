#!/usr/bin/env bash
set -euo pipefail

# wait-for-output: Block until an output file is created or updated.
#
# Usage: wait-for-output <out-file> [--timeout <seconds>] [--since <epoch>]
#
#   out-file     Path to the output file to watch
#   --timeout    Max seconds to wait (default: 300)
#   --since      Only succeed if file mtime is after this epoch timestamp
#                (prevents reading stale output from a previous run)
#
# Exit codes:
#   0 - File is ready (new or updated)
#   1 - Timed out waiting
#   2 - Usage error

usage() {
    sed -n '3,12p' "$0" | sed 's/^# \?//'
    exit "${1:-0}"
}

out_file=""
timeout_secs=300
since_epoch=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout) timeout_secs="$2"; shift 2 ;;
        --since)   since_epoch="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        -*)        echo "Unknown option: $1" >&2; usage 2 ;;
        *)
            if [[ -z "$out_file" ]]; then
                out_file="$1"
            else
                echo "Error: unexpected argument '$1'" >&2; usage 2
            fi
            shift
            ;;
    esac
done

if [[ -z "$out_file" ]]; then
    echo "Error: out-file is required" >&2
    usage 2
fi

elapsed=0
interval=2

while (( elapsed < timeout_secs )); do
    if [[ -f "$out_file" ]]; then
        file_mtime=$(stat -c %Y "$out_file" 2>/dev/null || echo 0)
        if (( file_mtime > since_epoch )); then
            echo "ready"
            exit 0
        fi
    fi
    sleep "$interval"
    (( elapsed += interval ))
done

echo "timeout"
exit 1
