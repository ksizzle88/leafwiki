---
name: sql-data-retrieval
description: Use when you need to query any database — Snowflake, PostgreSQL, or SQL Server. Triggers when the task involves running SQL, inspecting schemas, checking data, or when the user mentions "run a query", "check the database", "snow-2-claude", "pg-2-claude", "mssql-2-claude", "sql-2-claude", or any task requiring live database data.
---

# SQL Data Retrieval

Query Snowflake, PostgreSQL, or SQL Server by writing SQL files that the user reviews and executes via `sql-2-claude`.

## Workflow

1. **Write SQL** to `/tmp/claude/sql/{project}/{env}/{query-name}/query.sql`
2. **Present to the user** — description, full file path, exact command
3. **User runs it** — you never execute queries directly
4. **Read the output** — `out.json` in the same query folder

## Per-Query Folder Structure

Each query gets its own folder:

```
/tmp/claude/sql/{project}/{env}/{query-name}/
├── query.sql    ← you write this (Claude)
├── out.json     ← raw JSON (read this for data analysis)
└── out.md       ← markdown table (human-readable, for user)
```

- `{project}` = basename of the git repo root (e.g., `DPI_Analytics_DBT`)
- `{env}` = derived from the connection name (e.g., `mp_de_qa` → `qa`)
- `{query-name}` = descriptive name (REQUIRED — no default)

## SQL File Header (REQUIRED)

**ALWAYS** include `-- connection: <name>` as the first line of every SQL file:

```sql
-- connection: mp_de_qa
-- Check SDOH HCC types in QA environment

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'sdoh_hcc_types';
```

The script checks this header against the `-c` flag and warns if they don't match. This prevents accidentally running a QA query against prod.

## Router: sql-2-claude

`sql-2-claude` routes to the correct platform script based on the connection name.

```
sql-2-claude {query-name} -c <connection>
```

The `-c` flag is **required**. It determines the platform, connection, and output subfolder. See `connections.toml` in this skill directory for the full connection list, or run:

```
sql-2-claude connections
```

You can also call platform scripts directly:
- `snow-2-claude {query-name} -c <connection>` — Snowflake
- `pg-2-claude {query-name} -c <connection>` — PostgreSQL
- `mssql-2-claude {query-name} -c <connection>` — SQL Server

## Raw Mode

For arbitrary commands without a SQL file:

```
sql-2-claude raw -c mp_de_qa -- snow sql -q "SHOW DATABASES"
```

Output is captured to a `raw-{timestamp}/` folder in the env directory.

## Presenting to the User

After writing the SQL file, ALWAYS output:

```
I've written a query to [description].

**SQL file:** `/tmp/claude/sql/{project}/{env}/{query-name}/query.sql`

Run it with:
sql-2-claude {query-name} -c <connection>
```

## Reading Results

After the user confirms execution, read the JSON output:

```
/tmp/claude/sql/{project}/{env}/{query-name}/out.json
```

If the query failed, errors are also captured in `out.json` and `out.md` — read `out.json` to see the error details.

## Rules

- **NEVER** execute `sql-2-claude`, `snow-2-claude`, `pg-2-claude`, `mssql-2-claude`, `snow sql`, or `psql` directly via the Bash tool
- **ALWAYS** include `-- connection: <name>` as the first line of query.sql
- **ALWAYS** include `-c <connection>` in the run command
- **ALWAYS** print the full absolute path to the SQL file
- **ALWAYS** print the exact command for the user to run
- **ALWAYS** wait for the user to confirm execution before reading output
- **ALWAYS** read `out.json` (not `out.md`) for programmatic data analysis
- **ALWAYS** use a descriptive query name — no defaults
- Match the SQL dialect to the platform — see [reference/snowflake.md](reference/snowflake.md), [reference/postgres.md](reference/postgres.md), [reference/mssql.md](reference/mssql.md)
