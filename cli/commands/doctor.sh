#!/bin/bash
# claudio doctor - Diagnose common issues and suggest fixes

#######################################
# Show concise help for doctor command
#######################################
show_doctor_concise_help() {
    print_concise_help "doctor" \
        "Diagnose common Claudio setup issues and suggest fixes." \
        "[options]" \
        "claudio doctor" \
        "claudio doctor --fix"
}

#######################################
# Show extensive help for doctor command
#######################################
show_doctor_help() {
    local options
    local examples

    options=$(cat <<'EOF'
  --fix            Attempt to automatically fix detected issues
  --verbose, -v    Show detailed diagnostic information
  --no-color       Disable colored output
  -h, --help       Show this help message
EOF
)

    examples=$(cat <<'EOF'
  # Diagnose issues
  claudio doctor

  # Diagnose and attempt automatic fixes
  claudio doctor --fix

  # Verbose diagnostic output
  claudio doctor --verbose
EOF
)

    local see_also
    see_also=$(cat <<'EOF'
  claudio verify    Verify Claudio setup
  claudio version   Show version information
EOF
)

    print_extensive_help "doctor" \
        "Diagnose common Claudio setup issues and suggest fixes" \
        "[options]" \
        "${options}" \
        "${examples}" \
        "${see_also}"
}

#######################################
# Diagnose and suggest fixes
# Globals:
#   AUTO_FIX, VERBOSE
# Returns:
#   0 if no issues, 1 if issues found
#######################################
run_diagnostics() {
    local issues_found=0

    # Issue 1: Claude CLI not installed
    if ! has_command claude; then
        warn "Claude CLI is not installed"
        echo "  Fix: Run 'npm install -g @anthropic-ai/claude-code'" >&2
        ((issues_found++))
    fi

    # Issue 2: Claude not authenticated
    local creds_found=false
    for creds_path in \
        "${CLAUDE_CONFIG_DIR:-}/.credentials.json" \
        "$(get_home_dir)/.claude/.credentials.json" \
        "$(get_home_dir)/.claude-shared-auth/.credentials.json"; do

        if [[ -f "${creds_path}" ]]; then
            creds_found=true
            break
        fi
    done

    if ! ${creds_found}; then
        warn "Claude is not authenticated"
        echo "  Fix: Run 'claude login' to authenticate" >&2
        ((issues_found++))
    fi

    # Issue 3: Git not configured
    if ! git config --global user.name >/dev/null 2>&1 || \
       ! git config --global user.email >/dev/null 2>&1; then
        warn "Git user configuration is incomplete"
        echo "  Fix: Configure git with:" >&2
        echo "    git config --global user.name 'Your Name'" >&2
        echo "    git config --global user.email 'your.email@example.com'" >&2
        ((issues_found++))
    fi

    # Issue 4: GitHub CLI not authenticated
    if has_command gh && ! gh auth status >/dev/null 2>&1; then
        warn "GitHub CLI is not authenticated"
        echo "  Fix: Run 'gh auth login' to authenticate" >&2
        ((issues_found++))
    fi

    # Issue 5: Shared volumes not mounted
    local home_dir
    home_dir=$(get_home_dir)

    local missing_volumes=()
    for vol_path in \
        "${home_dir}/.claude-shared-auth" \
        "${home_dir}/.config/gh-shared" \
        "${home_dir}/.gitconfig-shared" \
        "${home_dir}/.claude-shared-plugins" \
        "${home_dir}/.mcp-shared"; do

        if [[ ! -d "${vol_path}" ]]; then
            missing_volumes+=("$(basename "${vol_path}")")
        fi
    done

    if [[ ${#missing_volumes[@]} -gt 0 ]]; then
        warn "Some shared volumes are not mounted"
        echo "  Missing: ${missing_volumes[*]}" >&2
        echo "  Fix: Rebuild container with proper volume mounts" >&2
        echo "       See: .devcontainer/templates/ for integration guides" >&2
        ((issues_found++))
    fi

    # Issue 6: Not running in container
    if ! in_container; then
        info "Not running inside a container"
        echo "  Note: Claudio is designed to run in a devcontainer" >&2
        echo "        Some features may not work correctly outside containers" >&2
    fi

    # Issue 7: CLAUDE_CONFIG_DIR not set
    if [[ -z "${CLAUDE_CONFIG_DIR:-}" ]]; then
        warn "CLAUDE_CONFIG_DIR environment variable is not set"
        echo "  Fix: Add to your shell profile:" >&2
        echo "    export CLAUDE_CONFIG_DIR=\"${home_dir}/.claude\"" >&2
        ((issues_found++))
    fi

    # Issue 8: Node.js not installed
    if ! has_command node; then
        warn "Node.js is not installed"
        echo "  Fix: Install Node.js from https://nodejs.org/" >&2
        ((issues_found++))
    fi

    # Summary
    echo ""
    info "========================================"

    if [[ ${issues_found} -eq 0 ]]; then
        success "✓ No issues detected!"
        echo ""
        log "Your Claudio setup looks good."
        log "Run 'claudio verify' for detailed verification."
        return 0
    else
        error "Found ${issues_found} issue(s)"
        echo ""
        log "Review the suggestions above to fix these issues."
        log "Run 'claudio doctor --fix' to attempt automatic fixes (where possible)."
        return 1
    fi
}

#######################################
# Main doctor command function
# Arguments:
#   Command arguments
# Returns:
#   0 if no issues, 1 if issues found
#######################################
cmd_doctor() {
    # Parse arguments
    local show_help=false
    local auto_fix=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help=true
                shift
                ;;
            --fix)
                auto_fix=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --no-color)
                NO_COLOR=1
                shift
                ;;
            *)
                error "Unknown option: $1"
                echo "" >&2
                show_doctor_concise_help >&2
                return 1
                ;;
        esac
    done

    # Show help if requested
    if [[ "${show_help}" == "true" ]]; then
        show_doctor_help
        return 0
    fi

    # Run diagnostics
    print_header "Claudio Setup Diagnostics"

    if [[ "${auto_fix}" == "true" ]]; then
        info "Auto-fix mode enabled (future feature)"
        echo ""
    fi

    run_diagnostics
}
