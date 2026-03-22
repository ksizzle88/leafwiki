# Terraform Style Guide (Project Conventions)

Based on HashiCorp official style guide. See `./hashicorp-official/terraform/code-generation/skills/terraform-style-guide/SKILL.md` for the full reference.

## File Organization

| File | Purpose |
|------|---------|
| `_config.tf` | Load and merge YAML configurations |
| `_providers.tf` | AWS, Snowflake, Vault, AzureAD providers |
| `_backend.tf` | Terraform state backend |
| `_context.tf` | Account context module |
| `_data.tf` | Data sources |
| `_variables.tf` | Input variable declarations |
| `_outputs.tf` | Output value declarations |
| `main.tf` | Account-level modules (security, SSO, storage) |
| `roles.tf` | Database/warehouse creation + role hierarchy |
| `service_users.tf` | Service account profiles |
| `databases.tf` | Database profiles |
| `import.tf` | Import and moved blocks |
| `config.yml` | Environment-specific YAML configuration |

Note: This project prefixes infrastructure files with `_` to sort them before
business logic files.

## Code Formatting

- Two spaces per nesting level (no tabs)
- Align equals signs for consecutive arguments
- Arguments before blocks, meta-arguments first
- `lifecycle` block always last

## Naming

- Lowercase with underscores for all Terraform names
- UPPERCASE for Snowflake object names (roles, databases, warehouses)
- Descriptive nouns excluding resource type
- Default to `this` for single-instance resources in modules

## Variables

Every variable must include `type` and `description`:

```hcl
variable "disabled" {
  description = "Whether the service user is disabled"
  type        = string
  default     = null
}
```

## Module Patterns

This project uses a profile pattern:

```
modules/
  resource_type/
    _base/          # Base module with all configuration
    profiles/
      profile_name/ # Thin wrapper that configures _base
```

Environments call profiles, profiles call `_base`.

## Import Blocks (Terraform 1.5+)

Prefer config-driven imports over CLI imports:

```hcl
import {
  to = module.standard_roles.snowflake_account_role.this["ROLE_NAME"]
  id = "ROLE_NAME"
}
```

## Moved Blocks (Terraform 1.1+)

Use for address refactoring without destroy/create:

```hcl
moved {
  from = module.old.snowflake_account_role.this["KEY"]
  to   = module.new.snowflake_account_role.this["KEY"]
}
```

## Validation

Always run before committing:

```bash
terraform fmt -recursive
terraform validate
```
