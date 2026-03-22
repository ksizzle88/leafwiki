# data_ops_ingestion — Project Reference

Location: `DPI_Analytics_DBT/data_ops_ingestion/`

A dbt project that ingests Parquet files exported from SQL Server (via `snowflake-export`) into Snowflake, with a user-editable override system for managing local modifications that survive re-ingestion.

---

## Architecture Overview

```
SQL Server → snowflake-export → S3 (parquet + manifest)
                                    ↓
                        data_ops_ingestion (dbt)
                                    ↓
                    ┌───────────────┴───────────────┐
                    │                               │
            dp_config_sync DB              dp_config DB (target)
            (raw ingestion)                (merged: source + overrides)
            ├─ {schema}.{table}            ├─ {schema}.{table}
            └─ {schema}_override.{table}   ├─ stream_{table}
                                           └─ task_capture_{table}
```

**Three databases involved:**
- `dp_config_sync` — Raw ingested tables + override tables
- `dp_config` (configurable via `SYNC_TARGET_DATABASE`) — Merged production tables with streams/tasks
- S3 bucket — Parquet files + JSON manifests from `snowflake-export`

---

## Project Structure

```
data_ops_ingestion/
├── dbt_project.yml
├── scripts/run_dp_config.sh          # Main entrypoint (two-step workflow)
├── nomad/nomad-entrypoint-data-ops.sh # Nomad job wrapper
├── models/
│   ├── dp_config_sync/               # Raw ingestion sources (YAML only, virtual models)
│   │   ├── bm/    config/  etl/  hcc/  map/  override/  ref/  sdoh/  test/
│   │   ├── dp_config_sync-stages.sql
│   │   └── dp_config_sync-file_formats.sql
│   └── dp_config/                     # Override+merge models (YAML only)
│       └── models.yml                 # 340 model definitions with meta (source_schema, source_table, primary_key)
├── macros/
│   ├── ingestion/                     # 21 macros: manifest checking, staging, COPY INTO, logging
│   ├── sync/                          # 9 macros: override merge, streams, capture tasks
│   ├── schema_migration/             # 7 macros: table recreation, backup/restore
│   └── Utility/
├── analyses/
│   ├── setup_dp_config.sql           # Create all override infrastructure
│   ├── teardown_dp_config.sql        # Drop all override infrastructure
│   └── schema_migration/             # Per-schema migration + backup/restore
│       ├── backup_overrides.sql
│       ├── restore_and_cleanup_overrides.sql
│       ├── deploy_dp_config_tables.sql
│       ├── fix_existing_null_ids.sql
│       └── {bm,config,etl,hcc,map,ref,sdoh,test}/
│           ├── {schema}_tables.sql
│           ├── {schema}_override_tables.sql
│           ├── {schema}_streams.sql
│           └── {schema}_tasks.sql
├── ddl/ingestion_history.sql
└── README.md
```

---

## Two-Step Ingestion Workflow

Run via `scripts/run_dp_config.sh`:

**Step 1 — Identify pending sources:**
```
dbt run-operation get_pending_selectors
  → Reads S3 manifests (*_COMPLETE.json)
  → Compares export_time to ingestion_history
  → Outputs selectors for sources with new data
```

**Step 2 — Ingest and merge:**
```
dbt run -s {SELECTORS}
  → Per dp_config_sync model: manifest check → staging table → COPY INTO → SWAP
  → Per dp_config model: flush stream → INSERT OVERWRITE with merge_with_override → recreate stream/task
```

---

## Override System

Users can edit `dp_config.{schema}.{table}` directly (INSERT/UPDATE/DELETE). Changes are captured by Snowflake streams and persisted in override tables so they survive the next re-ingestion.

### How it works

1. **Stream** (`dp_config.{schema}.stream_{table}`) tracks DML on the production table
2. **Task** (`dp_config.{schema}.task_capture_{table}`) runs every 1 minute, MERGEs stream changes into the override table
3. **Override table** (`dp_config_sync.{schema}_override.{table}`) stores user edits with extra columns: `_is_deleted`, `_modified_at`, `_modified_by`
4. **On re-ingestion**, `merge_with_override()` produces the final table:
   - Override records (where `_is_deleted = FALSE`) win on PK match
   - Source records included only where no override exists

### Auto-ID for user inserts

Sequences (`seq_{table}_{pk}`) generate negative IDs (START=-1, INCREMENT=-1) so user-inserted rows never collide with source data PKs.

---

## Schema Migration / Redeployment

When source definitions change (e.g., column type changes), tables must be recreated while preserving override data.

### Process

