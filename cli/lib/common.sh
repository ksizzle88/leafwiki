#!/bin/bash
# Common utilities for Claudio CLI
# Sourced by all command scripts

# Claudio version
readonly CLAUDIO_VERSION="1.0.0"
readonly CLAUDIO_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Color codes (disabled if not a TTY or NO_COLOR is set)
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly RED='\033[0;31m'
    readonly BLUE='\033[0;34m'
    readonly BOLD='\033[1m'
    readonly NC='\033[0m'  # No Color
else
    readonly GREEN=''
    readonly YELLOW=''
    readonly RED=''
    readonly BLUE=''
    readonly BOLD=''
    readonly NC=''
fi

#######################################
# Print error message to stderr
# Globals:
#   RED, NC
# Arguments:
#   Error message
# Outputs:
#   Formatted error to stderr
#######################################
error() {
    echo -e "${RED}Error: $*${NC}" >&2
}

#######################################
# Print warning message to stderr
# Globals:
#   YELLOW, NC
# Arguments:
#   Warning message
# Outputs:
#   Formatted warning to stderr
#######################################
warn() {
    echo -e "${YELLOW}Warning: $*${NC}" >&2
}

#######################################
# Print success message to stdout
# Globals:
#   GREEN, NC
# Arguments:
#   Success message
# Outputs:
#   Formatted success to stdout
#######################################
success() {
    echo -e "${GREEN}$*${NC}"
}

#######################################
# Print info message to stdout
# Globals:
#   BLUE, NC
# Arguments:
#   Info message
# Outputs:
#   Formatted info to stdout
#######################################
info() {
    echo -e "${BLUE}$*${NC}"
}

#######################################
# Die with error message and exit code
# Globals:
#   None
# Arguments:
#   Exit code
#   Error message
# Outputs:
#   Error to stderr
# Returns:
#   Exits with provided code
#######################################
die() {
    local exit_code="$1"
    shift
    error "$*"
    exit "${exit_code}"
}

#######################################
# Check if command exists
# Arguments:
#   Command name
# Returns:
#   0 if command exists, 1 otherwise
#######################################
has_command() {
    command -v "$1" >/dev/null 2>&1
}

#######################################
# Get user's home directory
# Handles root vs non-root users
# Outputs:
#   Home directory path
#######################################
get_home_dir() {
    local current_user="${USER:-$(id -un 2>/dev/null || echo "")}"

    if [[ "${current_user}" == "root" ]]; then
        echo "/root"
    else
        echo "${HOME:-/home/dev}"
    fi
}

#######################################
# Check if running in a container
# Returns:
#   0 if in container, 1 otherwise
#######################################
in_container() {
    [[ -f /.dockerenv ]] || [[ -f /run/.containerenv ]]
}

#######################################
# Parse common flags from arguments
# Sets global variables:
#   QUIET, VERBOSE, JSON_OUTPUT, NO_COLOR_FLAG
# Arguments:
#   All command arguments
# Returns:
#   Remaining arguments (non-flag)
#######################################
parse_common_flags() {
    QUIET="${QUIET:-false}"
    VERBOSE="${VERBOSE:-false}"
    JSON_OUTPUT="${JSON_OUTPUT:-false}"
    NO_COLOR_FLAG="${NO_COLOR_FLAG:-false}"

    local args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --no-color)
                NO_COLOR_FLAG=true
                NO_COLOR=1
                shift
                ;;
            -h|--help)
                # Help flag handled by individual commands
                args+=("$1")
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Return remaining args
    printf '%s\n' "${args[@]}"
}

#######################################
# Print verbose message (only if VERBOSE=true)
# Globals:
#   VERBOSE
# Arguments:
#   Message
# Outputs:
#   Message to stdout if verbose mode enabled
#######################################
verbose() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo "$*"
    fi
}

#######################################
# Print message (suppressed if QUIET=true)
# Globals:
#   QUIET
# Arguments:
#   Message
# Outputs:
#   Message to stdout unless quiet mode enabled
#######################################
log() {
    if [[ "${QUIET:-false}" != "true" ]]; then
        echo "$*"
    fi
}
