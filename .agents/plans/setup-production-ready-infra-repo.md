# Feature: Production-Ready Infrastructure Repository Setup

Transform the homebase-infra repository into a production-ready infrastructure management system with automated workflows, safety controls, and team collaboration features.

## Feature Description

Set up the infrastructure repository with enterprise-grade capabilities that make it safe, automated, and cost-effective to manage cloud infrastructure. This includes adding safeguards to prevent mistakes, automation to reduce manual work, security scanning to catch vulnerabilities, and cost tracking to understand spending.

## User Story

As a **team managing cloud infrastructure**
I want to **use modern infrastructure-as-code practices with automated safety checks**
So that **I can deploy infrastructure confidently, track costs, and collaborate effectively without fear of breaking production**

## Problem Statement

The current homebase-infra repository has basic infrastructure code (VPC, EC2, security groups) but lacks the operational capabilities needed for safe team collaboration:

**Safety Issues:**
- No remote state management (state stored locally, risk of data loss)
- Risk of concurrent changes causing conflicts or state corruption
- No automated checks before changes go live
- Easy to accidentally break production
- No rollback mechanism if something goes wrong

**Operational Challenges:**
- Manual processes are time-consuming and error-prone
- No security scanning to catch vulnerabilities
- Inconsistent code formatting between team members
- No CI/CD pipeline for automated deployments
- Difficult to understand what changed and why

**Cost and Visibility:**
- No way to track spending by environment or team
- Can't tell which resources cost the most
- No alerts when costs spike unexpectedly
- Hard to optimize spending without visibility

**Collaboration:**
- No review process for infrastructure changes
- Changes can conflict between team members
- No audit trail of who changed what and when
- Documentation gets out of date quickly

## Solution Statement

Implement a comprehensive infrastructure management system that provides:

1. **Safe State Management**: Prevent data loss and conflicts with encrypted remote storage
2. **Automated Workflows**: Review and deploy infrastructure changes automatically
3. **Security Guardrails**: Catch security issues before they reach production
4. **Cost Visibility**: Track and optimize spending across environments
5. **Team Collaboration**: Review changes together and maintain audit trails
6. **Quality Controls**: Ensure consistent, validated code

## Feature Metadata

**Feature Type**: Infrastructure Enhancement + Process Improvement
**Estimated Complexity**: Medium-High
**Primary Systems Affected**: Repository structure, deployment workflows, team processes
**Dependencies**: AWS account, GitHub repository, Terraform 1.5+

---

## CONTEXT REFERENCES

### Relevant Codebase Files (IMPORTANT: YOU MUST READ THESE FILES BEFORE IMPLEMENTING!)

**Current Infrastructure Code:**
- `/workspace/workspace/homebase-infra/main.tf` (lines 1-190) - Current infrastructure resources (VPC, EC2, security groups)
- `/workspace/workspace/homebase-infra/variables.tf` (lines 1-42) - Existing variable definitions and defaults
- `/workspace/workspace/homebase-infra/outputs.tf` (lines 1-30) - Current output definitions
- `/workspace/workspace/homebase-infra/README.md` (lines 1-222) - Existing documentation structure
- `/workspace/workspace/homebase-infra/.gitignore` (lines 1-33) - Current gitignore patterns

**Project Conventions:**
- `/workspace/.claude/CLAUDE.md` (lines 90-99) - Git commit conventions (conventional commits format)
- `/workspace/.claude/CLAUDE.md` (lines 59-66) - Code style guidelines
- `/workspace/.claude/CLAUDE.md` (lines 68-75) - Docker best practices (applicable to infrastructure)

### New Files to Create

**Infrastructure Organization:**
- `/workspace/workspace/homebase-infra/backend.tf` - Remote state configuration with S3 and state locking
- `/workspace/workspace/homebase-infra/providers.tf` - Provider configuration with default tags
- `/workspace/workspace/homebase-infra/locals.tf` - Common local values and computed tags
- `/workspace/workspace/homebase-infra/environments/dev/terraform.tfvars` - Development environment configuration
- `/workspace/workspace/homebase-infra/environments/staging/terraform.tfvars` - Staging environment configuration
- `/workspace/workspace/homebase-infra/environments/prod/terraform.tfvars` - Production environment configuration

**Modules (Optional - for reusable components):**
- `/workspace/workspace/homebase-infra/modules/vpc/main.tf` - Reusable VPC module
- `/workspace/workspace/homebase-infra/modules/vpc/variables.tf`
- `/workspace/workspace/homebase-infra/modules/vpc/outputs.tf`

**CI/CD and Quality:**
- `/workspace/workspace/homebase-infra/.github/workflows/terraform-plan.yml` - PR plan workflow
- `/workspace/workspace/homebase-infra/.github/workflows/terraform-apply.yml` - Automated apply workflow
- `/workspace/workspace/homebase-infra/.pre-commit-config.yaml` - Pre-commit hooks configuration
- `/workspace/workspace/homebase-infra/.tflint.hcl` - TFLint configuration
- `/workspace/workspace/homebase-infra/.checkov.yaml` - Checkov security scanning configuration

**Documentation:**
- `/workspace/workspace/homebase-infra/docs/SETUP.md` - Team onboarding guide
- `/workspace/workspace/homebase-infra/docs/DEPLOYMENT.md` - Deployment procedures
- `/workspace/workspace/homebase-infra/docs/TROUBLESHOOTING.md` - Common issues and solutions
- `/workspace/workspace/homebase-infra/docs/ARCHITECTURE.md` - Architecture decisions

### Relevant Documentation (YOU SHOULD READ THESE BEFORE IMPLEMENTING!)

