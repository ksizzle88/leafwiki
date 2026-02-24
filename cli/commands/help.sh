#!/bin/bash
# claudio help - Show help information

#######################################
# Show main Claudio help
#######################################
show_main_help() {
    cat <<EOF
${BOLD}claudio${NC} - Claudio development environment CLI

${BOLD}USAGE${NC}
  claudio <command> [options]

${BOLD}COMMANDS${NC}
  ${BOLD}verify${NC}    Verify Claudio setup and configuration
  ${BOLD}version${NC}   Show version information for Claudio and tools
  ${BOLD}doctor${NC}    Diagnose common issues and suggest fixes
  ${BOLD}help${NC}      Show help for commands

${BOLD}OPTIONS${NC}
  -h, --help       Show this help message
  -v, --version    Show version information

${BOLD}EXAMPLES${NC}
  # Verify your setup
  claudio verify

  # Show version information
  claudio version

  # Diagnose issues
  claudio doctor

  # Get help for a specific command
  claudio help verify
  claudio verify --help

${BOLD}GETTING STARTED${NC}
  1. Verify your setup:     claudio verify
  2. Fix any issues:        claudio doctor
  3. Check versions:        claudio version

${BOLD}LEARN MORE${NC}
  Documentation:  https://github.com/ksizzle88/claudio
  Report issues:  https://github.com/ksizzle88/claudio/issues

Run 'claudio help <command>' for more information about a specific command.
EOF
}

#######################################
# Show help for a specific command
# Arguments:
#   $1 - Command name
# Returns:
#   0 on success, 1 if command not found
#######################################
show_command_help() {
    local command="$1"

    case "${command}" in
        verify)
            # shellcheck source=commands/verify.sh
            source "${SCRIPT_DIR}/commands/verify.sh"
            show_verify_help
            ;;
        version)
            # shellcheck source=commands/version.sh
            source "${SCRIPT_DIR}/commands/version.sh"
            show_version_help
            ;;
        doctor)
            # shellcheck source=commands/doctor.sh
            source "${SCRIPT_DIR}/commands/doctor.sh"
            show_doctor_help
            ;;
        help)
            show_main_help
            ;;
        "")
            show_main_help
            ;;
        *)
            error "Unknown command: ${command}"
            echo "" >&2
            echo "Run 'claudio help' for available commands." >&2
            return 1
            ;;
    esac

    return 0
}

#######################################
# Main help command function
# Arguments:
#   Optional command name
# Returns:
#   0 on success, 1 if error
#######################################
cmd_help() {
    local command="${1:-}"

    # If specific command requested, show its help
    if [[ -n "${command}" ]]; then
        show_command_help "${command}"
    else
        # Show main help
        show_main_help
    fi
}
