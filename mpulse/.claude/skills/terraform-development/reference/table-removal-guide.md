# Table Removal Guide

How to fully remove a table from the raw_layer pipeline.

## Steps

### 1. Find the table in config

Search `modules/hxi/raw_layer/default_config.yml` for the table name under its
database and schema block.

### 2. Check DMS references

The table entry may have a `dms:` block with a `task-name`. Before removing:

- Check if that task exists in `modules/hxi/dms/default_config.yml` and any
  env-specific DMS configs (`qa_dms_config.yml`, `stage_dms_config.yml`).
- If the task has **other tables** mapped to it, only remove this table's
  mapping — do not remove the whole task.
- If this is the **only table** on the task, remove the task entry too.

### 3. Remove the YAML block

Delete the table entry from `default_config.yml`.

### 4. Run plan

```
tf-2-claude plan
```

Expect these destroys per table removed:

| Resource | Address pattern |
|----------|----------------|
| Schema evolution table | `snowflake_table.schema_evolution_tables["DB\|SCHEMA\|TABLE"]` |
| Schema evolution exec | `snowflake_execute.schema_evolution["DB\|SCHEMA\|TABLE"]` |
| Pipe | `snowflake_pipe.pipes["DB\|SCHEMA\|PIPE_TABLE"]` |
| External table (if enabled) | `snowflake_external_table.this["DB\|SCHEMA\|TABLE"]` |

External tables only appear if `create_external_tables = true` for that schema.

### 5. Check for unexpected impacts

Verify that **no other resources** are affected. These shared resources live
at the schema level and must NOT be destroyed:

- Snowflake stage (per-schema)
- File format (per-schema)
- Schema (per-database)
- Database
- SNS topic
- S3 bucket notification

If any shared resource shows up in the plan, something else changed — investigate
before applying.

### 6. Clear S3 data (optional)

Terraform does not manage S3 data files. If the table had DMS writing to it,
data may exist at:

```
s3://{bucket}/{db}/{schema_prefix}/{table_name}/
```

Check whether the prefix exists and clear it manually if desired. This is
outside Terraform's scope.

### 7. Apply

```
tf-2-claude apply
```

## Important Notes

- **Always check DMS config first.** A table may be the only one on a DMS task,
  or share a task with others. Removing a shared task breaks other tables.
- **Pipes have `lifecycle { ignore_changes = all }`** — destroy still works.
- **Schema evolution tables** do not have `prevent_destroy` — destroy proceeds
  cleanly.
- **Prod tables**: consider whether downstream consumers (dbt models, exports,
  dashboards) depend on the table before removing it.
