---
name: sqlserver-query
description: Use when you need to query SQL Server, inspect tables, check schemas, diagnose data issues, or explore databases. Triggers when the task involves running SQL against SQL Server / MSSQL, or when the user mentions "run a sql server query", "check sql server", "mssql-2-claude", or any task requiring live SQL Server data.
---

# SQL Server Query Bridge

Query SQL Server by writing SQL files that the user reviews and executes via `mssql-2-claude`. Queries are sent to a proxy server running on the host machine.

## How It Works

1. **You write SQL** to `/tmp/claude/sqlserver/{project}/<name>.sql`
2. **You tell the user** the full path to review + the exact command to run
3. **The user runs it** — you never execute queries directly
4. **You read the output** from `/tmp/claude/sqlserver/{project}/{env}/<name>-out.txt`

- `{project}` = basename of the git repo root (e.g., `hxi-infra`)
- `{env}` = the connection profile name from `-c`

SQL files go in the base project dir. Output files go in the env subfolder. The same SQL can be run against different environments — each gets its own output.

The `-c` flag is **required** — it determines both the SQL Server connection and the output subfolder.

## Connection Config

Connections and proxy settings are defined in `~/.mssql-2-claude.toml`:

```toml
[proxy]
url = "http://host.docker.internal:8080/query"

[connections.edw_qa]
server = "edw-qa.example.com"
database = "EDW"

[connections.edw_prod]
server = "edw-prod.example.com"
database = "EDW"
```

List available connections:
```
mssql-2-claude connections
```

## Writing the SQL File

- Default filename: `run.sql` (for throwaway queries)
- Use descriptive names when results should persist: `check-schema.sql`, `row-counts.sql`, etc.
- Add a comment header explaining what the query does
- Write T-SQL (SQL Server dialect)

Example:

```sql
-- check-tables.sql
-- List all user tables in the database
SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_SCHEMA, TABLE_NAME;
```

## Presenting to the User

After writing the SQL file, ALWAYS output:

1. A brief description of what the query does
2. The **full absolute path** to the SQL file (so the user can click to review)
3. The **exact command** to run (always includes `-c`)

Format:

```
I've written a query to [description].

**SQL file:** `/tmp/claude/sqlserver/{project}/<name>.sql`

Run it with:
```
mssql-2-claude <name>.sql -c <connection>
```
```

### Specifying output format

Default is TABLE. Use `-f` to change:

```
mssql-2-claude <name>.sql -c edw_qa -f JSON
mssql-2-claude <name>.sql -c edw_qa -f CSV
```

## Reading Results

After the user confirms they ran the query, read the output file:
- `run.sql` → `run-out.txt`
- `check-tables.sql` → `check-tables-out.txt`

The output file is in `/tmp/claude/sqlserver/{project}/{env}/` (the env subfolder, not the SQL file's directory).

## Rules

- **NEVER** execute `mssql-2-claude` directly via the Bash tool
- **ALWAYS** include `-c <connection>` in the command (it is required)
- **ALWAYS** print the full absolute path to the SQL file
- **ALWAYS** print the exact command for the user to run
- **ALWAYS** wait for the user to confirm execution before reading output
- Use `run.sql` for one-off throwaway queries
- Use descriptive filenames for queries whose results you'll reference later
- When writing multiple queries in sequence, use different filenames to preserve prior results