**Terraform Remote State:**
- [Terraform S3 Backend Documentation](https://developer.hashicorp.com/terraform/language/backend/s3)
  - Specific section: S3-native state locking (Terraform 1.10.0+)
  - Why: New approach eliminates need for DynamoDB, simpler and cheaper
- [AWS Prescriptive Guidance: Terraform Backend Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/backend.html)
  - Specific section: Security and encryption configuration
  - Why: Production-ready security requirements

**GitHub Actions CI/CD:**
- [HashiCorp: Automate Terraform with GitHub Actions](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions)
  - Specific section: OIDC authentication with AWS (no access keys)
  - Why: Secure authentication without storing credentials in GitHub
- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
  - Specific section: Setting up AWS IAM OIDC provider
  - Why: Required for secure GitHub Actions to AWS authentication

**Security Scanning:**
- [Trivy Configuration Documentation](https://aquasecurity.github.io/trivy/latest/docs/configuration/)
  - Specific section: Terraform scanning
  - Why: Modern replacement for deprecated tfsec, actively maintained
- [Checkov Documentation](https://www.checkov.io/documentation.html)
  - Specific section: CIS AWS Foundations Benchmark
  - Why: Compliance-focused scanning with 1000+ policies

**Cost Management:**
- [AWS Cost Allocation Tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/cost-alloc-tags.html)
  - Specific section: User-defined tags and activation
  - Why: Required for cost tracking and attribution
- [Terraform Default Tags](https://developer.hashicorp.com/terraform/tutorials/aws/aws-default-tags)
  - Specific section: Provider-level default tags
  - Why: Consistent tagging across all resources automatically

**Pre-commit Hooks:**
- [pre-commit-terraform Framework](https://github.com/antonbabenko/pre-commit-terraform)
  - Specific section: Available hooks and configuration
  - Why: Industry standard for Terraform pre-commit automation

### Patterns to Follow

**Naming Conventions (from existing code):**
```hcl
# Resource naming: ${project_name}-${resource_type}-${environment}
resource "aws_vpc" "main" {
  tags = {
    Name = "${var.project_name}-vpc"  # Pattern: homebase-vpc
  }
}

# Variable naming: snake_case
variable "project_name" {}
variable "aws_region" {}
variable "allowed_ssh_cidr" {}
```

**Tagging Pattern (to implement):**
```hcl
# Use provider default_tags for consistency
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment  = var.environment
      Project      = var.project_name
      Owner        = var.owner_email
      CostCenter   = var.cost_center
      ManagedBy    = "Terraform"
      Repository   = "homebase-infra"
    }
  }
}
```

**File Organization Pattern:**
```
# Separate configuration by purpose (from research):
- backend.tf      # Backend/state configuration
- providers.tf    # Provider configuration with default tags
- locals.tf       # Computed local values
- variables.tf    # Input variables
- main.tf         # Resource definitions
- outputs.tf      # Output values
- versions.tf     # Terraform and provider version constraints
```

**Security Group Pattern (from main.tf:69-122):**
```hcl
# Descriptive ingress/egress rules with comments
resource "aws_security_group" "dev_instance" {
  name        = "${var.project_name}-dev-sg"
  description = "Security group for development instance"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr
  }
  # ... more rules
}
```

**Documentation Pattern (from README.md):**
- Prerequisites section with installation commands
- Step-by-step getting started guide
- Security warnings (⚠️ prefix)
- Cost estimates table
- Troubleshooting section with common issues

---

## IMPLEMENTATION PLAN

### Phase 1: Remote State Setup (Safety Foundation)

**Goal**: Make infrastructure state safe and collaborative with remote storage

**Why This First**: Remote state is the foundation - all other improvements build on this. Must be set up before adding environments or CI/CD.

**Tasks:**
1. Create S3 bucket for Terraform state with encryption and versioning
2. Configure S3-native state locking (Terraform 1.10.0+ feature)
3. Create backend.tf with remote state configuration
4. Migrate existing local state to remote S3 backend
5. Verify state locking works (test concurrent terraform plan)

**Success Criteria:**
- State is stored remotely in encrypted S3 bucket
- Versioning enabled for rollback capability
- State locking prevents concurrent modifications
- Local state file removed from repository

### Phase 2: Repository Structure and Tagging (Organization)

**Goal**: Organize code for multi-environment support and cost tracking

**Why After Phase 1**: Need remote state working before creating multiple environments

**Tasks:**
1. Extract provider configuration to providers.tf with default tags
2. Create locals.tf for computed values and common tags
3. Set up environment-specific tfvars files (dev/staging/prod)
4. Update variables.tf with environment, cost_center, owner fields
5. Activate cost allocation tags in AWS (via aws_ce_cost_allocation_tag)
6. Document tagging strategy in README

**Success Criteria:**
- All resources automatically tagged via provider default_tags
- Environment-specific configurations separated into tfvars files
- Cost allocation tags activated and visible in AWS Cost Explorer
- Documentation explains tagging strategy

### Phase 3: Security Scanning and Quality (Guardrails)

**Goal**: Catch security issues and enforce code quality automatically

**Why After Phase 2**: Need proper structure in place before adding quality gates

**Tasks:**
1. Create .pre-commit-config.yaml with terraform_fmt, terraform_validate, terraform_trivy
2. Create .tflint.hcl configuration for AWS plugin and best practices
3. Create .checkov.yaml for security compliance checks
4. Install pre-commit hooks locally and test on existing code
5. Fix any security issues found by Trivy and Checkov
6. Document pre-commit setup in DEVELOPMENT.md

**Success Criteria:**
- Pre-commit hooks run automatically on git commit
- Code is consistently formatted with terraform fmt
- Security scans pass with zero CRITICAL/HIGH findings
- Team documentation includes pre-commit setup instructions

### Phase 4: CI/CD Pipeline (Automation)

**Goal**: Automate infrastructure review and deployment workflows

**Why After Phase 3**: Need quality checks working locally before automating in CI/CD

**Tasks:**
1. Set up AWS IAM OIDC provider for GitHub Actions authentication
2. Create GitHub Actions workflow for terraform plan on pull requests
3. Create GitHub Actions workflow for terraform apply on merge to main
4. Configure workflow to comment plan output on PRs
5. Add GitHub environment protection rules for production
6. Test full workflow end-to-end with a small change

**Success Criteria:**
- Pull requests automatically show terraform plan output
- Plans are reviewed before merge
- Merges to main automatically apply changes
- No AWS credentials stored in GitHub (OIDC authentication)
- Full audit trail of all infrastructure changes

### Phase 5: Cost Monitoring (Visibility)

**Goal**: Enable cost tracking, budgets, and optimization

**Why After Phase 4**: Tags must exist and be propagated via CI/CD first

**Tasks:**
1. Create aws_budgets_budget resources for environment and project tracking
2. Configure budget alerts to notify via email at 75% and 100%
3. Set up cost anomaly detection via aws_ce_anomaly_monitor
4. Document cost optimization practices in README
5. Create cost dashboard viewing guide for AWS Cost Explorer
6. Test budget alert notifications

**Success Criteria:**
- Budget alerts configured for dev, staging, prod environments
- Cost allocation tags visible in AWS Cost Explorer
- Team can view costs by Environment, Project, CostCenter tags
- Anomaly detection alerts on unexpected spending

### Phase 6: Documentation and Operations (Enablement)

**Goal**: Enable team self-service and troubleshooting

**Why Last**: Captures learnings from implementation phases

**Tasks:**
1. Create docs/SETUP.md with team onboarding instructions
2. Create docs/DEPLOYMENT.md with deployment procedures
3. Create docs/TROUBLESHOOTING.md with common issues
4. Create docs/ARCHITECTURE.md documenting design decisions
5. Update main README.md with new workflows and structure
6. Create runbook for disaster recovery (state recovery)

**Success Criteria:**
- New team member can set up and deploy using documentation
- Common operations documented with examples
- Troubleshooting covers top 10 expected issues
- Architecture decisions are clear and justified

---

## STEP-BY-STEP TASKS

**IMPORTANT**: Execute every task in order, top to bottom. Each task is atomic and independently testable.

### PHASE 1: Remote State Setup

### CREATE /workspace/workspace/homebase-infra/backend.tf

- **IMPLEMENT**: S3 backend configuration with S3-native state locking
- **PATTERN**: Use S3-native locking (Terraform 1.10.0+) - simpler than DynamoDB approach
- **IMPORTS**: None (Terraform configuration block)
- **GOTCHA**: State locking requires `use_lockfile = true` in backend config
- **VALIDATE**: `terraform init` (should initialize successfully)

```hcl
terraform {
  backend "s3" {
    bucket         = "homebase-terraform-state"
    key            = "homebase/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    use_lockfile   = true  # S3-native locking (Terraform 1.10.0+)

    # Optionally add DynamoDB for compatibility with older Terraform
    # dynamodb_table = "homebase-terraform-locks"
  }
}
```

### CREATE /workspace/workspace/homebase-infra/state-bucket.tf

- **IMPLEMENT**: Terraform configuration to create the S3 state bucket (run once, then import to state)
- **PATTERN**: Separate file for bootstrap resources, deleted after state migration
- **IMPORTS**: None
- **GOTCHA**: This creates the bucket that will store the state - chicken/egg problem solved by running this first without backend, then migrating
- **VALIDATE**: `terraform apply` (creates bucket), then configure backend and `terraform init` to migrate

```hcl
# state-bucket.tf
# TEMPORARY FILE: Create state bucket, then delete this file after migration

resource "aws_s3_bucket" "terraform_state" {
  bucket = "homebase-terraform-state"

  tags = {
    Name        = "Terraform State Bucket"
    Environment = "shared"
    Purpose     = "terraform-state-storage"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

### EXECUTE State Migration

- **IMPLEMENT**: Create state bucket, configure backend, migrate state
- **PATTERN**: Multi-step bootstrap process
- **IMPORTS**: None (bash commands)
- **GOTCHA**: Must create bucket BEFORE configuring backend
- **VALIDATE**: After migration, `terraform state list` shows all resources and state file exists in S3

```bash
# Step 1: Create the state bucket (without backend configured)
cd /workspace/workspace/homebase-infra
terraform init
terraform apply -target=aws_s3_bucket.terraform_state \
                -target=aws_s3_bucket_versioning.terraform_state \
                -target=aws_s3_bucket_server_side_encryption_configuration.terraform_state \
                -target=aws_s3_bucket_public_access_block.terraform_state

# Step 2: Add backend configuration to backend.tf (already created above)

# Step 3: Migrate state to S3
terraform init -migrate-state
# Type 'yes' when prompted

# Step 4: Verify state is in S3
aws s3 ls s3://homebase-terraform-state/homebase/

# Step 5: Delete local state files
rm terraform.tfstate terraform.tfstate.backup

# Step 6: Delete state-bucket.tf (no longer needed)
rm state-bucket.tf
git add backend.tf
git commit -m "feat: add remote state backend with S3"
```

### PHASE 2: Repository Structure and Tagging

### CREATE /workspace/workspace/homebase-infra/providers.tf

- **IMPLEMENT**: Extract provider configuration from main.tf with default tags
- **PATTERN**: Separate providers.tf following Terraform conventions
- **IMPORTS**: None (Terraform configuration)
- **GOTCHA**: Must remove provider block from main.tf to avoid duplication
- **VALIDATE**: `terraform validate`

```hcl
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment    = var.environment
      Project        = var.project_name
      Owner          = var.owner_email
      CostCenter     = var.cost_center
      ManagedBy      = "Terraform"
      Repository     = "homebase-infra"
      Terraform      = "true"
    }
  }
}
```

### UPDATE /workspace/workspace/homebase-infra/main.tf

- **IMPLEMENT**: Remove provider and backend blocks (now in separate files)
- **PATTERN**: Keep only resource definitions in main.tf
- **IMPORTS**: None
- **GOTCHA**: Remove lines 1-14 (terraform and provider blocks)
- **VALIDATE**: `terraform validate`

Remove these lines from main.tf (1-14):
```hcl
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

### CREATE /workspace/workspace/homebase-infra/locals.tf

- **IMPLEMENT**: Common local values and computed tags
- **PATTERN**: Centralize computed values
- **IMPORTS**: None
- **GOTCHA**: None
- **VALIDATE**: `terraform validate`

```hcl
locals {
  common_tags = {
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
    UpdatedDate = formatdate("YYYY-MM-DD", timestamp())
  }

  # Environment-specific settings
  environment_config = {
    production = {
      instance_type = "t3.medium"
      backup_retention = 30
    }
    staging = {
      instance_type = "t3.small"
      backup_retention = 7
    }
    development = {
      instance_type = "t3.micro"
      backup_retention = 1
    }
  }
}
```

### UPDATE /workspace/workspace/homebase-infra/variables.tf

- **IMPLEMENT**: Add environment, owner_email, cost_center variables
- **PATTERN**: Follow existing variable structure with validation
- **IMPORTS**: None
- **GOTCHA**: Validation blocks ensure only valid values accepted
- **VALIDATE**: `terraform validate`

Add to end of variables.tf:
```hcl
variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

variable "owner_email" {
  description = "Email of team/person responsible for this infrastructure"
  type        = string
}

variable "cost_center" {
  description = "Cost center code for billing allocation"
  type        = string
  default     = "ENG-001"
}
```

### CREATE /workspace/workspace/homebase-infra/environments/

- **IMPLEMENT**: Directory structure for environment-specific configurations
- **PATTERN**: Separate tfvars per environment
- **IMPORTS**: None (directory creation)
- **GOTCHA**: Must create .gitkeep or README to commit empty directories
- **VALIDATE**: `ls -la environments/`

```bash
mkdir -p /workspace/workspace/homebase-infra/environments/{development,staging,production}
```

### CREATE /workspace/workspace/homebase-infra/environments/development/terraform.tfvars

- **IMPLEMENT**: Development environment configuration
- **PATTERN**: Mirror existing terraform.tfvars.example structure
- **IMPORTS**: None
- **GOTCHA**: Use smaller instance types for dev to save costs
- **VALIDATE**: `terraform plan -var-file=environments/development/terraform.tfvars`

```hcl
# Development Environment Configuration
aws_region          = "us-east-1"
environment         = "development"
project_name        = "homebase"
instance_type       = "t3.micro"
root_volume_size    = 20
ssh_public_key_path = "~/.ssh/id_rsa.pub"
use_elastic_ip      = false
allowed_ssh_cidr    = ["0.0.0.0/0"]

# Cost tracking
owner_email  = "devops-team@company.com"
cost_center  = "ENG-001"
```

### CREATE /workspace/workspace/homebase-infra/environments/staging/terraform.tfvars

- **IMPLEMENT**: Staging environment configuration
- **PATTERN**: Medium-sized resources, similar to production but smaller
- **IMPORTS**: None
- **GOTCHA**: Use staging-specific naming to avoid conflicts
- **VALIDATE**: `terraform plan -var-file=environments/staging/terraform.tfvars`

```hcl
# Staging Environment Configuration
aws_region          = "us-east-1"
environment         = "staging"
project_name        = "homebase"
instance_type       = "t3.small"
root_volume_size    = 25
ssh_public_key_path = "~/.ssh/id_rsa.pub"
use_elastic_ip      = true
allowed_ssh_cidr    = ["0.0.0.0/0"]

# Cost tracking
owner_email  = "devops-team@company.com"
cost_center  = "ENG-001"
```

### CREATE /workspace/workspace/homebase-infra/environments/production/terraform.tfvars

- **IMPLEMENT**: Production environment configuration
- **PATTERN**: Production-sized resources with restricted access
- **IMPORTS**: None
- **GOTCHA**: Restrict SSH access to specific IPs in production
- **VALIDATE**: `terraform plan -var-file=environments/production/terraform.tfvars`

```hcl
# Production Environment Configuration
aws_region          = "us-east-1"
environment         = "production"
project_name        = "homebase"
instance_type       = "t3.medium"
root_volume_size    = 30
ssh_public_key_path = "~/.ssh/id_rsa.pub"
use_elastic_ip      = true

# SECURITY: Restrict to office IP
allowed_ssh_cidr    = ["YOUR.OFFICE.IP/32"]

# Cost tracking
owner_email  = "devops-team@company.com"
cost_center  = "ENG-001"
```

### CREATE /workspace/workspace/homebase-infra/cost-tracking.tf

- **IMPLEMENT**: AWS Cost Explorer tag activation and budget alerts
- **PATTERN**: Separate file for cost management resources
- **IMPORTS**: None
- **GOTCHA**: Cost allocation tags take 24 hours to activate and only work from management account
- **VALIDATE**: `terraform apply` then check AWS Billing Console

```hcl
# Activate cost allocation tags
resource "aws_ce_cost_allocation_tag" "environment" {
  tag_key = "Environment"
  status  = "Active"
}

resource "aws_ce_cost_allocation_tag" "project" {
  tag_key = "Project"
  status  = "Active"
}

resource "aws_ce_cost_allocation_tag" "cost_center" {
  tag_key = "CostCenter"
  status  = "Active"
}

resource "aws_ce_cost_allocation_tag" "owner" {
  tag_key = "Owner"
  status  = "Active"
}

# Environment budget with alerts
resource "aws_budgets_budget" "environment_monthly" {
  name              = "${var.project_name}-${var.environment}-monthly-budget"
  budget_type       = "COST"
  limit_amount      = var.environment == "production" ? "500" : "100"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2024-01-01_00:00"

  cost_filter {
    name   = "TagKeyValue"
    values = ["Environment$${var.environment}"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 75
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.owner_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.owner_email]
  }
}
```

### UPDATE /workspace/workspace/homebase-infra/.gitignore

- **IMPLEMENT**: Add environment-specific overrides to gitignore
- **PATTERN**: Allow committed environment templates, ignore local overrides
- **IMPORTS**: None
- **GOTCHA**: Don't ignore the environments/ directory itself, only local overrides
- **VALIDATE**: `git status` shows environments directory but not *.local.tfvars

Add to .gitignore:
```
# Environment-specific local overrides
*.local.tfvars
```

### PHASE 3: Security Scanning and Quality

### CREATE /workspace/workspace/homebase-infra/.pre-commit-config.yaml

- **IMPLEMENT**: Pre-commit hooks for formatting, validation, and security
- **PATTERN**: Use pre-commit-terraform framework with security scanning
- **IMPORTS**: None (pre-commit framework config)
- **GOTCHA**: Requires pre-commit framework installed locally (pip install pre-commit)
- **VALIDATE**: `pre-commit run --all-files`

```yaml
# Production-ready Terraform pre-commit configuration
repos:
  # Terraform hooks
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.92.0
    hooks:
      # Essential: Code formatting
      - id: terraform_fmt
        name: Terraform Format
        args:
          - '--hook-config=--parallelism-limit=CPU*2'

      # Essential: Configuration validation
      - id: terraform_validate
        name: Terraform Validate
        args:
          - '--hook-config=--retry-once'

      # Recommended: Linting
      - id: terraform_tflint
        name: TFLint
        args:
          - '--args=--config=.tflint.hcl'

      # Security: Trivy scanning (modern tfsec replacement)
      - id: terraform_trivy
        name: Trivy Security Scan
        args:
          - --args=--severity=HIGH,CRITICAL
          - --args=--exit-code=0  # Don't fail builds initially
        exclude: '.terraform/'

      # Security: Checkov compliance
      - id: terraform_checkov
        name: Checkov Security Scan
        args:
          - --args=--framework=terraform
          - --args=--quiet
        exclude: '.terraform/'

      # Documentation: Auto-generate
      - id: terraform_docs
        name: Terraform Docs
        args:
          - --hook-config=--path-to-file=README.md
          - --hook-config=--add-to-existing-file=true

  # General file checks
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
        exclude: '.terraform/'
      - id: check-merge-conflict
      - id: detect-private-key
```

### CREATE /workspace/workspace/homebase-infra/.tflint.hcl

- **IMPLEMENT**: TFLint configuration for AWS best practices
- **PATTERN**: Enable AWS plugin and Terraform best practice rules
- **IMPORTS**: None (TFLint config)
- **GOTCHA**: Must install tflint and aws plugin separately
- **VALIDATE**: `tflint --init && tflint`

```hcl
plugin "aws" {
  enabled = true
  version = "0.31.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

plugin "terraform" {
  enabled = true
}

rule "terraform_comment_syntax" {
  enabled = true
}

rule "terraform_deprecated_index" {
  enabled = true
}

rule "terraform_unused_required_providers" {
  enabled = true
}

rule "terraform_module_pinned_source" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_standard_module_structure" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true
}
```

### CREATE /workspace/workspace/homebase-infra/.checkov.yaml

- **IMPLEMENT**: Checkov security scanning configuration
- **PATTERN**: Enable specific security checks, skip non-applicable ones
- **IMPORTS**: None (Checkov config)
- **GOTCHA**: Checkov is very strict - may need to skip some checks initially
- **VALIDATE**: `checkov -d . --config-file .checkov.yaml`

```yaml
framework:
  - terraform

# Enable specific critical checks
checks:
  - CKV_AWS_1     # Ensure CloudFront distribution is encrypted
  - CKV_AWS_19    # Ensure CloudTrail log file validation is enabled
  - CKV_AWS_20    # Ensure S3 bucket has versioning enabled
  - CKV_AWS_21    # Ensure S3 bucket has MFA Delete enabled
  - CKV_AWS_23    # Ensure security group has description
  - CKV_AWS_24    # Ensure security group rules have description
  - CKV_AWS_79    # Ensure Instance Metadata Service Version 1 is not enabled
  - CKV_AWS_88    # EC2 instance should not have public IP
  - CKV_AWS_126   # Ensure EBS is encrypted
  - CKV_AWS_130   # Ensure VPC subnets do not assign public IP by default

# Skip checks not applicable to current infrastructure
skip-checks:
  - CKV_AWS_88    # Skip for dev instances that need public IP

compact: true
quiet: true
```

### INSTALL pre-commit hooks

- **IMPLEMENT**: Install pre-commit framework and initialize hooks
- **PATTERN**: Team setup process
- **IMPORTS**: None (pip install)
- **GOTCHA**: Each team member must run this after cloning repository
- **VALIDATE**: `git commit` triggers hooks automatically

```bash
# Install pre-commit framework
pip install pre-commit

# Install git hooks
cd /workspace/workspace/homebase-infra
pre-commit install

# Run all hooks manually to test
pre-commit run --all-files

# If needed, install additional tools
# macOS:
brew install tflint terraform-docs trivy checkov

# Ubuntu:
sudo apt-get install -y python3-pip
pip3 install checkov
```

### FIX security issues

- **IMPLEMENT**: Address any HIGH/CRITICAL security findings from Trivy and Checkov
- **PATTERN**: Iterative fixing based on scan results
- **IMPORTS**: None
- **GOTCHA**: May need to add exceptions for legitimate use cases (e.g., public IPs for dev)
- **VALIDATE**: `pre-commit run terraform_trivy --all-files` and `pre-commit run terraform_checkov --all-files` with zero CRITICAL/HIGH findings

Common fixes needed:
1. Add descriptions to security group rules (CKV_AWS_24)
2. Ensure EBS encryption is enabled (already done in main.tf:163)
3. Review public IP assignments for security implications

### PHASE 4: CI/CD Pipeline

### CREATE AWS IAM OIDC Provider for GitHub

- **IMPLEMENT**: AWS IAM configuration for GitHub Actions OIDC authentication
- **PATTERN**: Secure authentication without storing credentials
- **IMPORTS**: None (AWS Console or CLI)
- **GOTCHA**: Must use exact thumbprint and provider URL
- **VALIDATE**: Check in AWS IAM Console → Identity Providers

```bash
# Option 1: AWS Console
# 1. Go to IAM → Identity Providers → Add Provider
# 2. Provider Type: OpenID Connect
# 3. Provider URL: https://token.actions.githubusercontent.com
# 4. Audience: sts.amazonaws.com

# Option 2: AWS CLI
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### CREATE /workspace/workspace/homebase-infra/iam-github-actions.tf

- **IMPLEMENT**: IAM role for GitHub Actions with trust policy
- **PATTERN**: OIDC-based trust relationship
- **IMPORTS**: None
- **GOTCHA**: Replace YOUR-GITHUB-ORG and YOUR-REPO with actual values
- **VALIDATE**: `terraform apply` then verify role exists in AWS IAM

```hcl
# IAM role for GitHub Actions
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions" {
  name = "github-actions-terraform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:ksizzle88/homebase-infra:*"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "GitHub Actions Terraform Role"
    Purpose     = "OIDC authentication for GitHub Actions"
    Environment = "shared"
  }
}

