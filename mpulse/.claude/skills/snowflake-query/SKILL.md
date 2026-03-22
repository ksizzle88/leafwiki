---
name: snowflake-query
description: Use when you need to query Snowflake, inspect database objects, check grants/roles, diagnose data issues, or explore schemas. Triggers when the task involves running SQL against Snowflake, investigating Snowflake data, or when the user mentions "run a query", "check snowflake", "snow-2-claude", or any task requiring live Snowflake data.
---

# Snowflake Query Bridge

Query Snowflake by writing SQL files that the user reviews and executes via `snow-2-claude`.

## How It Works

1. **You write SQL** to `.claude/snowflake/<name>.sql` (relative to the project root)
2. **You tell the user** the full path to review + the exact command to run
3. **The user runs it** — you never execute queries directly
4. **You read the output** from `.claude/snowflake/<name>-out.txt`

## Directory Resolution

The `snow-2-claude` script traverses upward from the current directory to find the nearest `.claude/` folder (like git finds `.git/`), then uses `.claude/snowflake/` inside it. Falls back to `~/.claude/snowflake/`.

When writing SQL files, use the `.claude/snowflake/` path relative to the project root you're working in.

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
3. The **exact command** to run

Format:

```
I've written a query to [description].

**SQL file:** `/full/path/to/.claude/snowflake/<name>.sql`

Run it with:
```
snow-2-claude <name>.sql
```
```

### Specifying a connection

If the task requires a specific Snowflake account, include the `-c` flag:

```
snow-2-claude <name>.sql -c data_ops_prod
```

Available connections (from ~/.snowflake/connections.toml):
- `data_ops_dev` — Data Ops Dev/QA (NMB10465)
- `data_ops_prod` — Data Ops Prod (EGC79305)
- `dpi_ml_prod` — ML Prod (tob70205)
- `mp_de_qa` — mPulse DE QA (vjb21090)
- `mp_de_stage` — mPulse DE Stage (MEB84506)
- `mp_de_prod` — mPulse DE Prod (yzb01027)
- `edw-develop` — EDW Dev (oab27176)

### Specifying output format

Default is TABLE. Use `-f` to change:

```
snow-2-claude <name>.sql -f JSON
snow-2-claude <name>.sql -f CSV
```

## Reading Results

After the user confirms they ran the query, read the output file:
- `run.sql` → `run-out.txt`
- `check-grants.sql` → `check-grants-out.txt`

The output file is in the same `.claude/snowflake/` directory as the SQL file.

## Rules

- **NEVER** execute `snow-2-claude` or `snow sql` directly via the Bash tool
- **ALWAYS** print the full absolute path to the SQL file
- **ALWAYS** print the exact command for the user to run
- **ALWAYS** wait for the user to confirm execution before reading output
- Use `run.sql` for one-off throwaway queries
- Use descriptive filenames for queries whose results you'll reference later
- When writing multiple queries in sequence, use different filenames to preserve prior results
