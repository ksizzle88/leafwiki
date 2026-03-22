---
name: postgres-query
description: Use when you need to query PostgreSQL, inspect tables, check schemas, diagnose data issues, or explore databases. Triggers when the task involves running SQL against PostgreSQL, investigating Postgres data, or when the user mentions "run a postgres query", "check postgres", "pg-2-claude", or any task requiring live PostgreSQL data.
---

# PostgreSQL Query Bridge

Query PostgreSQL by writing SQL files that the user reviews and executes via `pg-2-claude`.

## How It Works

1. **You write SQL** to `/tmp/claude/postgres/{project}/<name>.sql`
2. **You tell the user** the full path to review + the exact command to run
3. **The user runs it** — you never execute queries directly
4. **You read the output** from `/tmp/claude/postgres/{project}/{env}/<name>-out.txt`

- `{project}` = basename of the git repo root (e.g., `hxi-infra`)
- `{env}` = the connection profile name from `-c`

SQL files go in the base project dir. Output files go in the env subfolder. The same SQL can be run against different environments — each gets its own output.

The `-c` flag is **required** — it determines both the PostgreSQL connection and the output subfolder.

## Connection Config

Connections are defined in `~/.pg-2-claude.toml`:

```toml
[connections.my_db_qa]
host = "qa-db.example.com"
port = 5432
dbname = "mydb"
user = "myuser"
password = "mypass"    # optional — can use PGPASSWORD env var instead
sslmode = "require"    # optional

[connections.my_db_prod]
host = "prod-db.example.com"
port = 5432
dbname = "mydb"
user = "myuser"
password = "mypass"
```

List available connections:
```
pg-2-claude connections
```

## Writing the SQL File

- Default filename: `run.sql` (for throwaway queries)
- Use descriptive names when results should persist: `check-schema.sql`, `row-counts.sql`, etc.
- Add a comment header explaining what the query does
- Write clean, readable SQL

Example:

```sql
-- check-schema.sql
-- List all tables in the public schema
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
```

## Presenting to the User

After writing the SQL file, ALWAYS output:

1. A brief description of what the query does
2. The **full absolute path** to the SQL file (so the user can click to review)
3. The **exact command** to run (always includes `-c`)

Format:

```
I've written a query to [description].

**SQL file:** `/tmp/claude/postgres/{project}/<name>.sql`

Run it with:
```
pg-2-claude <name>.sql -c <connection>
```
```

### Specifying output format

Default is TABLE. Use `-f` to change:

```
pg-2-claude <name>.sql -c my_db_qa -f JSON
pg-2-claude <name>.sql -c my_db_qa -f CSV
```

## Reading Results

After the user confirms they ran the query, read the output file:
- `run.sql` → `run-out.txt`
- `check-schema.sql` → `check-schema-out.txt`

The output file is in `/tmp/claude/postgres/{project}/{env}/` (the env subfolder, not the SQL file's directory).

## Rules

- **NEVER** execute `pg-2-claude` or `psql` directly via the Bash tool
- **ALWAYS** include `-c <connection>` in the command (it is required)
- **ALWAYS** print the full absolute path to the SQL file
- **ALWAYS** print the exact command for the user to run
- **ALWAYS** wait for the user to confirm execution before reading output
- Use `run.sql` for one-off throwaway queries
- Use descriptive filenames for queries whose results you'll reference later
- When writing multiple queries in sequence, use different filenames to preserve prior results
