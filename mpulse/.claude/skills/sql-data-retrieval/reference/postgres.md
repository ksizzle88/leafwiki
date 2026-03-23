# PostgreSQL Reference

Platform-specific details for PostgreSQL connections used by `pg-2-claude`.

## Connections

| Connection | Env | Description |
|------------|-----|-------------|
| `edw_postgres` | edw_postgres | EDW PostgreSQL |

Additional connections can be added to `~/.pg-2-claude.toml`.

## Authentication

Connections are defined in `~/.pg-2-claude.toml`:

```toml
[connections.edw_postgres]
host = "db-host.example.com"
port = 5432
dbname = "edw"
user = "myuser"
password = "mypass"    # optional -- can use PGPASSWORD env var instead
sslmode = "require"    # optional
```

Each connection profile maps to a set of psycopg2 connection parameters. All keys under `[connections.<name>]` are passed directly to `psycopg2.connect()`.

To list available connections:
```
pg-2-claude connections
```

## Script Usage

`pg-2-claude` uses a Python runner (`pg-runner.py`) with psycopg2 to execute queries.

Key flags:
- `-c <connection>` -- required, determines connection profile and env subfolder
- `-f <format>` -- output format: TABLE (default), JSON, CSV
- `-t <seconds>` -- query timeout (default: 120s)
- `--dry-run` -- print the command without executing

Subcommands:
- `pg-2-claude connections` -- list available connection profiles
- `pg-2-claude clean [-c connection]` -- remove output files

## SQL Dialect Tips

PostgreSQL SQL:
- Identifiers are case-sensitive when double-quoted, folded to lowercase otherwise
- Use `information_schema.tables` / `information_schema.columns` for metadata
- `\d` commands are psql-specific and not available through pg-2-claude
- `ILIKE` for case-insensitive pattern matching
- `::type` for casting (e.g., `'2024-01-01'::date`)
- `LATERAL JOIN` for correlated subqueries in FROM
- `WITH RECURSIVE` for hierarchical queries
- `DISTINCT ON (col)` for first-row-per-group (PostgreSQL-specific)
- Array operations: `ANY()`, `ALL()`, `array_agg()`
- JSON operations: `->`, `->>`, `jsonb_each()`, `jsonb_array_elements()`

## Output Directory

```
/tmp/claude/sql/{project}/
  <name>.sql                          # SQL files (base dir)
  edw_postgres/<name>-out.json        # Output per env
  edw_postgres/<name>-out.txt
```
