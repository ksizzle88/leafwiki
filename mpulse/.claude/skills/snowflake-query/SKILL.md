---
name: snowflake-query
description: Use when you need to query Snowflake, inspect database objects, check grants/roles, diagnose data issues, or explore schemas. Triggers when the task involves running SQL against Snowflake, investigating Snowflake data, or when the user mentions "run a query", "check snowflake", "snow-2-claude", or any task requiring live Snowflake data.
---

# Snowflake Query Bridge

Query Snowflake by writing SQL files that the user reviews and executes via `snow-2-claude`.

## How It Works

1. **You write SQL** to `/tmp/claude/snowflake/{project}/<name>.sql`
2. **You tell the user** the full path to review + the exact command to run
3. **The user runs it** — you never execute queries directly
4. **You read the output** — two files are produced:
   - `/tmp/claude/snowflake/{project}/{env}/<name>-out.json` — raw JSON (read this for data analysis)
   - `/tmp/claude/snowflake/{project}/{env}/<name>-out.txt` — markdown table (human-readable)

- `{project}` = basename of the git repo root (e.g., `hxi-infra`, `DPI_Analytics_DBT`)
- `{env}` = derived from the `-c` connection name (e.g., `mp_de_qa` → `qa`)

SQL files go in the base project dir. Output files go in the env subfolder. The same SQL can be run against different environments — each gets its own output.

The `-c` flag is **required** — it determines both the Snowflake connection and the output subfolder.

## Connection → Environment Mapping

| Connection | Env subfolder | Account |
|------------|---------------|---------|
| `mp_de_qa` | `qa/` | VJB21090 |
| `mp_de_stage` | `stage/` | MEB84506 |
| `mp_de_prod` | `prod/` | YZB01027 |
| `data_ops_dev` | `data_ops_dev/` | NMB10465 |
| `data_ops_prod` | `data_ops_prod/` | EGC79305 |
| `dpi_ml_prod` | `dpi_ml_prod/` | tob70205 |
| `edw-develop` | `edw_develop/` | oab27176 |

## Writing the SQL File

- Default filename: `run.sql` (for throwaway queries)
- Use descriptive names when results should persist: `check-grants.sql`, `table-schema.sql`, etc.
- Add a comment header explaining what the query does
- Write clean, readable SQL

Example:

```sql
-- check-grants.sql
-- Verify role grants for DATA_DEVELOPER role
SHOW GRANTS TO ROLE DATA_DEVELOPER__ALL;
```

## Presenting to the User

After writing the SQL file, ALWAYS output:

1. A brief description of what the query does
2. The **full absolute path** to the SQL file (so the user can click to review)
3. The **exact command** to run (always includes `-c`)

Format:

```
I've written a query to [description].

**SQL file:** `/tmp/claude/snowflake/{project}/<name>.sql`

Run it with:
```
snow-2-claude <name>.sql -c <connection>
```
```

Output is always dual format — the user sees a markdown table preview in the console, and both JSON and table files are saved.

## Reading Results

After the user confirms they ran the query, read the **JSON output** for data analysis:
- `run.sql` → read `run-out.json`
- `check-grants.sql` → read `check-grants-out.json`

The **table output** (`-out.txt`) is for the user's quick reference — you don't need to read it.

Output files are in `/tmp/claude/snowflake/{project}/{env}/` (the env subfolder, not the SQL file's directory).

## Rules

- **NEVER** execute `snow-2-claude` or `snow sql` directly via the Bash tool
- **ALWAYS** include `-c <connection>` in the command (it is required)
- **ALWAYS** print the full absolute path to the SQL file
- **ALWAYS** print the exact command for the user to run
- **ALWAYS** wait for the user to confirm execution before reading output
- **ALWAYS** read the `.json` file (not `.txt`) for programmatic data analysis
- Use `run.sql` for one-off throwaway queries
- Use descriptive filenames for queries whose results you'll reference later
- When writing multiple queries in sequence, use different filenames to preserve prior results
