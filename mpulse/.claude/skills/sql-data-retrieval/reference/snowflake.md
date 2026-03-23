# Snowflake Reference

Platform-specific details for Snowflake connections used by `snow-2-claude`.

## Accounts and Connections

| Connection | Env | Account | Description |
|------------|-----|---------|-------------|
| `mp_de_qa` | qa | VJB21090 | mPulse DE QA |
| `mp_de_stage` | stage | MEB84506 | mPulse DE Staging |
| `mp_de_prod` | prod | YZB01027 | mPulse DE Production |
| `data_ops_dev` | data_ops_dev | NMB10465 | Data Ops Dev |
| `data_ops_prod` | data_ops_prod | EGC79305 | Data Ops Production |
| `dpi_ml_prod` | dpi_ml_prod | tob70205 | ML Production |
| `edw-develop` | edw_develop | oab27176 | EDW Development |

Terraform connections (`*_tf` suffix) use JWT auth with the `terraform` service account and are not available through snow-2-claude.

## Authentication

Connections are configured in `~/.snowflake/connections.toml` (Snowflake CLI config). Authentication is browser-based (external browser auth for interactive use).

To test a connection:
```
snow connection test -c <connection>
```

If a query times out, the auth token may have expired. Re-authenticate with the test command above.

## Snow CLI Usage

`snow-2-claude` wraps the Snowflake CLI (`snow sql`). It always runs with `--format JSON` internally and converts to dual output (JSON + markdown table).

Key flags:
- `-c <connection>` — required, determines account and env subfolder
- `-t <seconds>` — query timeout (default: 120s)
- `--dry-run` — print the command without executing

Subcommands:
- `snow-2-claude connections` — not supported (connections are in `~/.snowflake/connections.toml`)
- `snow-2-claude clean [-c connection]` — remove output files

## SQL Dialect Tips

Snowflake SQL:
- Identifiers are case-insensitive unless double-quoted
- Use `SHOW GRANTS TO ROLE <role>` to inspect permissions
- Use `INFORMATION_SCHEMA` or `SHOW` commands for metadata
- `FLATTEN()` for semi-structured data (VARIANT, ARRAY, OBJECT)
- `TRY_CAST()` for safe type conversion
- `QUALIFY` clause for window function filtering (Snowflake-specific)
- String functions: `IFF()`, `NULLIF()`, `COALESCE()`, `NVL()`
- Date functions: `DATEADD()`, `DATEDIFF()`, `DATE_TRUNC()`

## Output Directory

```
/tmp/claude/sql/{project}/
  <name>.sql                  # SQL files (base dir)
  qa/<name>-out.json          # Output per env
  qa/<name>-out.txt
  prod/<name>-out.json
  prod/<name>-out.txt
```