# Attach permissions for Terraform to manage infrastructure
resource "aws_iam_role_policy" "github_actions_terraform" {
  name = "terraform-permissions"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:*",
          "s3:*",
          "iam:*",
          "logs:*",
          "cloudwatch:*"
        ]
        Resource = "*"
      }
    ]
  })
}

output "github_actions_role_arn" {
  description = "ARN of IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions.arn
}
```

### CREATE /workspace/workspace/homebase-infra/.github/workflows/terraform-plan.yml

- **IMPLEMENT**: GitHub Actions workflow for terraform plan on pull requests
- **PATTERN**: Plan-only on PR, never apply
- **IMPORTS**: None (GitHub Actions workflow)
- **GOTCHA**: Must have AWS OIDC provider and IAM role created first
- **VALIDATE**: Create a PR and verify workflow runs and comments plan output

```yaml
name: 'Terraform Plan'

on:
  pull_request:
    branches: [main]
    paths:
      - '**.tf'
      - '**.tfvars'
      - '.github/workflows/terraform-plan.yml'

env:
  TF_VERSION: 1.6.0
  AWS_REGION: us-east-1

permissions:
  id-token: write
  contents: read
  pull-requests: write

jobs:
  terraform-plan:
    name: Terraform Plan
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Format Check
        id: fmt
        run: terraform fmt -check -recursive
        continue-on-error: true

      - name: Terraform Init
        id: init
        run: terraform init

      - name: Terraform Validate
        id: validate
        run: terraform validate -no-color

      - name: Terraform Plan
        id: plan
        run: terraform plan -no-color -out=tfplan
        continue-on-error: true

      - name: Update Pull Request
        uses: actions/github-script@v7
        if: github.event_name == 'pull_request'
        env:
          PLAN: "${{ steps.plan.outputs.stdout }}"
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const output = `#### Terraform Format and Style 🖌\`${{ steps.fmt.outcome }}\`
            #### Terraform Initialization ⚙️\`${{ steps.init.outcome }}\`
            #### Terraform Validation 🤖\`${{ steps.validate.outcome }}\`
            #### Terraform Plan 📖\`${{ steps.plan.outcome }}\`

            <details><summary>Show Plan</summary>

            \`\`\`terraform
            ${process.env.PLAN}
            \`\`\`

            </details>

            *Pushed by: @${{ github.actor }}, Action: \`${{ github.event_name }}\`*`;

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output
            })

      - name: Terraform Plan Status
        if: steps.plan.outcome == 'failure'
        run: exit 1
