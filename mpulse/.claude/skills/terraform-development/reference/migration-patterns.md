# Terraform Migration Patterns

Quick reference for common migration operations in Snowflake infrastructure.

## Table of Contents
- [Import Blocks](#import-blocks)
- [Moved Blocks](#moved-blocks)
- [State Operations](#state-operations)
- [Snowflake Import ID Formats](#snowflake-import-id-formats)
- [Common Migration Workflows](#common-migration-workflows)

---

## Import Blocks

Terraform 1.5+ import blocks (preferred over `terraform import` CLI):

```hcl
# Basic import
import {
  to = snowflake_account_role.example
  id = "ROLE_NAME"
}

# Import into a module
import {
  to = module.standard_roles.snowflake_account_role.this["SUPERUSER__ALL"]
  id = "SUPERUSER__ALL"
}

# Import into for_each resource
import {
  to = snowflake_database_role.roles["READ_ONLY"]
  id = "DATABASE_NAME|READ_ONLY"
}

# Import grant
import {
  to = snowflake_grant_account_role.ownership["ROLE_NAME"]
  id = "ROLE_NAME|OWNERSHIP|ROLE|ROLE_OWNER_NAME"
}
```

### Import with Lifecycle Ignore

When importing existing resources you don't want Terraform to modify:

```hcl
resource "snowflake_account_role" "legacy" {
  name = "LEGACY_ROLE"
  lifecycle {
    ignore_changes = all
  }
}

import {
  to = snowflake_account_role.legacy
  id = "LEGACY_ROLE"
}
```

---

## Moved Blocks

Refactor resource addresses without destroying/recreating:

```hcl
# Rename a resource
moved {
  from = snowflake_account_role.old_name
  to   = snowflake_account_role.new_name
}

# Move into a module
moved {
  from = snowflake_account_role.this
  to   = module.roles.snowflake_account_role.this
}

# Move between modules
moved {
  from = module.old_module.snowflake_account_role.this["KEY"]
  to   = module.new_module.snowflake_account_role.this["KEY"]
}

# Move for_each key change
moved {
  from = module.roles.snowflake_account_role.this["old_key"]
  to   = module.roles.snowflake_account_role.this["new_key"]
}
```

---

## State Operations

When import/moved blocks aren't sufficient:

```bash
# Remove from state without destroying
terraform state rm 'module.old.snowflake_account_role.this["ROLE"]'

# Move in state (alternative to moved blocks for complex cases)
terraform state mv \
  'module.old.snowflake_account_role.this' \
  'module.new.snowflake_account_role.this'

# List resources in state
terraform state list | grep snowflake_account_role

# Show specific resource state
terraform state show 'snowflake_account_role.example'
```

---

## Snowflake Import ID Formats

### Account-Level Resources

| Resource Type | Import ID Format | Example |
|---|---|---|
| `snowflake_account_role` | `ROLE_NAME` | `DATA_DEVELOPER__ALL` |
| `snowflake_user` | `USER_NAME` | `AIRFLOW_USER` |
| `snowflake_database` | `DB_NAME` | `MPONE_DB` |
| `snowflake_warehouse` | `WH_NAME` | `COMPUTE_WH` |
| `snowflake_network_policy` | `POLICY_NAME` | `ALLOW_PRIVATELINK` |
| `snowflake_network_rule` | `DB_NAME\|SCHEMA\|RULE_NAME` | `SNOWFLAKE\|NETWORK_RULES\|ALLOW_VPC` |
| `snowflake_storage_integration` | `INTEGRATION_NAME` | `S3_STORAGE` |

### Database-Level Resources

| Resource Type | Import ID Format | Example |
|---|---|---|
| `snowflake_database_role` | `DB_NAME\|ROLE_NAME` | `MPONE_DB\|_READ` |
| `snowflake_schema` | `DB_NAME\|SCHEMA_NAME` | `MPONE_DB\|RAW` |
| `snowflake_table` | `DB_NAME\|SCHEMA\|TABLE` | `MPONE_DB\|RAW\|USERS` |
| `snowflake_stage` | `DB_NAME\|SCHEMA\|STAGE` | `MPONE_DB\|RAW\|S3_STAGE` |
| `snowflake_pipe` | `DB_NAME\|SCHEMA\|PIPE` | `MPONE_DB\|RAW\|S3_PIPE` |

### Grant Resources

| Resource Type | Import ID Format | Example |
|---|---|---|
| `snowflake_grant_account_role` | `ROLE\|GRANT_TYPE\|GRANTEE_TYPE\|GRANTEE` | `READ_ONLY__ALL\|USAGE\|ROLE\|SYSADMIN` |
| `snowflake_grant_database_role` | `DB\|ROLE\|GRANT_TYPE\|GRANTEE_TYPE\|GRANTEE` | `MPONE_DB\|_READ\|USAGE\|DATABASE_ROLE\|READ_ONLY` |
| `snowflake_grant_privileges_to_database_role` | Complex - see provider docs | |
| `snowflake_grant_ownership` | `OBJECT_TYPE\|OBJECT_NAME\|OUTBOUND_PRIVILEGES\|ROLE_TYPE\|ROLE_NAME` | `ROLE\|READ_ONLY__ALL\|COPY\|ROLE\|USERADMIN` |

---

## Common Migration Workflows

### 1. Import Existing Roles into New Module

```hcl
# Step 1: Add import blocks
import {
  to = module.standard_roles.snowflake_account_role.this["SUPERUSER__ALL"]
  id = "SUPERUSER__ALL"
}

# Step 2: Run plan to verify import matches
# Step 3: Apply to import into state
# Step 4: Remove import blocks (they're one-time)
```

### 2. Migrate Legacy Resource to Module

```hcl
# Step 1: Add moved block
moved {
  from = snowflake_account_role.superuser
  to   = module.standard_roles.snowflake_account_role.this["SUPERUSER__ALL"]
}

# Step 2: Plan to verify no destroy/create
# Step 3: Apply
# Step 4: Remove moved block and old resource definition
```

### 3. Adopt Unmanaged Resource

```hcl
# Step 1: Define resource with ignore_changes
resource "snowflake_account_role" "legacy" {
  name = "LEGACY_ROLE"
  lifecycle { ignore_changes = all }
}

# Step 2: Import
import {
  to = snowflake_account_role.legacy
  id = "LEGACY_ROLE"
}

# Step 3: Apply, then optionally remove ignore_changes to manage fully
```