```
1. Compile & run: backup_overrides.sql
   → CLONEs override tables with data to {table}__backup

2. Compile & run: {schema}/{schema}_tables.sql
   → CREATE OR REPLACE TABLE with new column types from sources.yml
   → Uses replace_dp_config_table macro (types come from data_type in sources.yml verbatim)

3. Compile & run: {schema}/{schema}_override_tables.sql
   → Recreates override tables matching new schema

4. Compile & run: {schema}/{schema}_streams.sql
   → Recreates streams on the new tables

5. Compile & run: {schema}/{schema}_tasks.sql
   → Recreates capture tasks with MERGE logic

6. Compile & run: restore_and_cleanup_overrides.sql
   → Fixes NULL IDs in backups (generates negative IDs)
   → INSERTs backup data into new override tables
   → DROPs backup tables
   → Runs each table in a transaction with rollback on error
```

All compile commands use `dbt compile --select ...` and the compiled SQL is run manually in Snowflake.

### Key macro: `replace_dp_config_table`

```sql
CREATE OR REPLACE TABLE {target_db}.{schema}.{table} (
    "{COLUMN_NAME}" {data_type} [DEFAULT seq.NEXTVAL],
    ...
);
```

The `data_type` from `sources.yml` is used **verbatim** as the Snowflake column type. Changing `NUMBER` to `FLOAT` in sources.yml directly changes the Snowflake DDL.

---

## Source Definitions

File pattern: `models/dp_config_sync/{schema}/sources.yml`

```yaml
sources:
  - name: dp_config_sync__{schema}
    database: dp_config_sync
    schema: {schema}
    tables:
      - name: {table}
        columns:
          - name: {col}
            data_type: {SNOWFLAKE_TYPE}  # Used verbatim in CREATE TABLE DDL
```

**9 schemas**: bm, config, etl, hcc, map, ref, sdoh, test (+ override)

**Supported data types**: `INTEGER`, `STRING`, `TIMESTAMP_NTZ`, `NUMBER`, `FLOAT`, `TINYINT` — anything valid in Snowflake works since it's passed through directly.

---

## dp_config Model Definitions

File: `models/dp_config/models.yml` (340 models)

```yaml
models:
  - name: dp_config-{schema}-{table}
    meta:
      source_schema: {schema}
      source_table: {table}
      primary_key: {pk_column}
```

The `dp_config_model` macro uses these meta fields to:
- Resolve the source table in `dp_config_sync`
- Build the `merge_with_override()` query
- Create streams and capture tasks
- Set up sequences and DEFAULT on PK

---

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SOURCE_DATABASE` | `DP_CONFIG` | Raw ingestion target database |
| `SYNC_TARGET_DATABASE` | `dp_config` | Production (merged) database |
| `CLIENT_NAME` | `SYSTEM` | Client identifier |
| `DBT_TARGET` | (profile) | Snowflake target (qa, prod) |
| `FULL_REFRESH` | `false` | Force re-ingestion of all sources |
| `DP_CONFIG_SYNC_BUCKET` | `data-ops-snowflake-sync-stage` | S3 bucket |
| `DP_CONFIG_SYNC_INTEGRATION` | `DATA_OPS_SNOWFLAKE_SYNC_STAGE_INTEG` | Storage integration |

---

## Common Operations

**Normal ingestion run:**
```bash
./scripts/run_dp_config.sh --target qa
```

**Full refresh (re-ingest everything):**
```bash
./scripts/run_dp_config.sh --full-refresh --target qa
```

**Schema migration (e.g., column type change in sdoh):**
```bash
# Edit sources.yml, then:
dbt compile --select backup_overrides
# Run compiled SQL in Snowflake
dbt compile --select path:analyses/schema_migration/sdoh/sdoh_tables.sql
# Run compiled SQL
dbt compile --select path:analyses/schema_migration/sdoh/sdoh_override_tables.sql
# Run compiled SQL
dbt compile --select path:analyses/schema_migration/sdoh/sdoh_streams.sql
# Run compiled SQL
dbt compile --select path:analyses/schema_migration/sdoh/sdoh_tasks.sql
# Run compiled SQL
dbt compile --select restore_and_cleanup_overrides
# Run compiled SQL
```

**Deploy all dp_config tables (initial setup or full redeploy):**
```bash
dbt compile --select deploy_dp_config_tables
# Run compiled SQL
```

**Setup override infrastructure:**
```bash
dbt compile --select setup_dp_config
# Run compiled SQL
```

**Teardown (remove overrides, keep tables):**
```bash
dbt compile --select teardown_dp_config
# Run compiled SQL (suspends tasks, drops streams, drops override tables)
```