```

### CREATE /workspace/workspace/homebase-infra/.github/workflows/terraform-apply.yml

- **IMPLEMENT**: GitHub Actions workflow for terraform apply on merge to main
- **PATTERN**: Automated apply only after PR is merged
- **IMPORTS**: None (GitHub Actions workflow)
- **GOTCHA**: Uses GitHub Environment for production approval gate
- **VALIDATE**: Merge a PR and verify apply runs automatically

```yaml
name: 'Terraform Apply'

on:
  push:
    branches: [main]
    paths:
      - '**.tf'
      - '**.tfvars'

env:
  TF_VERSION: 1.6.0
  AWS_REGION: us-east-1

permissions:
  id-token: write
  contents: read

jobs:
  terraform-apply:
    name: Terraform Apply
    runs-on: ubuntu-latest

    # Optional: Require manual approval for production
    # Uncomment when ready to enable production gate
    # environment: production

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        run: terraform init

      - name: Terraform Apply
        run: terraform apply -auto-approve -input=false

      - name: Notify on Failure
        if: failure()
        run: |
          echo "Terraform apply failed! Check logs immediately."
          exit 1
```

### CREATE GitHub Repository Secrets

- **IMPLEMENT**: Add AWS_ROLE_ARN secret to GitHub repository
- **PATTERN**: Store sensitive configuration in GitHub Secrets
- **IMPORTS**: None (GitHub UI)
- **GOTCHA**: Get ARN from terraform output after applying iam-github-actions.tf
- **VALIDATE**: Check Settings → Secrets and variables → Actions

```bash
# Get the role ARN
cd /workspace/workspace/homebase-infra
terraform output github_actions_role_arn

# Add to GitHub:
# 1. Go to repository Settings → Secrets and variables → Actions
# 2. Click "New repository secret"
# 3. Name: AWS_ROLE_ARN
# 4. Value: (paste the ARN from terraform output)
# 5. Click "Add secret"
```

### CREATE GitHub Environment Protection

- **IMPLEMENT**: Configure GitHub Environment for production approval
- **PATTERN**: Manual approval gate for production deployments
- **IMPORTS**: None (GitHub UI)
- **GOTCHA**: Only works with GitHub Pro or Enterprise
- **VALIDATE**: Check Settings → Environments

```
# In GitHub repository:
# 1. Go to Settings → Environments
# 2. Click "New environment"
# 3. Name: production
# 4. Check "Required reviewers"
# 5. Add reviewer(s)
# 6. Click "Save protection rules"
```

### TEST CI/CD Pipeline

- **IMPLEMENT**: End-to-end test of full CI/CD workflow
- **PATTERN**: Make a small change, create PR, verify plan, merge, verify apply
- **IMPORTS**: None
- **GOTCHA**: Use a safe change for testing (e.g., add a tag or output)
- **VALIDATE**: Full workflow completes successfully with plan comment on PR

```bash
# 1. Create a test branch
cd /workspace/workspace/homebase-infra
git checkout -b test-cicd-pipeline

# 2. Make a small, safe change (add an output)
cat >> outputs.tf << 'EOF'

output "test_cicd" {
  description = "Test output for CI/CD pipeline"
  value       = "CI/CD is working!"
}
EOF

# 3. Commit and push
git add outputs.tf
git commit -m "test: verify CI/CD pipeline"
git push origin test-cicd-pipeline

# 4. Create PR on GitHub and verify:
#    - Workflow runs automatically
#    - Plan output is commented on PR
#    - All checks pass

# 5. Merge PR and verify:
#    - Apply workflow runs automatically
#    - Infrastructure is updated
#    - No errors in workflow logs

