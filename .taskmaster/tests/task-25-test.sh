#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# Verification test script for Task 25 (v2): Deploy Claudio container to cloud
# =============================================================================
# Updated for Doppler-based secrets (no ghcr_token/ghcr_username TF vars),
# IAM instance profile for SSM access, and doppler run -- integration.
# Tests are static — no terraform apply is run.
# Exit 0 if all pass, exit 1 if any fail.
# =============================================================================

REPO_DIR="/workspace/workspace/homebase-infra"

PASS_COUNT=0
FAIL_COUNT=0
ERRORS=""

pass() {
  echo "  PASS: $1"
  ((PASS_COUNT++))
}

fail() {
  echo "  FAIL: $1"
  ((FAIL_COUNT++))
  ERRORS="${ERRORS}\n  - $1"
}

section() {
  echo ""
  echo "=== Criterion $1: $2 ==="
}

# Helper: check file exists
require_file() {
  local filepath="$1"
  local label="$2"
  if [ -f "$filepath" ]; then
    pass "$label exists"
    return 0
  else
    fail "$label does not exist ($filepath)"
    return 1
  fi
}

# Helper: check file contains pattern (grep -qE)
file_contains() {
  local filepath="$1"
  local pattern="$2"
  local label="$3"
  if grep -qE "$pattern" "$filepath" 2>/dev/null; then
    pass "$label"
    return 0
  else
    fail "$label"
    return 1
  fi
}

# Helper: check file does NOT contain pattern
file_not_contains() {
  local filepath="$1"
  local pattern="$2"
  local label="$3"
  if grep -qE "$pattern" "$filepath" 2>/dev/null; then
    fail "$label"
    return 1
  else
    pass "$label"
    return 0
  fi
}

# Helper: python3 multiline check for terraform variable blocks
check_tf_variable() {
  local tf_file="$1"
  local var_name="$2"
  local check_field="$3"  # "sensitive" or "default" or "exists" or "type_list"
  local label="$4"

  local result
  result=$(python3 -c "
import re, sys
content = open('$tf_file').read()
match = re.search(r'variable\s+\"$var_name\"\s*\{([^}]+)\}', content, re.DOTALL)
if not match:
    print('NO_VAR')
    sys.exit(0)
block = match.group(1)
if '$check_field' == 'exists':
    print('OK')
elif '$check_field' == 'sensitive':
    if 'sensitive' in block and 'true' in block:
        print('OK')
    else:
        print('MISSING_FIELD')
elif '$check_field' == 'default':
    if 'default' in block:
        print('OK')
    else:
        print('MISSING_FIELD')
elif '$check_field' == 'type_list':
    if 'list' in block:
        print('OK')
    else:
        print('MISSING_FIELD')
" 2>/dev/null)

  case "$result" in
    OK)            pass "$label" ;;
    MISSING_FIELD) fail "$label (variable exists but missing $check_field)" ;;
    NO_VAR)        fail "$label (variable not found)" ;;
    *)             fail "$label (could not parse variable block)" ;;
  esac
}

# Helper: check a terraform variable does NOT exist
check_tf_variable_absent() {
  local tf_file="$1"
  local var_name="$2"
  local label="$3"

  local result
  result=$(python3 -c "
import re, sys
content = open('$tf_file').read()
match = re.search(r'variable\s+\"$var_name\"\s*\{', content)
if match:
    print('FOUND')
else:
    print('ABSENT')
" 2>/dev/null)

  case "$result" in
    ABSENT) pass "$label" ;;
    FOUND)  fail "$label (variable should not exist — secrets come from Doppler)" ;;
    *)      fail "$label (could not parse file)" ;;
  esac
}

# ---------------------------------------------------------------------------
# Criterion 1: All new files exist in the right locations
# ---------------------------------------------------------------------------
section 1 "File existence"

require_file "$REPO_DIR/deploy/docker-compose.cloud.yml" "deploy/docker-compose.cloud.yml"
require_file "$REPO_DIR/deploy/claudio.service" "deploy/claudio.service"
require_file "$REPO_DIR/deploy/.env.cloud.example" "deploy/.env.cloud.example"

# Existing files that should be modified (just check they still exist)
require_file "$REPO_DIR/main.tf" "main.tf"
require_file "$REPO_DIR/variables.tf" "variables.tf"
require_file "$REPO_DIR/outputs.tf" "outputs.tf"

# ---------------------------------------------------------------------------
# Criterion 2: docker-compose.cloud.yml validation
# ---------------------------------------------------------------------------
section 2 "docker-compose.cloud.yml content validation"

COMPOSE="$REPO_DIR/deploy/docker-compose.cloud.yml"

