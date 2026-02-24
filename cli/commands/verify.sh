#!/bin/bash
# claudio verify - Verify Claudio setup and configuration

#######################################
# Show concise help for verify command
#######################################
show_verify_concise_help() {
    print_concise_help "verify" \
        "Verify your Claudio development environment setup." \
        "[options]" \
        "claudio verify" \
        "claudio verify --json" \
        "claudio verify --quiet"
}

#######################################
# Show extensive help for verify command
#######################################
show_verify_help() {
    local options
    local examples

    options=$(cat <<'EOF'
  --json           Output results as JSON for scripting
  --quiet, -q      Only show errors, suppress warnings
  --verbose, -v    Show detailed diagnostic information
  --no-color       Disable colored output
  -h, --help       Show this help message
EOF
)

    examples=$(cat <<'EOF'
  # Basic verification
  claudio verify

  # JSON output for CI/CD
  claudio verify --json

  # Quiet mode - only show errors
  claudio verify --quiet

  # Verbose mode with detailed output
  claudio verify --verbose
EOF
)

    local see_also
    see_also=$(cat <<'EOF'
  claudio doctor    Diagnose and fix common issues
  claudio version   Show version information
EOF
)

    print_extensive_help "verify" \
        "Verify Claudio development environment setup" \
        "[options]" \
        "${options}" \
        "${examples}" \
        "${see_also}"
}

