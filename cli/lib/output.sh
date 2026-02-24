#!/bin/bash
# Output formatting utilities for Claudio CLI

#######################################
# Print a section header
# Globals:
#   BLUE, NC
# Arguments:
#   Header text
# Outputs:
#   Formatted header to stdout
#######################################
print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   $*${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

#######################################
# Print a check result
# Globals:
#   GREEN, RED, YELLOW, NC
# Arguments:
#   $1 - Check name
#   $2 - Status (pass|fail|warn)
#   $3 - Details (optional)
# Outputs:
#   Formatted check result to stdout
#######################################
print_check() {
    local name="$1"
    local status="$2"
    local details="${3:-}"

    echo -n "${name}: "

    case "${status}" in
        pass)
            echo -e "${GREEN}✓${NC} ${details}"
            ;;
        fail)
            echo -e "${RED}✗${NC} ${details}"
            ;;
        warn)
            echo -e "${YELLOW}⚠${NC} ${details}"
            ;;
        *)
            echo "${details}"
            ;;
    esac
}

#######################################
# Print usage information
# Arguments:
#   Command name
#   Usage pattern
# Outputs:
#   Formatted usage to stdout
#######################################
print_usage() {
    local command="$1"
    local pattern="$2"

    echo "Usage: claudio ${command} ${pattern}"
}

#######################################
# Print concise help with examples
# Should be used when command fails or runs without args
# Arguments:
#   Command name
#   Description
#   Usage pattern
#   Example commands (multiple args)
# Outputs:
#   Formatted concise help to stdout
#######################################
print_concise_help() {
    local command="$1"
    local description="$2"
    local usage="$3"
    shift 3

    echo "Usage: claudio ${command} ${usage}"
    echo ""
    echo "${description}"
    echo ""

    if [[ $# -gt 0 ]]; then
        echo "Examples:"
        for example in "$@"; do
            echo "  ${example}"
        done
        echo ""
    fi

    echo "Use 'claudio ${command} --help' for more information."
}

#######################################
# Print extensive help documentation
# Should be used with --help flag
# Arguments:
#   Command name
#   Description
#   Usage pattern
#   Options text (multi-line)
#   Examples text (multi-line)
#   See also text (optional)
# Outputs:
#   Formatted extensive help to stdout
#######################################
print_extensive_help() {
    local command="$1"
    local description="$2"
    local usage="$3"
    local options="$4"
    local examples="$5"
    local see_also="${6:-}"

    cat <<EOF
claudio ${command} - ${description}

USAGE
  claudio ${command} ${usage}

DESCRIPTION
  ${description}

OPTIONS
${options}

EXAMPLES
${examples}

EOF

    if [[ -n "${see_also}" ]]; then
        cat <<EOF
SEE ALSO
${see_also}

EOF
    fi

    cat <<EOF
For more information, visit:
  https://github.com/ksizzle88/claudio
EOF
}

#######################################
# Print JSON output
# Arguments:
#   JSON string
# Outputs:
#   Pretty-printed JSON to stdout
#######################################
print_json() {
    if has_command jq; then
        echo "$1" | jq .
    else
        echo "$1"
    fi
}

#######################################
# Start a spinner for long operations
# Globals:
#   SPINNER_PID (set)
# Arguments:
#   Message to display
#######################################
start_spinner() {
    local message="$1"

    # Only show spinner if output is to a terminal
    if [[ ! -t 1 ]]; then
        echo "${message}..."
        return
    fi

    (
        local spin='-\|/'
        local i=0
        while true; do
            i=$(( (i+1) %4 ))
            printf "\r${message}... ${spin:$i:1}"
            sleep 0.1
        done
    ) &

    SPINNER_PID=$!
}

#######################################
# Stop the spinner
# Globals:
#   SPINNER_PID (read and unset)
#######################################
stop_spinner() {
    if [[ -n "${SPINNER_PID:-}" ]]; then
        kill "${SPINNER_PID}" 2>/dev/null || true
        wait "${SPINNER_PID}" 2>/dev/null || true
        unset SPINNER_PID
        printf "\r"
    fi
}

#######################################
# Print a table row
# Arguments:
#   Column values (variable number)
# Outputs:
#   Formatted table row
#######################################
print_table_row() {
    local col1="${1:-}"
    local col2="${2:-}"
    local col3="${3:-}"

    printf "  %-30s %-15s %s\n" "${col1}" "${col2}" "${col3}"
}
