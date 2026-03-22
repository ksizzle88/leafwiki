# Snowflake Import ID Formats

Quick reference for Snowflake provider resource import IDs.

## Account-Level Resources

| Resource Type | Import ID Format | Example |
|---|---|---|
| `snowflake_account_role` | `ROLE_NAME` | `DATA_DEVELOPER__ALL` |
| `snowflake_user` | `USER_NAME` | `AIRFLOW_USER` |
| `snowflake_service_user` | `USER_NAME` | `MP_DBT_USER` |
| `snowflake_database` | `DB_NAME` | `MPONE_DB` |
| `snowflake_warehouse` | `WH_NAME` | `COMPUTE_WH` |
| `snowflake_network_policy` | `POLICY_NAME` | `ALLOW_PRIVATELINK` |
| `snowflake_network_rule` | `DB_NAME\|SCHEMA\|RULE_NAME` | `SNOWFLAKE\|NETWORK_RULES\|ALLOW_VPC` |
| `snowflake_storage_integration` | `INTEGRATION_NAME` | `S3_STORAGE` |

## Database-Level Resources

| Resource Type | Import ID Format | Example |
|---|---|---|
| `snowflake_database_role` | `DB_NAME\|ROLE_NAME` | `MPONE_DB\|_READ` |
| `snowflake_schema` | `DB_NAME\|SCHEMA_NAME` | `MPONE_DB\|RAW` |
| `snowflake_table` | `DB_NAME\|SCHEMA\|TABLE` | `MPONE_DB\|RAW\|USERS` |
| `snowflake_stage` | `DB_NAME\|SCHEMA\|STAGE` | `MPONE_DB\|RAW\|S3_STAGE` |
| `snowflake_pipe` | `DB_NAME\|SCHEMA\|PIPE` | `MPONE_DB\|RAW\|S3_PIPE` |

## Grant Resources

| Resource Type | Import ID Format | Example |
|---|---|---|
| `snowflake_grant_account_role` | `ROLE\|GRANT_TYPE\|GRANTEE_TYPE\|GRANTEE` | `READ_ONLY__ALL\|USAGE\|ROLE\|SYSADMIN` |
| `snowflake_grant_database_role` | `DB\|ROLE\|GRANT_TYPE\|GRANTEE_TYPE\|GRANTEE` | `MPONE_DB\|_READ\|USAGE\|DATABASE_ROLE\|READ_ONLY` |
| `snowflake_grant_privileges_to_database_role` | Complex -- see provider docs | |
| `snowflake_grant_ownership` | `OBJECT_TYPE\|"OBJECT_NAME"\|OUTBOUND_PRIVILEGES\|ROLE_TYPE\|"ROLE_NAME"` | `ROLE\|"READ_ONLY__ALL"\|COPY\|ROLE\|"USERADMIN"` |

## SCIM Ownership Grant Pattern

Common in this codebase -- AAD_PROVISIONER owns SCIM-managed roles:

```hcl
import {
  to = snowflake_grant_ownership.scim_role_ownership["ROLE_NAME"]
  id = "ROLE|\"ROLE_NAME\"|COPY|ROLE|\"USERADMIN\""
}
```

## Tips

- Pipe-separated IDs use literal `|` characters
- Grant ownership IDs use escaped quotes around names: `\"NAME\"`
- When in doubt, use `terraform state show <address>` to see the ID format
  of an already-imported resource
- The `tfplan.py imports` command shows import IDs from a plan