#######################################
# Run verification checks
# Globals:
#   JSON_OUTPUT, QUIET, VERBOSE
# Returns:
#   0 if all checks pass, 1 if errors, 2 if warnings
#######################################
run_verification() {
    local warnings=0
    local errors=0
    local checks_data=()

    # Check 1: Claude CLI
    if has_command claude; then
        local version
        version=$(claude --version 2>/dev/null || echo "unknown")
        print_check "Claude CLI" "pass" "${version}"
        checks_data+=("claude_cli:pass:${version}")
    else
        print_check "Claude CLI" "fail" "Not found"
        ((errors++))
        checks_data+=("claude_cli:fail:Not found")
    fi

    # Check 2: CLAUDE_CONFIG_DIR
    if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
        print_check "CLAUDE_CONFIG_DIR" "pass" "${CLAUDE_CONFIG_DIR}"
        checks_data+=("claude_config_dir:pass:${CLAUDE_CONFIG_DIR}")
    else
        local expected
        expected="$(get_home_dir)/.claude"
        print_check "CLAUDE_CONFIG_DIR" "warn" "Not set (expected: ${expected})"
        ((warnings++))
        checks_data+=("claude_config_dir:warn:Not set")
    fi

    # Check 3: Claude authentication
    local creds_found=false
    if [[ -f "${CLAUDE_CONFIG_DIR:-}/.credentials.json" ]]; then
        print_check "Claude authentication" "pass" "Authenticated (local)"
        creds_found=true
        checks_data+=("claude_auth:pass:local")
    elif [[ -f "$(get_home_dir)/.claude/.credentials.json" ]]; then
        print_check "Claude authentication" "pass" "Authenticated (home)"
        creds_found=true
        checks_data+=("claude_auth:pass:home")
    elif [[ -f "$(get_home_dir)/.claude-shared-auth/.credentials.json" ]]; then
        print_check "Claude authentication" "pass" "Authenticated (shared)"
        creds_found=true
        checks_data+=("claude_auth:pass:shared")
    else
        print_check "Claude authentication" "warn" "Not authenticated (run 'claude login')"
        ((warnings++))
        checks_data+=("claude_auth:warn:Not authenticated")
    fi

    # Check 4: Git configuration
    local git_name git_email
    git_name=$(git config --global user.name 2>/dev/null || echo "")
    git_email=$(git config --global user.email 2>/dev/null || echo "")

    if [[ -n "${git_name}" ]] && [[ -n "${git_email}" ]]; then
        print_check "Git configuration" "pass" "${git_name} <${git_email}>"
        checks_data+=("git_config:pass:${git_name} <${git_email}>")
    else
        print_check "Git configuration" "warn" "Not fully configured"
        [[ -z "${git_name}" ]] && log "    Missing: user.name"
        [[ -z "${git_email}" ]] && log "    Missing: user.email"
        ((warnings++))
        checks_data+=("git_config:warn:Not fully configured")
    fi

    # Check 5: GitHub CLI
    if has_command gh; then
        local gh_version
        gh_version=$(gh --version 2>/dev/null | head -n1)
        if gh auth status >/dev/null 2>&1; then
            print_check "GitHub CLI" "pass" "${gh_version} - Authenticated"
            checks_data+=("gh_cli:pass:${gh_version}")
        else
            print_check "GitHub CLI" "warn" "${gh_version} - Not authenticated"
            ((warnings++))
            checks_data+=("gh_cli:warn:Not authenticated")
        fi
    else
        print_check "GitHub CLI" "fail" "Not found"
        ((errors++))
        checks_data+=("gh_cli:fail:Not found")
    fi

    # Check 6: Node.js
    if has_command node; then
        local node_version
        node_version=$(node --version 2>/dev/null)
        print_check "Node.js" "pass" "${node_version}"
        checks_data+=("nodejs:pass:${node_version}")
    else
        print_check "Node.js" "fail" "Not found"
        ((errors++))
        checks_data+=("nodejs:fail:Not found")
    fi

    # Check 7: Python
    if has_command python || has_command python3; then
        local py_version
        py_version=$(python --version 2>/dev/null || python3 --version 2>/dev/null)
        print_check "Python" "pass" "${py_version}"
        checks_data+=("python:pass:${py_version}")
    else
        log "  Python: (not found - optional)"
        checks_data+=("python:warn:Not found (optional)")
    fi

    # Shared volume checks
    echo ""
    info "Shared Volume Mounts:"

    check_volume_mount() {
        local path="$1"
        local name="$2"
        local expanded_path
        expanded_path=$(eval echo "${path}")

        if [[ -d "${expanded_path}" ]]; then
            print_check "  ${name}" "pass" "Mounted at ${expanded_path}"
            checks_data+=("volume_${name// /_}:pass:${expanded_path}")
        else
            print_check "  ${name}" "warn" "Not mounted"
            ((warnings++))
            checks_data+=("volume_${name// /_}:warn:Not mounted")
        fi
    }

    check_volume_mount '~/.claude-shared-auth' 'Claude auth'
    check_volume_mount '~/.config/gh-shared' 'GitHub CLI auth'
    check_volume_mount '~/.gitconfig-shared' 'Git config'
    check_volume_mount '~/.claude-shared-plugins' 'Claude plugins'
    check_volume_mount '~/.mcp-shared' 'MCP servers'

    echo ""
    info "Host Bind Mounts:"

    check_volume_mount '~/.ssh-host' 'SSH keys (host)'
    check_volume_mount '~/.gnupg-host' 'GPG config (host)'

    # Check SSH agent
    if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
        print_check "  SSH agent" "pass" "${SSH_AUTH_SOCK}"
        checks_data+=("ssh_agent:pass:${SSH_AUTH_SOCK}")
    else
        print_check "  SSH agent" "warn" "Not configured"
        ((warnings++))
        checks_data+=("ssh_agent:warn:Not configured")
    fi

    # Summary
    echo ""
    info "========================================"

    if [[ ${errors} -eq 0 ]] && [[ ${warnings} -eq 0 ]]; then
        success "✓ All checks passed!"
        return 0
    elif [[ ${errors} -eq 0 ]]; then
        warn "⚠ Passed with ${warnings} warning(s)"
        echo ""
        log "Your Claudio setup is functional but has minor issues."
        log "Review warnings above for optional improvements."
        return 2
    else
        error "✗ Failed with ${errors} error(s) and ${warnings} warning(s)"
        echo ""
        log "Critical issues detected. Please resolve errors above."
        log "Run 'claudio doctor' for help fixing these issues."
        return 1
    fi
}

#######################################
# Main verify command function
# Arguments:
#   Command arguments
# Returns:
#   0 on success, non-zero on failure
#######################################
cmd_verify() {
    # Parse arguments
    local show_help=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help=true
                shift
                ;;
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
                NO_COLOR=1
                shift
                ;;
            *)
                error "Unknown option: $1"
                echo "" >&2
                show_verify_concise_help >&2
                return 1
                ;;
        esac
    done

    # Show help if requested
    if [[ "${show_help}" == "true" ]]; then
        show_verify_help
        return 0
    fi

    # Run verification
    print_header "Claudio Setup Verification"

    run_verification
}
