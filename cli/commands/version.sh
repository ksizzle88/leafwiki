#!/bin/bash
# claudio version - Show version information

#######################################
# Show concise help for version command
#######################################
show_version_concise_help() {
    print_concise_help "version" \
        "Show version information for Claudio and installed tools." \
        "[options]" \
        "claudio version" \
        "claudio version --json"
}

#######################################
# Show extensive help for version command
#######################################
show_version_help() {
    local options
    local examples

    options=$(cat <<'EOF'
  --json           Output version info as JSON
  --no-color       Disable colored output
  -h, --help       Show this help message
EOF
)

    examples=$(cat <<'EOF'
  # Show all version information
  claudio version

  # JSON output for scripting
  claudio version --json
EOF
)

    print_extensive_help "version" \
        "Show version information for Claudio and installed tools" \
        "[options]" \
        "${options}" \
        "${examples}"
}

#######################################
# Get version of a command
# Arguments:
#   $1 - Command name
#   $2 - Version flag (optional, defaults to --version)
# Outputs:
#   Version string or "not installed"
#######################################
get_version() {
    local cmd="$1"
    local version_flag="${2:---version}"

    if has_command "${cmd}"; then
        "${cmd}" "${version_flag}" 2>/dev/null | head -n1 || echo "unknown"
    else
        echo "not installed"
    fi
}

#######################################
# Display version information
# Globals:
#   JSON_OUTPUT, CLAUDIO_VERSION
# Returns:
#   0 always
#######################################
show_version_info() {
    if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
        # JSON output
        local json
        json=$(cat <<EOF
{
  "claudio": "${CLAUDIO_VERSION}",
  "claude": "$(get_version claude)",
  "node": "$(get_version node)",
  "python": "$(get_version python || get_version python3)",
  "gh": "$(get_version gh | awk '{print $3}')",
  "git": "$(get_version git | awk '{print $3}')",
  "docker": "$(get_version docker | awk '{print $3}')"
}
EOF
)
        print_json "${json}"
    else
        # Human-readable output
        print_header "Claudio Version Information"

        echo "Claudio Platform:"
        print_table_row "  Claudio" "${CLAUDIO_VERSION}" ""
        echo ""

        echo "Development Tools:"
        print_table_row "  Claude CLI" "$(get_version claude)" ""
        print_table_row "  Node.js" "$(get_version node)" ""
        print_table_row "  Python" "$(get_version python || get_version python3)" ""
        print_table_row "  Git" "$(get_version git | awk '{print $3}')" ""
        print_table_row "  GitHub CLI" "$(get_version gh | awk '{print $3}')" ""

        echo ""
        echo "Container Tools:"
        print_table_row "  Docker" "$(get_version docker | awk '{print $3}')" ""

        if in_container; then
            echo ""
            info "Running inside container: Yes"
        fi

        echo ""
        log "For detailed setup verification, run: claudio verify"
    fi

    return 0
}

#######################################
# Main version command function
# Arguments:
#   Command arguments
# Returns:
#   0 always
#######################################
cmd_version() {
    # Parse arguments
    local show_help=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help=true
                shift
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --no-color)
                NO_COLOR=1
                shift
                ;;
            *)
                error "Unknown option: $1"
                echo "" >&2
                show_version_concise_help >&2
                return 1
                ;;
        esac
    done

    # Show help if requested
    if [[ "${show_help}" == "true" ]]; then
        show_version_help
        return 0
    fi

    # Show version information
    show_version_info
}