# 6. Clean up test output
git checkout main
git pull
# Remove the test output from outputs.tf
# Commit and let CI/CD apply the cleanup
```

### PHASE 5: Cost Monitoring

### UPDATE /workspace/workspace/homebase-infra/variables.tf

- **IMPLEMENT**: Add budget limit variables
- **PATTERN**: Environment-specific budget limits
- **IMPORTS**: None
- **GOTCHA**: Different limits for different environments
- **VALIDATE**: `terraform validate`

Add to variables.tf:
```hcl
variable "budget_limit_usd" {
  description = "Monthly budget limit in USD"
  type        = number
  default     = 100

  validation {
    condition     = var.budget_limit_usd > 0
    error_message = "Budget limit must be greater than 0."
  }
}
```

### UPDATE environment tfvars files with budgets

- **IMPLEMENT**: Add budget_limit_usd to each environment tfvars
- **PATTERN**: Higher budgets for production, lower for dev
- **IMPORTS**: None
- **GOTCHA**: Adjust based on actual expected costs
- **VALIDATE**: `terraform plan -var-file=environments/development/terraform.tfvars`

Add to environments/development/terraform.tfvars:
```hcl
budget_limit_usd = 50
```

Add to environments/staging/terraform.tfvars:
```hcl
budget_limit_usd = 150
```

Add to environments/production/terraform.tfvars:
```hcl
budget_limit_usd = 500
```

### UPDATE /workspace/workspace/homebase-infra/cost-tracking.tf

- **IMPLEMENT**: Update budget resource to use variable
- **PATTERN**: Variable-driven configuration
- **IMPORTS**: None
- **GOTCHA**: None
- **VALIDATE**: `terraform apply`

Update the budget resource in cost-tracking.tf:
```hcl
resource "aws_budgets_budget" "environment_monthly" {
  name              = "${var.project_name}-${var.environment}-monthly-budget"
  budget_type       = "COST"
  limit_amount      = tostring(var.budget_limit_usd)
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2024-01-01_00:00"

  # ... rest remains the same
}
```

### CREATE /workspace/workspace/homebase-infra/anomaly-detection.tf

- **IMPLEMENT**: AWS Cost Anomaly Detection for unusual spending
- **PATTERN**: Proactive alerting on cost spikes
- **IMPORTS**: None
- **GOTCHA**: Requires 10-14 days of cost data to establish baseline
- **VALIDATE**: `terraform apply` then check AWS Cost Anomaly Detection console

```hcl
# Cost anomaly monitor for the project
resource "aws_ce_anomaly_monitor" "project_spend" {
  name              = "${var.project_name}-anomaly-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

# Subscribe to anomaly alerts
resource "aws_ce_anomaly_subscription" "project_alerts" {
  name      = "${var.project_name}-anomaly-alerts"
  frequency = "DAILY"

  monitor_arn_list = [
    aws_ce_anomaly_monitor.project_spend.arn
  ]

  subscriber {
    type    = "EMAIL"
    address = var.owner_email
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["10"]  # Alert on $10+ anomalies
    }
  }
}
```

### DOCUMENT cost optimization practices

- **IMPLEMENT**: Add cost optimization section to README
- **PATTERN**: Follow existing README structure
- **IMPORTS**: None
- **GOTCHA**: Include links to AWS Cost Explorer
- **VALIDATE**: Read through documentation for clarity

Add to README.md before "## Cleanup" section:
```markdown
## Cost Management

### Viewing Costs

1. **AWS Cost Explorer**:
   - Go to AWS Console → Billing → Cost Explorer
   - Filter by tag:
     - Environment: `development`, `staging`, `production`
     - Project: `homebase`
     - CostCenter: `ENG-001`

2. **Budget Alerts**:
   - Configured to notify at 75% and 100% of monthly budget
   - Check AWS Budgets console for current spend

### Cost Optimization Tips

- **Development**: Use `t3.micro` instances and disable Elastic IP
- **Staging**: Use `t3.small` instances, enable only when needed
- **Production**: Right-size based on actual usage metrics

### Current Cost Estimates (Monthly)

| Environment | Instance | Storage | IP | Total |
|-------------|----------|---------|-----|-------|
| Development | $7 (t3.micro) | $2 (20GB) | $0 | ~$9 |
| Staging | $15 (t3.small) | $3 (25GB) | Free | ~$18 |
| Production | $30 (t3.medium) | $3 (30GB) | Free | ~$33 |

**State Storage**: ~$0.10/month (S3 + versioning)
```

### VERIFY cost tracking

- **IMPLEMENT**: Check AWS Cost Explorer for tagged resources
- **PATTERN**: Manual verification in AWS console
- **IMPORTS**: None
- **GOTCHA**: Tags may take 24 hours to appear in Cost Explorer
- **VALIDATE**: See cost breakdown by Environment, Project, CostCenter tags

```
# After 24-48 hours of resources running:
# 1. Go to AWS Console → Cost Management → Cost Explorer
# 2. Click "Tags" on left sidebar
# 3. Verify these tags are available for filtering:
#    - Environment
#    - Project
#    - CostCenter
#    - Owner
# 4. Create a cost report filtered by Environment=production
# 5. Save the report for regular monitoring
```

### PHASE 6: Documentation and Operations

### CREATE /workspace/workspace/homebase-infra/docs/SETUP.md

- **IMPLEMENT**: Team onboarding guide
- **PATTERN**: Step-by-step instructions for new team members
- **IMPORTS**: None
- **GOTCHA**: Test with a new team member to validate clarity
- **VALIDATE**: New team member can follow and deploy successfully

```markdown
# Team Setup Guide

## Prerequisites

- AWS account access with administrator permissions
- GitHub account with repository access
- Local development environment:
  - Terraform 1.5+ installed
  - AWS CLI configured
  - Git installed
  - Python 3.11+ with pip (for pre-commit)

## Initial Setup (One-time)

### 1. Clone Repository

\`\`\`bash
git clone https://github.com/ksizzle88/homebase-infra.git
cd homebase-infra
\`\`\`

### 2. Install Pre-commit Hooks

\`\`\`bash
# Install pre-commit framework
pip install pre-commit

# Install git hooks
pre-commit install

# Test hooks
pre-commit run --all-files
\`\`\`

### 3. Install Additional Tools

**macOS:**
\`\`\`bash
brew install tflint terraform-docs trivy checkov
\`\`\`

**Ubuntu:**
\`\`\`bash
pip install checkov
# Install tflint, terraform-docs, trivy manually
\`\`\`

### 4. Configure AWS CLI

\`\`\`bash
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Default region: us-east-1
# Default output format: json
\`\`\`

## Development Workflow

### Making Changes

1. **Create a feature branch:**
   \`\`\`bash
   git checkout -b feature/your-change-description
   \`\`\`

2. **Make your infrastructure changes:**
   - Edit .tf files as needed
   - Update documentation if needed
   - Follow existing patterns and naming conventions

3. **Test locally:**
   \`\`\`bash
   terraform init
   terraform plan -var-file=environments/development/terraform.tfvars
   \`\`\`

4. **Commit changes:**
   \`\`\`bash
   git add .
   git commit -m "feat: description of your change"
   # Pre-commit hooks run automatically
   \`\`\`

5. **Push and create PR:**
   \`\`\`bash
   git push origin feature/your-change-description
   # Create pull request on GitHub
   \`\`\`

6. **Review plan output:**
   - GitHub Actions will automatically comment with terraform plan
   - Review the plan carefully
   - Request peer review

7. **Merge:**
   - After approval, merge PR
   - GitHub Actions will automatically apply changes

## Environment-Specific Deployments

### Development
\`\`\`bash
terraform plan -var-file=environments/development/terraform.tfvars
terraform apply -var-file=environments/development/terraform.tfvars
\`\`\`

### Staging
\`\`\`bash
terraform plan -var-file=environments/staging/terraform.tfvars
terraform apply -var-file=environments/staging/terraform.tfvars
\`\`\`

### Production
\`\`\`bash
terraform plan -var-file=environments/production/terraform.tfvars
terraform apply -var-file=environments/production/terraform.tfvars
\`\`\`

## Common Commands

\`\`\`bash
# Format code
terraform fmt -recursive

# Validate configuration
terraform validate

# View current state
terraform show

# List all resources
terraform state list

# View outputs
terraform output

# Run security scan manually
trivy config .
checkov -d .
\`\`\`

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.
```

### CREATE /workspace/workspace/homebase-infra/docs/DEPLOYMENT.md

- **IMPLEMENT**: Deployment procedures and workflows
- **PATTERN**: Operational runbook format
- **IMPORTS**: None
- **GOTCHA**: Document emergency procedures clearly
- **VALIDATE**: Follow procedure for a test deployment

