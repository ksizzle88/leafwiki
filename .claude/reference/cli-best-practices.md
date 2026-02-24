# CLI Best Practices for Claudio

Best practices for building the Claudio CLI tool, based on industry standards from [clig.dev](https://clig.dev/), [Google's Shell Style Guide](https://google.github.io/styleguide/shellguide.html), and [GitHub's bashstyle](https://github.com/progrium/bashstyle).

## Core Principles

### 1. Human-First Design
- Prioritize readability and usability for humans
- Provide helpful error messages and suggestions
- Show examples in help text
- Use color thoughtfully (disable when not a TTY)

### 2. Composability
- Send output to stdout, messages to stderr
- Support piping with `--plain` flag
- Support `--json` for machine-readable output
- Return proper exit codes (0 = success, non-zero = failure)

### 3. Consistency
- Use same flag names across all subcommands
- Maintain consistent output formatting
- Follow standard conventions (`-h/--help`, `-v/--version`, `-q/--quiet`)

## Subcommand Design

### Naming Patterns
```bash
# Good: Clear, unambiguous
claudio verify
claudio doctor
claudio version

# Avoid: Ambiguous or similar names
claudio update   # vs upgrade? confusing
claudio check    # vs verify? too similar
```

### Noun-Verb Ordering
For complex operations, prefer noun-verb:
```bash
claudio config get
claudio config set
claudio template apply
```

### No Abbreviations
```bash
# Good
claudio verify
claudio version

# Bad - prevents adding "versions" command later
claudio ver  # abbreviation breaks extensibility
```

## Script Structure (Google Style Guide)

### File Header
```bash
#!/bin/bash
# claudio - Main CLI entry point for Claudio development environment
#
# Usage: claudio <command> [options]
#
# Commands:
#   verify   - Verify Claudio setup
#   version  - Show version information
#   doctor   - Diagnose common issues
#   help     - Show help for commands

set -euo pipefail  # Exit on error, undefined vars, pipe failures
```

### Error Handling
```bash
# Always check return values
if ! command; then
    echo "Error: Command failed" >&2
    exit 1
fi

# Route errors to stderr
error() {
    echo "Error: $*" >&2
}

# Use local variables in functions
verify_setup() {
    local checks_passed=0
    local checks_failed=0
    # ...
}
```

### Function Documentation
```bash
#######################################
# Verify Claudio setup and configuration
# Globals:
#   CLAUDE_CONFIG_DIR
# Arguments:
#   None
# Outputs:
#   Verification results to stdout
#   Errors to stderr
# Returns:
#   0 if all checks pass, 1 otherwise
#######################################
verify_setup() {
    # implementation
}
```

## Help Text Design (clig.dev)

### Concise Help (no --help flag)
```bash
$ claudio verify
Usage: claudio verify [options]

Verify your Claudio development environment setup.

Options:
  --json        Output results as JSON
  --quiet       Only show errors

Examples:
  claudio verify
  claudio verify --json > results.json

Use 'claudio verify --help' for more information.
```

### Extensive Help (with --help flag)
```bash
$ claudio verify --help
claudio verify - Verify Claudio setup

USAGE
  claudio verify [options]

DESCRIPTION
  Performs comprehensive verification of your Claudio development
  environment, including:
  - Claude CLI installation and authentication
  - Git and GitHub CLI configuration
  - Volume mounts (shared and per-container)
  - Node.js, Python, and other development tools
  - SSH agent and host bind mounts

OPTIONS
  --json           Output results as JSON for scripting
  --quiet, -q      Only show errors, suppress warnings
  --verbose, -v    Show detailed diagnostic information
  --no-color       Disable colored output

EXAMPLES
  # Basic verification
  claudio verify

  # JSON output for CI/CD
  claudio verify --json

  # Quiet mode - only errors
  claudio verify --quiet

EXIT CODES
  0   All checks passed
  1   Critical errors detected
  2   Warnings present (use --strict to treat as errors)

SEE ALSO
  claudio doctor    Diagnose and fix common issues
  claudio version   Show version information
```

## Output Formatting

### Check for TTY
```bash
# Detect if output is to terminal
if [[ -t 1 ]]; then
    # Terminal - use colors
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    NC='\033[0m'
else
    # Not a terminal (pipe/redirect) - no colors
    GREEN=''
    RED=''
    NC=''
fi

# Respect NO_COLOR environment variable
if [[ -n "${NO_COLOR:-}" ]]; then
    GREEN=''
    RED=''
    NC=''
fi
```

### Machine-Readable Output
```bash
# Support --json flag for scripting
if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
    jq -n \
        --arg status "passed" \
        --argjson checks "$checks_passed" \
        '{status: $status, checks_passed: $checks}'
fi
```

## Argument Parsing

### Standard Flag Names
```bash
# Use conventional flags
-h, --help        # Help text
-v, --version     # Version info
-q, --quiet       # Suppress output
-f, --force       # Skip confirmations
-n, --dry-run     # Show what would happen
--json            # Machine-readable output
--no-color        # Disable colors
```

### Prefer Flags Over Positional Arguments
```bash
# Good: Clear and flexible
claudio template apply --repo myrepo --type simple-image

# Avoid: Unclear and order-dependent
claudio template myrepo simple-image apply
```

## Error Messages

### Human-Friendly Errors
```bash
# Bad
echo "ERROR: ENOENT" >&2

# Good
echo "Error: Claude configuration directory not found at ~/.claude" >&2
echo "       Run 'claudio doctor' to diagnose and fix this issue." >&2
```

### Suggest Next Steps
```bash
if [[ ! -f ~/.claude/.credentials.json ]]; then
    echo "Error: Claude not authenticated" >&2
    echo "" >&2
    echo "To authenticate, run:" >&2
    echo "  claude login" >&2
    echo "" >&2
    echo "Or visit: https://claude.ai/settings" >&2
    exit 1
fi
```

## Variable and Function Naming

### Naming Conventions
```bash
# Constants: UPPERCASE with underscores
readonly CLAUDIO_VERSION="1.0.0"
readonly CLAUDIO_LIB_DIR="/usr/local/lib/claudio"

# Variables: lowercase with underscores
local checks_passed=0
local error_count=0

# Functions: lowercase with underscores
verify_claude_cli() {
    # ...
}

show_version() {
    # ...
}
```

### Always Quote Variables
```bash
# Good
local config_dir="${CLAUDE_CONFIG_DIR}"
if [[ -d "${config_dir}" ]]; then
    echo "Found config at: ${config_dir}"
fi

# Bad - can break with spaces
local config_dir=$CLAUDE_CONFIG_DIR
if [[ -d $config_dir ]]; then
    echo "Found config at: $config_dir"
fi
```

## Environment Variables

### Precedence (Highest to Lowest)
1. Command-line flags
2. Environment variables
3. Config files
4. Defaults

```bash
# Example implementation
VERBOSE="${VERBOSE:-false}"  # Default to false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true  # Flag overrides env var
fi
```

### Follow XDG Base Directory Spec
```bash
# Respect XDG directories
readonly XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
readonly XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

readonly CLAUDIO_CONFIG_DIR="${XDG_CONFIG_HOME}/claudio"
```

## Code Organization

### Directory Structure
```bash
cli/
├── claudio              # Main entry point
├── commands/            # Subcommand implementations
│   ├── verify.sh
│   ├── version.sh
│   ├── doctor.sh
│   └── help.sh
└── lib/                 # Shared libraries
    ├── common.sh        # Colors, utilities
    ├── output.sh        # Formatting functions
    └── validation.sh    # Common checks
```

### Main Entry Point Pattern
```bash
#!/bin/bash
# Main entry point

set -euo pipefail

# Source common libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

main() {
    local command="${1:-}"

    case "${command}" in
        verify|version|doctor|help)
            # shellcheck source=commands/verify.sh
            source "${SCRIPT_DIR}/commands/${command}.sh"
            shift
            "cmd_${command}" "$@"
            ;;
        "")
            cmd_help
            exit 1
            ;;
        *)
            error "Unknown command: ${command}"
            echo "Run 'claudio help' for usage." >&2
            exit 1
            ;;
    esac
}

main "$@"
```

## Testing Considerations

### ShellCheck Compliance
```bash
# Run ShellCheck on all scripts
shellcheck cli/claudio cli/commands/*.sh cli/lib/*.sh

# Address all warnings before committing
```

### Exit Code Testing
```bash
# Test success and failure cases
if claudio verify; then
    echo "Verification passed"
else
    echo "Verification failed with exit code: $?"
fi
```

## Security Best Practices

### Never Echo Secrets
```bash
# Bad
echo "API Key: ${ANTHROPIC_API_KEY}"

# Good
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "API key is configured"
else
    echo "API key not found"
fi
```

### Validate Input
```bash
validate_repo_name() {
    local repo="$1"

    # Only allow alphanumeric, dash, underscore
    if [[ ! "${repo}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error "Invalid repository name: ${repo}"
        echo "Repository names must contain only letters, numbers, dashes, and underscores" >&2
        return 1
    fi
}
```

## Future Extensibility

### Plugin System (Future)
Design with extensibility in mind:
```bash
# Allow custom commands in ~/.config/claudio/commands/
if [[ -d "${CLAUDIO_CONFIG_DIR}/commands" ]]; then
    for custom_cmd in "${CLAUDIO_CONFIG_DIR}/commands"/*.sh; do
        if [[ -f "${custom_cmd}" ]]; then
            # Load custom commands
            source "${custom_cmd}"
        fi
    done
fi
```

## Quick Reference Checklist

Before committing CLI code, verify:

- [ ] Script starts with `#!/bin/bash` and `set -euo pipefail`
- [ ] All functions have documentation comments
- [ ] Variables are quoted: `"${var}"` not `$var`
- [ ] Error messages go to stderr: `>&2`
- [ ] Exit codes are meaningful (0=success, non-zero=failure)
- [ ] Help text includes examples
- [ ] Color codes disabled when not a TTY
- [ ] ShellCheck passes with no warnings
- [ ] Function names use `lowercase_with_underscores`
- [ ] Constants use `UPPERCASE_WITH_UNDERSCORES`
- [ ] Common flags follow conventions (`-h`, `--help`, `--json`, etc.)

## Sources

- [Command Line Interface Guidelines](https://clig.dev/)
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [GitHub bashstyle](https://github.com/progrium/bashstyle)