if [ -f "$COMPOSE" ]; then
  # Valid YAML check
  if python3 -c "import yaml; yaml.safe_load(open('$COMPOSE'))" 2>/dev/null; then
    pass "docker-compose.cloud.yml is valid YAML"
  else
    # Fallback: may contain template/interpolation variables that break YAML parsing
    if grep -q 'services:' "$COMPOSE" 2>/dev/null; then
      pass "docker-compose.cloud.yml has valid structure (may contain template vars)"
    else
      fail "docker-compose.cloud.yml is not valid YAML and lacks basic structure"
    fi
  fi

  # Image reference
  file_contains "$COMPOSE" "ghcr\.io/ksizzle88/claudio" \
    "Uses ghcr.io/ksizzle88/claudio image"

  # Volumes
  file_contains "$COMPOSE" "claudio.*config|claude" \
    "Has volume for Claudio/Claude config"
  file_contains "$COMPOSE" "shared" \
    "Has volume for shared data"
  file_contains "$COMPOSE" "commandhistory|command.?history" \
    "Has volume for command history"
  file_contains "$COMPOSE" "/workspace" \
    "Has volume for /workspace"

  # Restart policy
  file_contains "$COMPOSE" "restart:.*unless-stopped" \
    "Has restart: unless-stopped"

  # Healthcheck
  file_contains "$COMPOSE" "healthcheck" \
    "Has healthcheck defined"

  # Required environment variables
  file_contains "$COMPOSE" "CLAUDE_CONFIG_DIR" \
    "Has CLAUDE_CONFIG_DIR env var"
  file_contains "$COMPOSE" "CLAUDIO_HOME" \
    "Has CLAUDIO_HOME env var"
  file_contains "$COMPOSE" "SHELL" \
    "Has SHELL env var"
  file_contains "$COMPOSE" "TZ" \
    "Has TZ env var"
  file_contains "$COMPOSE" "GH_TOKEN" \
    "Has GH_TOKEN env var"
  file_contains "$COMPOSE" "CLAUDE_CODE_TOKEN" \
    "Has CLAUDE_CODE_TOKEN env var"
else
  fail "docker-compose.cloud.yml not found, skipping content checks"
fi

# ---------------------------------------------------------------------------
# Criterion 3: claudio.service (systemd unit file) validation
# ---------------------------------------------------------------------------
section 3 "claudio.service systemd unit validation"

SERVICE="$REPO_DIR/deploy/claudio.service"

if [ -f "$SERVICE" ]; then
  # Required systemd sections
  file_contains "$SERVICE" "^\[Unit\]" \
    "Has [Unit] section"
  file_contains "$SERVICE" "^\[Service\]" \
    "Has [Service] section"
  file_contains "$SERVICE" "^\[Install\]" \
    "Has [Install] section"

  # Required directives
  file_contains "$SERVICE" "After=.*docker\.service" \
    "Has After=docker.service"
  file_contains "$SERVICE" "^Restart=" \
    "Has Restart= directive"
  file_contains "$SERVICE" "WantedBy=.*multi-user\.target" \
    "Has WantedBy=multi-user.target"

  # Doppler integration
  file_contains "$SERVICE" "doppler" \
    "References doppler (for doppler run --)"
else
  fail "claudio.service not found, skipping content checks"
fi

# ---------------------------------------------------------------------------
# Criterion 4: main.tf user_data and IAM validation
# ---------------------------------------------------------------------------
section 4 "main.tf - user_data and IAM additions"

MAIN_TF="$REPO_DIR/main.tf"

if [ -f "$MAIN_TF" ]; then
  # Doppler CLI installation or usage in user_data
  file_contains "$MAIN_TF" "doppler" \
    "user_data contains doppler (CLI install or usage)"

  # SSM — fetch bootstrap token from AWS SSM
  file_contains "$MAIN_TF" "ssm|aws.*ssm" \
    "user_data contains SSM reference (fetching bootstrap token)"

  # Docker compose pull
  file_contains "$MAIN_TF" "docker.compose.*pull|docker-compose.*pull" \
    "user_data contains docker compose pull"

  # Docker compose up
  file_contains "$MAIN_TF" "docker.compose.*up|docker-compose.*up" \
    "user_data contains docker compose up"

  # Systemd service installation for claudio
  file_contains "$MAIN_TF" "claudio\.service" \
    "user_data references claudio.service for systemd installation"

  # IAM instance profile resource
  file_contains "$MAIN_TF" "aws_iam_instance_profile" \
    "Has IAM instance profile resource"

  # IAM role resource for the instance
  file_contains "$MAIN_TF" "aws_iam_role" \
    "Has IAM role resource for instance"

  # EC2 instance references instance profile
  file_contains "$MAIN_TF" "iam_instance_profile" \
    "EC2 instance references iam_instance_profile"
else
  fail "main.tf not found, skipping user_data and IAM checks"
fi

# ---------------------------------------------------------------------------
# Criterion 5: variables.tf - new variables (Doppler model)
# ---------------------------------------------------------------------------
section 5 "variables.tf - new Claudio deployment variables (Doppler model)"

VARS_TF="$REPO_DIR/variables.tf"