```markdown
# Deployment Procedures

## Standard Deployment (via CI/CD)

### 1. Development Environment

Development deployments happen automatically on every push to `develop` branch (if using branch-based workflow) or via environment-specific PR workflow.

**Process:**
1. Create PR with infrastructure changes
2. Review terraform plan output in PR comments
3. Merge PR after approval
4. GitHub Actions automatically applies changes

### 2. Production Environment

Production deployments require manual approval (if environment protection enabled).

**Process:**
1. Create PR targeting `main` branch
2. Review terraform plan output
3. Get approval from 2+ team members
4. Merge PR
5. GitHub Actions pauses for manual approval
6. Designated approver reviews and approves deployment
7. Changes applied automatically

## Manual Deployment (Emergency)

If CI/CD is unavailable, use manual deployment:

\`\`\`bash
# 1. Ensure you're on the correct branch
git checkout main
git pull origin main

# 2. Initialize Terraform
terraform init

# 3. Select environment
export ENV=production  # or staging, development

# 4. Plan changes
terraform plan -var-file=environments/${ENV}/terraform.tfvars -out=tfplan

# 5. Review plan carefully
terraform show tfplan

# 6. Apply (after approval)
terraform apply tfplan

# 7. Verify
terraform output
\`\`\`

## Rollback Procedure

### Using State Versioning

\`\`\`bash
# 1. List state versions in S3
aws s3api list-object-versions \
  --bucket homebase-terraform-state \
  --prefix homebase/terraform.tfstate

# 2. Download previous version
aws s3api get-object \
  --bucket homebase-terraform-state \
  --key homebase/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.backup

# 3. Review the previous state
terraform show terraform.tfstate.backup

# 4. Restore state (CAREFUL!)
aws s3 cp terraform.tfstate.backup s3://homebase-terraform-state/homebase/terraform.tfstate

# 5. Run terraform plan to verify
terraform plan
\`\`\`

### Using Git Revert

\`\`\`bash
# 1. Identify the bad commit
git log --oneline

# 2. Revert the commit
git revert <COMMIT_SHA>

# 3. Push revert
git push origin main

# 4. CI/CD will apply the rollback automatically
\`\`\`

## Disaster Recovery

### State File Corruption

1. **Restore from S3 versioning** (see Rollback Procedure)
2. **Verify restored state**: `terraform plan` should show no changes
3. **If state is lost**: Use `terraform import` to rebuild state

### Complete Infrastructure Loss

1. **Restore state file** from S3 versioning
2. **Run terraform apply** to recreate all resources
3. **Verify all outputs** match expected values
4. **Test connectivity** to all resources

## Pre-Deployment Checklist

- [ ] Changes reviewed by at least one team member
- [ ] Terraform plan shows expected changes only
- [ ] No HIGH/CRITICAL security findings in scans
- [ ] Documentation updated if needed
- [ ] Rollback plan identified
- [ ] Maintenance window scheduled (for production)
- [ ] Team notified of deployment

## Post-Deployment Checklist

- [ ] Verify all outputs are correct
- [ ] Test infrastructure functionality
- [ ] Check CloudWatch for errors
- [ ] Monitor costs in Cost Explorer
- [ ] Update change log
- [ ] Notify team of successful deployment
```

### CREATE /workspace/workspace/homebase-infra/docs/TROUBLESHOOTING.md

- **IMPLEMENT**: Common issues and solutions
- **PATTERN**: Problem/Solution format
- **IMPORTS**: None
- **GOTCHA**: Update as new issues are discovered
- **VALIDATE**: Team can self-resolve common issues

```markdown
# Troubleshooting Guide

## Pre-commit Hooks

### Issue: Hooks fail with "command not found"

**Cause**: Required tools not installed

**Solution**:
\`\`\`bash
# macOS
brew install tflint terraform-docs trivy checkov

# Ubuntu
pip install checkov
# Install tflint, terraform-docs, trivy manually
\`\`\`

### Issue: Hooks take too long

**Cause**: Large codebase or slow scanning

**Solution**: Increase parallelism in `.pre-commit-config.yaml`:
\`\`\`yaml
- id: terraform_fmt
  args: ['--hook-config=--parallelism-limit=CPU*4']
\`\`\`

## Terraform State

### Issue: "Error acquiring the state lock"

**Cause**: Another terraform process is running or crashed

**Solution**:
\`\`\`bash
# Check for running terraform processes
ps aux | grep terraform

# If no processes, force unlock (use with caution!)
terraform force-unlock <LOCK_ID>
\`\`\`

### Issue: "State file not found"

**Cause**: Backend not initialized or configured incorrectly

**Solution**:
\`\`\`bash
# Reinitialize backend
terraform init -reconfigure

# Verify backend configuration
cat backend.tf
\`\`\`

### Issue: "State file version too new"

**Cause**: State was modified by newer Terraform version

**Solution**:
\`\`\`bash
# Upgrade Terraform to at least version shown in error
# Or restore previous state version from S3
\`\`\`

## GitHub Actions

### Issue: "Error: OIDC token verification failed"

**Cause**: GitHub OIDC provider not configured in AWS

**Solution**:
1. Verify OIDC provider exists in AWS IAM
2. Check trust policy on IAM role
3. Ensure repository name matches in trust policy

### Issue: "Error: AccessDenied"

**Cause**: IAM role lacks required permissions

**Solution**: Add missing permissions to IAM role policy

### Issue: Plan comment not appearing on PR

**Cause**: GitHub token lacks permissions

**Solution**: Ensure workflow has `pull-requests: write` permission

## AWS Resources

### Issue: Cannot SSH to instance

**Cause**: Security group or key issues

**Solution**:
1. Verify security group allows your IP: `aws ec2 describe-security-groups`
2. Check instance is running: `aws ec2 describe-instances`
3. Verify SSH key path is correct
4. Get current IP: `curl ifconfig.me`

### Issue: Elastic IP not attaching

**Cause**: EIP limit reached or instance not ready

**Solution**:
\`\`\`bash
# Check EIP limits
aws ec2 describe-account-attributes --attribute-names vpc-max-elastic-ips

# Manually attach EIP
aws ec2 associate-address --instance-id <INSTANCE_ID> --allocation-id <EIP_ID>
\`\`\`

## Cost Tracking

### Issue: Tags not appearing in Cost Explorer

**Cause**: Tags not activated or waiting period not elapsed

**Solution**:
1. Wait 24-48 hours after tag creation
2. Verify tags are activated: AWS Billing → Cost Allocation Tags
3. Ensure resources were created AFTER tag activation

### Issue: Budget alerts not received

**Cause**: Email not confirmed or budget threshold not reached

**Solution**:
1. Check email for AWS subscription confirmation
2. Verify budget configuration in AWS Budgets console
3. Check spam folder for alert emails

## Security Scans

### Issue: Checkov fails with many errors

**Cause**: Strict default security policies

**Solution**: Skip non-applicable checks in `.checkov.yaml`:
\`\`\`yaml
skip-checks:
  - CKV_AWS_123  # Reason for skipping
\`\`\`

### Issue: Trivy shows vulnerabilities in .terraform/

**Cause**: Scanning temporary files

**Solution**: Add exclude pattern to `.pre-commit-config.yaml`:
\`\`\`yaml
- id: terraform_trivy
  exclude: '.terraform/'
\`\`\`

## General

### Issue: "Module not found"

**Cause**: Modules not downloaded

**Solution**:
\`\`\`bash
terraform init
\`\`\`

### Issue: "Provider not installed"

**Cause**: Provider cache not initialized

**Solution**:
\`\`\`bash
terraform init -upgrade
\`\`\`

## Getting Help

If you encounter an issue not listed here:

1. Check Terraform documentation: https://www.terraform.io/docs
2. Search GitHub Issues: https://github.com/ksizzle88/homebase-infra/issues
3. Ask in team Slack channel
4. Create new issue with reproduction steps
```

### CREATE /workspace/workspace/homebase-infra/docs/ARCHITECTURE.md

- **IMPLEMENT**: Architecture decisions and rationale
- **PATTERN**: ADR (Architecture Decision Record) format
- **IMPORTS**: None
- **GOTCHA**: Document "why" not just "what"
- **VALIDATE**: Team understands architectural choices

