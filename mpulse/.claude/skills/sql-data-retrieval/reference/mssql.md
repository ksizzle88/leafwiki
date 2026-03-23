# SQL Server Reference

Platform-specific details for SQL Server connections used by `mssql-2-claude`.

## Connections

| Connection | Env | Description |
|------------|-----|-------------|
| `edw_mssql` | edw_mssql | EDW SQL Server |

Additional connections can be added to `~/.mssql-2-claude.toml`.

## Architecture: HTTP Proxy

`mssql-2-claude` does not connect to SQL Server directly. It sends queries to an HTTP proxy running on the host machine. This is necessary because SQL Server uses Windows Authentication (NTLM/Kerberos) which is not available inside the Linux container.

The proxy runs on the Windows host and handles authentication transparently.

## Authentication

Connections and proxy settings are defined in `~/.mssql-2-claude.toml`:

```toml
[proxy]
url = "http://host.docker.internal:8080/query"

[connections.edw_mssql]
server = "edw-server.example.com"
database = "EDW"
# additional fields are passed to the proxy as connection params
```

The `[proxy]` section defines the proxy URL. `host.docker.internal` resolves to the Docker host from inside the container.

To list available connections:
```
mssql-2-claude connections
```

## Script Usage

`mssql-2-claude` uses a Python runner (`mssql-runner.py`) that sends SQL to the proxy via HTTP POST.

Key flags:
- `-c <connection>` -- required, determines connection profile and env subfolder
- `-f <format>` -- output format: TABLE (default), JSON, CSV
- `-t <seconds>` -- query timeout (default: 120s)
- `--dry-run` -- print the command without executing

Subcommands:
- `mssql-2-claude connections` -- list available connection profiles
- `mssql-2-claude clean [-c connection]` -- remove output files

## SQL Dialect Tips

T-SQL (SQL Server dialect):
- Use `TOP N` instead of `LIMIT N` (e.g., `SELECT TOP 10 * FROM ...`)
- `INFORMATION_SCHEMA.TABLES` for metadata (same as PostgreSQL)
- Square brackets `[column]` for identifier quoting (or double quotes)
- `GETDATE()` for current timestamp, `CAST(x AS DATE)` for date conversion
- `STRING_AGG()` for string aggregation (SQL Server 2017+)
- `TRY_CAST()` / `TRY_CONVERT()` for safe type conversion
- `CROSS APPLY` / `OUTER APPLY` instead of `LATERAL JOIN`
- `IIF(condition, true_val, false_val)` for inline conditionals
- `OFFSET ... FETCH NEXT ... ROWS ONLY` for pagination (SQL Server 2012+)
- No `BOOLEAN` type -- use `BIT` (0/1)
- Temp tables: `#local_temp`, `##global_temp`

## Output Directory

```
/tmp/claude/sql/{project}/
  <name>.sql                        # SQL files (base dir)
  edw_mssql/<name>-out.json         # Output per env
  edw_mssql/<name>-out.txt
```