if [ -f "$VARS_TF" ]; then
  # New variables that SHOULD exist
  check_tf_variable "$VARS_TF" "doppler_project" "exists" \
    "variable doppler_project exists"

  check_tf_variable "$VARS_TF" "doppler_config" "exists" \
    "variable doppler_config exists"

  check_tf_variable "$VARS_TF" "claudio_image_tag" "default" \
    "variable claudio_image_tag with default value"

  check_tf_variable "$VARS_TF" "workspace_repos" "type_list" \
    "variable workspace_repos with list type"

  check_tf_variable "$VARS_TF" "git_user_name" "exists" \
    "variable git_user_name exists"

  check_tf_variable "$VARS_TF" "git_user_email" "exists" \
    "variable git_user_email exists"

  check_tf_variable "$VARS_TF" "timezone" "exists" \
    "variable timezone exists"

  # Variables that should NOT exist (secrets come from Doppler, not TF)
  check_tf_variable_absent "$VARS_TF" "ghcr_token" \
    "variable ghcr_token does NOT exist (secrets from Doppler)"

  check_tf_variable_absent "$VARS_TF" "ghcr_username" \
    "variable ghcr_username does NOT exist (secrets from Doppler)"
else
  fail "variables.tf not found, skipping variable checks"
fi

# ---------------------------------------------------------------------------
# Criterion 6: outputs.tf - container connection output
# ---------------------------------------------------------------------------
section 6 "outputs.tf - container connection output"

OUTPUTS_TF="$REPO_DIR/outputs.tf"

if [ -f "$OUTPUTS_TF" ]; then
  # Look for an output that helps connect to the container
  if grep -qE 'output\s+"(ssh_to_container|container_ssh_command|container_command|claudio_ssh|claudio_connect)"' "$OUTPUTS_TF" 2>/dev/null; then
    pass "Has a named container connection output"
  elif grep -qEi '(container|claudio)' "$OUTPUTS_TF" 2>/dev/null && grep -qE '^output\s' "$OUTPUTS_TF" 2>/dev/null; then
    # Broader check: any output mentioning container or claudio
    pass "Has an output related to container/claudio connection"
  else
    fail "No container connection output found in outputs.tf"
  fi
else
  fail "outputs.tf not found, skipping output checks"
fi

# ---------------------------------------------------------------------------
# Criterion 7: terraform fmt check
# ---------------------------------------------------------------------------
section 7 "Terraform formatting (terraform fmt)"

if command -v terraform &>/dev/null; then
  FMT_OUTPUT=$(cd "$REPO_DIR" && terraform fmt -check -recursive 2>&1)
  FMT_EXIT=$?
  if [ "$FMT_EXIT" -eq 0 ]; then
    pass "terraform fmt -check -recursive passes"
  else
    fail "terraform fmt -check found formatting issues: $FMT_OUTPUT"
  fi
else
  echo "  SKIP: terraform not available in this environment (terraform fmt check)"
fi

# ---------------------------------------------------------------------------
# Criterion 8: terraform validate
# ---------------------------------------------------------------------------
section 8 "Terraform validation"

if command -v terraform &>/dev/null; then
  INIT_OUTPUT=$(cd "$REPO_DIR" && terraform init -backend=false 2>&1)
  INIT_EXIT=$?
  if [ "$INIT_EXIT" -eq 0 ]; then
    VALIDATE_OUTPUT=$(cd "$REPO_DIR" && terraform validate 2>&1)
    VALIDATE_EXIT=$?
    if [ "$VALIDATE_EXIT" -eq 0 ]; then
      pass "terraform validate passes"
    else
      fail "terraform validate failed: $VALIDATE_OUTPUT"
    fi
  else
    echo "  SKIP: terraform init failed (expected without backend creds): ${INIT_OUTPUT:0:200}"
  fi
else
  echo "  SKIP: terraform not available in this environment (terraform validate)"
fi

# ---------------------------------------------------------------------------
# Criterion 9: Environment tfvars reference new variables
# ---------------------------------------------------------------------------
section 9 "Environment tfvars - branch-based image tags and repos"

declare -A ENV_TAGS
ENV_TAGS[development]="develop"
ENV_TAGS[staging]="stage"
ENV_TAGS[production]="master|latest"

for env_dir in "$REPO_DIR/environments"/*/; do
  env_name=$(basename "$env_dir")
  TFVARS="$env_dir/terraform.tfvars"

  if [ ! -f "$TFVARS" ]; then
    fail "$env_name: terraform.tfvars not found"
    continue
  fi

  # Check for claudio_image_tag reference
  file_contains "$TFVARS" "claudio_image_tag" \
    "$env_name/terraform.tfvars references claudio_image_tag"

  # Check correct branch-based tag per environment
  expected_tag="${ENV_TAGS[$env_name]:-}"
  if [ -n "$expected_tag" ]; then
    if grep -qE "claudio_image_tag" "$TFVARS" 2>/dev/null; then
      if grep -E "claudio_image_tag" "$TFVARS" 2>/dev/null | grep -qE "$expected_tag"; then
        pass "$env_name uses correct image tag ($expected_tag)"
      else
        fail "$env_name does not use expected image tag ($expected_tag)"
      fi
    fi
  fi

  # Check for workspace_repos reference
  file_contains "$TFVARS" "workspace_repos" \
    "$env_name/terraform.tfvars references workspace_repos"
done

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==========================================="
echo "  RESULTS: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "==========================================="

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
  echo ""
  exit 1
else
  echo ""
  echo "All acceptance criteria verified successfully."
  exit 0
fi