```markdown
# Architecture Documentation

## Overview

The homebase-infra repository manages AWS infrastructure using Terraform with modern DevOps practices including automated CI/CD, security scanning, and cost tracking.

## Design Decisions

### 1. Remote State with S3-Native Locking

**Decision**: Use S3 for state storage with S3-native locking (Terraform 1.10.0+)

**Rationale**:
- S3-native locking is simpler than DynamoDB approach
- Lower cost (~$0.05/month vs $0.50-2.00/month with DynamoDB)
- Fewer IAM permissions required
- Better integration with S3 versioning for rollback

**Alternatives Considered**:
- DynamoDB locking: More complex, higher cost
- Terraform Cloud: Commercial solution, vendor lock-in
- Local state: Not suitable for team collaboration

### 2. Provider Default Tags

**Decision**: Use `default_tags` in AWS provider configuration

**Rationale**:
- Consistent tagging across all resources automatically
- Reduces code duplication (no manual tags on every resource)
- Easy to update organization-wide tags
- Supports cost allocation and resource management

**Implementation**:
```hcl
provider "aws" {
  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      # ...
    }
  }
}
```

### 3. GitHub Actions with OIDC

**Decision**: Use GitHub Actions with OIDC authentication to AWS

**Rationale**:
- No long-lived credentials stored in GitHub
- Short-lived tokens for each workflow run
- Better security posture
- Automatic credential rotation
- AWS updated to trust GitHub directly (no manual thumbprint updates)

**Alternatives Considered**:
- AWS access keys in secrets: Long-lived credentials, security risk
- Self-hosted runners: Additional infrastructure to manage

### 4. Multi-Tool Security Scanning

**Decision**: Use both Trivy and Checkov for security scanning

**Rationale**:
- Trivy: Modern, fast, actively maintained (replaced tfsec)
- Checkov: Comprehensive compliance checks (CIS, PCI-DSS, etc.)
- Complementary coverage - different tools catch different issues
- Low overhead when run in parallel

**Tools Configuration**:
- Trivy: HIGH/CRITICAL findings
- Checkov: Framework-specific policies
- Pre-commit: Local scanning before commit
- CI/CD: Automated scanning on every PR

### 5. Environment-Specific tfvars

**Decision**: Use separate tfvars files per environment

**Rationale**:
- Clear separation of environment configurations
- Easy to see differences between environments
- Version controlled alongside code
- Supports Terraform workspaces or backend key per environment

**Structure**:
```
environments/
├── development/terraform.tfvars
├── staging/terraform.tfvars
└── production/terraform.tfvars
```

### 6. Cost Allocation Tags

**Decision**: Implement comprehensive tagging strategy for cost tracking

**Rationale**:
- Enables cost attribution by environment, project, team
- Supports budget alerts and anomaly detection
- Required for FinOps and cost optimization
- Compliance requirement for many organizations

**Tag Strategy**:
- Environment: development, staging, production
- Project: homebase
- Owner: devops-team@company.com
- CostCenter: ENG-001
- ManagedBy: Terraform

## Infrastructure Components

### Networking
- **VPC**: 10.0.0.0/16 CIDR block
- **Subnets**: Public subnet in single AZ (cost optimization)
- **Internet Gateway**: For public internet access
- **Route Tables**: Public routing to internet

### Compute
- **EC2 Instances**: Ubuntu 24.04 with Docker pre-installed
- **Instance Types**: Environment-specific sizing
  - Development: t3.micro
  - Staging: t3.small
  - Production: t3.medium
- **Storage**: GP3 EBS volumes with encryption

### Security
- **Security Groups**: Least-privilege ingress rules
- **SSH Access**: Restricted by IP in production
- **EBS Encryption**: Enabled for all volumes
- **State Encryption**: AES256 server-side encryption in S3

### Cost Management
- **Budgets**: Per-environment monthly limits
- **Anomaly Detection**: Alerts on unusual spending
- **Tagging**: Comprehensive cost allocation tags
- **Rightsizing**: Environment-specific instance types

## CI/CD Pipeline

### Pull Request Workflow
1. Developer creates PR
2. GitHub Actions runs:
   - `terraform fmt` check
   - `terraform validate`
   - `terraform plan`
   - Security scans (Trivy, Checkov)
3. Plan output commented on PR
4. Team reviews plan and code
5. PR approved and merged

### Deployment Workflow
1. PR merged to main branch
2. GitHub Actions runs:
   - `terraform init`
   - `terraform apply -auto-approve`
3. Infrastructure updated
4. Success/failure notification

### Safety Mechanisms
- Branch protection: Requires PR reviews
- Environment protection: Manual approval for production
- State locking: Prevents concurrent modifications
- Plan review: Changes visible before apply

## Disaster Recovery

### State File Recovery
1. S3 versioning enabled on state bucket
2. Can restore any previous state version
3. Automated backup retention

### Infrastructure Recovery
1. State file contains complete infrastructure definition
2. `terraform apply` recreates all resources from state
3. Recovery time: ~10-15 minutes

### Rollback Procedures
1. Git revert for code changes
2. S3 version restore for state corruption
3. CI/CD automatically applies rollback

## Monitoring and Alerting

### Cost Monitoring
- AWS Cost Explorer with tag filtering
- Budget alerts at 75% and 100%
- Anomaly detection for unusual spending

### Security Monitoring
- Pre-commit scans before code is committed
- CI/CD scans on every PR
- GitHub Security tab for vulnerability tracking

### Infrastructure Monitoring
- CloudWatch for EC2 metrics (future enhancement)
- AWS Health Dashboard for service issues

## Future Enhancements

### Planned Improvements
1. Multi-region deployment support
2. Auto Scaling Groups for compute
3. CloudWatch dashboards and alarms
4. Automated instance scheduling (cost optimization)
5. Infrastructure testing with Terratest
6. Custom Sentinel/OPA policies
7. Atlantis for enhanced PR workflow

### Scalability Considerations
- Modularize VPC, compute, and networking
- Implement module registry
- Add integration tests
- Enhance monitoring and alerting
```

### UPDATE /workspace/workspace/homebase-infra/README.md

- **IMPLEMENT**: Update main README with new structure and workflows
- **PATTERN**: Follow existing README structure but expand significantly
- **IMPORTS**: None
- **GOTCHA**: Keep quick start simple, link to detailed docs
- **VALIDATE**: New team member can understand from README alone

Add/update these sections in README.md:

```markdown
# Homebase Infrastructure

Production-ready Terraform infrastructure for AWS with automated CI/CD, security scanning, and cost tracking.

## Features

- ✅ **Remote State Management**: S3-backed state with encryption and versioning
- ✅ **Automated CI/CD**: GitHub Actions for plan and apply workflows
- ✅ **Security Scanning**: Trivy and Checkov pre-commit and CI/CD integration
- ✅ **Cost Tracking**: Budget alerts and anomaly detection by environment
- ✅ **Multi-Environment**: Separate configurations for dev, staging, production
- ✅ **Quality Gates**: Pre-commit hooks for formatting and validation
- ✅ **Team Collaboration**: PR-based workflow with plan previews

## Quick Start

### For Team Members

See [docs/SETUP.md](docs/SETUP.md) for detailed onboarding instructions.

```bash
# 1. Clone repository
git clone https://github.com/ksizzle88/homebase-infra.git
cd homebase-infra

# 2. Install pre-commit hooks
pip install pre-commit
pre-commit install

# 3. Make changes and create PR
git checkout -b feature/your-change
# ... make changes ...
git commit -m "feat: your change description"
git push origin feature/your-change
```

## Documentation

- [Setup Guide](docs/SETUP.md) - Team onboarding
- [Deployment Procedures](docs/DEPLOYMENT.md) - How to deploy
- [Architecture](docs/ARCHITECTURE.md) - Design decisions
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues

## Repository Structure

```
homebase-infra/
├── .github/workflows/      # CI/CD workflows
│   ├── terraform-plan.yml  # PR plan workflow
│   └── terraform-apply.yml # Auto-apply on merge
├── docs/                   # Documentation
│   ├── SETUP.md
│   ├── DEPLOYMENT.md
│   ├── ARCHITECTURE.md
│   └── TROUBLESHOOTING.md
├── environments/           # Environment-specific configs
│   ├── development/
│   ├── staging/
│   └── production/
├── backend.tf              # S3 backend configuration
├── providers.tf            # AWS provider with default tags
├── main.tf                 # Primary infrastructure
├── variables.tf            # Input variables
├── outputs.tf              # Output values
├── locals.tf               # Local computed values
├── cost-tracking.tf        # Budget and cost monitoring
├── anomaly-detection.tf    # Cost anomaly alerts
├── iam-github-actions.tf   # IAM role for CI/CD
├── .pre-commit-config.yaml # Pre-commit hooks
├── .tflint.hcl             # TFLint configuration
└── .checkov.yaml           # Security scan configuration
```

## Workflows

### Making Changes

1. Create feature branch: `git checkout -b feature/description`
2. Make infrastructure changes
3. Commit: `git commit -m "feat: description"` (pre-commit hooks run)
4. Push: `git push origin feature/description`
5. Create PR on GitHub
6. Review terraform plan in PR comments
7. Merge after approval
8. Changes applied automatically

### Environment Deployments

Changes are deployed per environment using separate tfvars files:

```bash
# Development
terraform plan -var-file=environments/development/terraform.tfvars

# Staging
terraform plan -var-file=environments/staging/terraform.tfvars

# Production (requires approval)
terraform plan -var-file=environments/production/terraform.tfvars
```

## Security

### Pre-commit Hooks
- `terraform fmt`: Code formatting
- `terraform validate`: Syntax validation
- `terraform_trivy`: Vulnerability scanning
- `terraform_checkov`: Compliance checks
- `terraform_docs`: Documentation generation

### CI/CD Scans
- Trivy: Infrastructure vulnerability scanning
- Checkov: CIS compliance and best practices
- GitHub Security: SARIF upload for tracking

### Authentication
- GitHub Actions uses OIDC (no stored credentials)
- AWS IAM role with least-privilege permissions
- State file encrypted with AES256

## Cost Management

### Current Estimates (Monthly)

| Environment | Instance | Storage | Total |
|-------------|----------|---------|-------|
| Development | $7 | $2 | ~$9 |
| Staging | $15 | $3 | ~$18 |
| Production | $30 | $3 | ~$33 |

### Cost Tracking
- Budget alerts at 75% and 100% of limit
- Anomaly detection for unusual spending
- Cost Explorer filtering by environment, project, team

### View Costs
```bash
# AWS Console → Cost Explorer
# Filter by tags:
# - Environment: development/staging/production
# - Project: homebase
# - CostCenter: ENG-001
```

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues.

**Quick fixes:**

- State lock: `terraform force-unlock <LOCK_ID>`
- Hooks fail: Install tools with `brew install tflint terraform-docs trivy checkov`
- Can't SSH: Check security group allows your IP with `curl ifconfig.me`

## Contributing

1. Follow conventional commit format: `type: description`
   - `feat:` for new features
   - `fix:` for bug fixes
   - `docs:` for documentation
   - `chore:` for maintenance
2. Ensure pre-commit hooks pass
3. Include tests for infrastructure changes
4. Update documentation as needed

## Support

- GitHub Issues: https://github.com/ksizzle88/homebase-infra/issues
- Team Slack: #infrastructure channel
- Terraform Docs: https://www.terraform.io/docs
```

---

## TESTING STRATEGY

### Unit Tests (Terraform Validation)

**Scope**: Syntax correctness and configuration validation

**Commands**:
```bash
terraform fmt -check -recursive
terraform validate
tflint --config=.tflint.hcl
```

**Coverage**: All .tf files

### Integration Tests (Security Scans)

**Scope**: Security compliance and best practices

**Commands**:
```bash
trivy config . --severity HIGH,CRITICAL
checkov -d . --config-file .checkov.yaml
```

**Coverage**: Infrastructure security, CIS compliance

### End-to-End Tests (Deployment Verification)

**Scope**: Full deployment cycle

**Procedure**:
1. Create test branch with small change (add tag or output)
2. Create PR and verify plan workflow runs
3. Verify plan output is commented on PR
4. Merge PR and verify apply workflow runs
5. Verify infrastructure change is applied
6. Verify state is updated in S3
7. Clean up test change

---

## VALIDATION COMMANDS

Execute every command to ensure zero regressions and 100% feature correctness.

### Level 1: Syntax & Style

```bash
# Format check
terraform fmt -check -recursive

# Expected: No files need formatting
# If files listed, run: terraform fmt -recursive

# Validate syntax
terraform validate

# Expected: Success! The configuration is valid.

# TFLint
tflint --config=.tflint.hcl --init
tflint --config=.tflint.hcl

# Expected: No issues found
```

### Level 2: Security Scans

```bash
# Trivy security scan
trivy config . --severity HIGH,CRITICAL --exit-code 1

# Expected: No HIGH or CRITICAL vulnerabilities

# Checkov compliance scan
checkov -d . --config-file .checkov.yaml --compact

# Expected: All checks pass or skipped with reason
```

### Level 3: Pre-commit Validation

```bash
# Run all pre-commit hooks
pre-commit run --all-files

# Expected: All hooks pass
```

### Level 4: Terraform Plan

```bash
# Development environment
terraform init
terraform plan -var-file=environments/development/terraform.tfvars

# Expected: Plan shows expected changes only

# Staging environment
terraform plan -var-file=environments/staging/terraform.tfvars

# Production environment
terraform plan -var-file=environments/production/terraform.tfvars
```

### Level 5: CI/CD Workflow

```bash
# Create test branch
git checkout -b test/validate-cicd
echo "# Test" >> docs/TEST.md
git add docs/TEST.md
git commit -m "test: validate CI/CD pipeline"
git push origin test/validate-cicd

# Expected:
# 1. GitHub Actions workflow triggers
# 2. Plan workflow runs successfully
# 3. Plan output commented on PR
# 4. Security scans pass

# Create PR and verify workflow
# Merge PR and verify apply workflow
# Delete test branch
```

### Level 6: Manual Infrastructure Verification

```bash
# Verify remote state
aws s3 ls s3://homebase-terraform-state/homebase/

# Expected: terraform.tfstate file exists

# Verify state locking works
terraform plan &
terraform plan &
# Expected: Second command waits for lock or fails with lock error

# Verify cost allocation tags are active
aws ce list-cost-allocation-tags --status Active

# Expected: Environment, Project, CostCenter, Owner tags listed

# Verify budget exists
aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text)

# Expected: Budget(s) listed with correct configuration

# Verify IAM role for GitHub Actions
aws iam get-role --role-name github-actions-terraform-role

# Expected: Role exists with OIDC trust policy
```

---

## ACCEPTANCE CRITERIA

- [ ] Remote state configured with S3 and S3-native locking
- [ ] State migration completed successfully (local state removed)
- [ ] Provider default tags configured and propagating to all resources
- [ ] Environment-specific tfvars files created (dev, staging, prod)
- [ ] Cost allocation tags activated in AWS Billing console
- [ ] Pre-commit hooks configured and passing locally
- [ ] Security scans (Trivy, Checkov) passing with zero CRITICAL/HIGH findings
- [ ] GitHub Actions OIDC authentication configured with AWS
- [ ] Terraform plan workflow running on pull requests
- [ ] Plan output commented automatically on PRs
- [ ] Terraform apply workflow running on merge to main
- [ ] Budget alerts configured for all environments
- [ ] Cost anomaly detection configured and subscribed
- [ ] Documentation complete (SETUP, DEPLOYMENT, ARCHITECTURE, TROUBLESHOOTING)
- [ ] Main README updated with new structure and workflows
- [ ] Full deployment cycle tested end-to-end successfully
- [ ] Team can view costs by Environment, Project, CostCenter tags
- [ ] All validation commands pass with zero errors

---

## COMPLETION CHECKLIST

### Phase 1: Remote State
- [ ] backend.tf created with S3 configuration
- [ ] State bucket created with encryption and versioning
- [ ] Local state migrated to S3 successfully
- [ ] State locking verified (concurrent plans blocked)
- [ ] Local state files removed from repository

### Phase 2: Organization & Tagging
- [ ] providers.tf created with default tags
- [ ] locals.tf created with computed values
- [ ] Environment-specific tfvars files created
- [ ] Cost allocation tags activated in AWS
- [ ] Tags visible in AWS Cost Explorer

### Phase 3: Security & Quality
- [ ] .pre-commit-config.yaml created and working
- [ ] .tflint.hcl configured
- [ ] .checkov.yaml configured
- [ ] Pre-commit hooks installed locally
- [ ] All security scans passing

### Phase 4: CI/CD
- [ ] AWS OIDC provider created for GitHub
- [ ] IAM role for GitHub Actions created
- [ ] GitHub repository secret AWS_ROLE_ARN added
- [ ] terraform-plan.yml workflow created
- [ ] terraform-apply.yml workflow created
- [ ] Full CI/CD workflow tested successfully

### Phase 5: Cost Monitoring
- [ ] Budget resources created per environment
- [ ] Budget alerts configured
- [ ] Anomaly detection configured
- [ ] Cost tracking documented
- [ ] Costs visible in Cost Explorer by tags

### Phase 6: Documentation
- [ ] docs/SETUP.md created
- [ ] docs/DEPLOYMENT.md created
- [ ] docs/TROUBLESHOOTING.md created
- [ ] docs/ARCHITECTURE.md created
- [ ] README.md updated
- [ ] All documentation reviewed and validated

---

## NOTES

### Design Philosophy

This implementation prioritizes **safety, collaboration, and visibility**:

- **Safety**: Remote state, locking, and automated validation prevent common mistakes
- **Collaboration**: PR-based workflow with plan previews enables team review
- **Visibility**: Cost tracking and security scanning provide operational insight
- **Automation**: CI/CD reduces manual work and ensures consistency
- **Quality**: Pre-commit hooks and security scans catch issues early

### Technology Choices

**S3-Native Locking vs DynamoDB**:
- Chose S3-native locking (Terraform 1.10.0+) for simplicity and cost
- Eliminates DynamoDB complexity and reduces cost by ~$0.50-2.00/month per environment
- Simpler IAM permissions

**Trivy vs tfsec**:
- Chose Trivy as primary scanner (tfsec deprecated)
- Added Checkov for compliance checks (CIS, PCI-DSS)
- Complementary coverage from both tools

**GitHub Actions vs Alternatives**:
- Native GitHub integration
- OIDC authentication eliminates stored credentials
- Free for public repos, cost-effective for private repos
- Mature Terraform Actions ecosystem

### Implementation Order Rationale

1. **Remote State First**: Foundation for all other work
2. **Organization Second**: Structure must exist before automation
3. **Security Third**: Quality gates before automation
4. **CI/CD Fourth**: Automate after manual process works
5. **Cost Fifth**: Tags must exist and propagate first
6. **Documentation Last**: Captures learnings from implementation

### Common Pitfalls to Avoid

1. **Don't skip state migration validation**: Always verify state after migration
2. **Don't commit secrets**: Use environment variables and AWS Secrets Manager
3. **Don't disable security scans**: Fix issues or document skip reasons
4. **Don't apply without review**: Always review plan output before apply
5. **Don't ignore cost alerts**: Investigate immediately to prevent runaway costs

### Estimated Timeline

- **Phase 1 (Remote State)**: 2-3 hours
- **Phase 2 (Organization)**: 2-3 hours
- **Phase 3 (Security)**: 1-2 hours
- **Phase 4 (CI/CD)**: 3-4 hours
- **Phase 5 (Cost)**: 1-2 hours
- **Phase 6 (Documentation)**: 2-3 hours

**Total**: 11-17 hours over 2-3 days

### Cost Impact

**New Monthly Costs**:
- S3 state bucket: ~$0.05/month
- State versioning: ~$0.05/month
- Budget resources: Free
- Anomaly detection: Free
- **Total**: ~$0.10/month

**Potential Savings**:
- Right-sized instances: $10-30/month
- Automated shutdown schedules (future): $50-100/month
- Cost visibility enables optimization: Variable

### Security Considerations

- State file contains sensitive data (encrypted at rest)
- GitHub Actions has least-privilege AWS access
- Security groups restrict SSH to known IPs in production
- All EBS volumes encrypted
- Pre-commit hooks prevent committing secrets

### Next Steps After Implementation

1. **Week 1**: Monitor CI/CD workflows, fix any issues
2. **Week 2**: Review cost allocation, adjust budgets if needed
3. **Month 1**: Implement automated instance scheduling for cost optimization
4. **Month 2**: Add CloudWatch monitoring and alerting
5. **Quarter 1**: Modularize infrastructure for reusability
6. **Quarter 2**: Implement automated testing with Terratest
