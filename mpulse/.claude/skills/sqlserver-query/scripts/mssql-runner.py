#!/usr/bin/env python3
"""Execute SQL against SQL Server via a host-side proxy, format output for Claude."""

import argparse
import csv
import io
import json
import sys
import tomllib
import urllib.request
import urllib.error


def load_config(config_path: str, conn_name: str) -> tuple[str, dict]:
    """Load proxy URL and named connection profile from TOML config.

    Returns (proxy_url, connection_params).
    """
    with open(config_path, "rb") as f:
        cfg = tomllib.load(f)

    proxy = cfg.get("proxy", {})
    proxy_url = proxy.get("url")
    if not proxy_url:
        print("Error: [proxy] url not configured in config file", file=sys.stderr)
        sys.exit(1)

    conns = cfg.get("connections", {})
    if conn_name not in conns:
        available = ", ".join(conns.keys()) if conns else "(none)"
        print(f"Error: connection '{conn_name}' not found. Available: {available}", file=sys.stderr)
        sys.exit(1)

    return proxy_url, conns[conn_name]


def send_query(proxy_url: str, conn_params: dict, sql: str, timeout: int, fmt: str) -> dict:
    """Send SQL to the proxy server and return the response.

    Expected request format (customize when proxy is built):
        POST proxy_url
        Content-Type: application/json
        {
            "connection": { ...conn_params... },
            "sql": "SELECT ...",
            "timeout": 120,
            "format": "TABLE"
        }

    Expected response format:
        {
            "columns": ["col1", "col2", ...],
            "rows": [["val1", "val2"], ...],
            "status": "OK",
            "error": null
        }

    TODO: Update request/response format once proxy server is built.
    """
    payload = {
        "connection": conn_params,
        "sql": sql,
        "timeout": timeout,
        "format": fmt,
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        proxy_url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=timeout + 10) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print(f"Error: proxy returned HTTP {e.code}", file=sys.stderr)
        print(body, file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"Error: cannot reach proxy at {proxy_url}: {e.reason}", file=sys.stderr)
        print("  Is the proxy server running on the host?", file=sys.stderr)
        sys.exit(1)


def format_table(columns: list[str], rows: list[list]) -> str:
    """Format results as an aligned text table."""
    if not columns:
        return "(no columns)"
    if not rows:
        return " | ".join(columns) + "\n(0 rows)"

    str_rows = [[str(v) if v is not None else "NULL" for v in row] for row in rows]
    widths = [max(len(col), max((len(r[i]) for r in str_rows), default=0)) for i, col in enumerate(columns)]

    header = " | ".join(col.ljust(w) for col, w in zip(columns, widths))
    separator = "-+-".join("-" * w for w in widths)

    lines = [header, separator]
    for row in str_rows:
        lines.append(" | ".join(val.ljust(w) for val, w in zip(row, widths)))
    lines.append(f"({len(rows)} row{'s' if len(rows) != 1 else ''})")

    return "\n".join(lines)


def format_csv_output(columns: list[str], rows: list[list]) -> str:
    """Format results as CSV."""
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(columns)
    for row in rows:
        writer.writerow(["NULL" if v is None else v for v in row])
    return buf.getvalue()


def format_json_output(columns: list[str], rows: list[list]) -> str:
    """Format results as JSON array of objects."""
    result = [dict(zip(columns, row)) for row in rows]
    return json.dumps(result, indent=2, default=str)


def main():
    parser = argparse.ArgumentParser(description="Execute SQL against SQL Server via proxy")
    parser.add_argument("--config", required=True, help="Path to TOML config file")
    parser.add_argument("--connection", required=True, help="Connection profile name")
    parser.add_argument("--format", choices=["TABLE", "JSON", "CSV"], default="TABLE")
    parser.add_argument("--timeout", type=int, default=120, help="Query timeout in seconds")
    parser.add_argument("--sql-file", required=True, help="Path to SQL file")
    args = parser.parse_args()

    proxy_url, conn_params = load_config(args.config, args.connection)

    with open(args.sql_file) as f:
        sql = f.read().strip()

    if not sql:
        print("Error: SQL file is empty", file=sys.stderr)
        sys.exit(1)

    result = send_query(proxy_url, conn_params, sql, args.timeout, args.format)

    # Handle error from proxy
    if result.get("error"):
        print(f"SQL Server Error: {result['error']}", file=sys.stderr)
        sys.exit(1)

    columns = result.get("columns", [])
    rows = result.get("rows", [])

    # If proxy already returned formatted output, print it directly
    if "output" in result:
        print(result["output"])
        return

    # Otherwise format locally
    if not columns:
        print(result.get("status", "OK"))
        return

    if args.format == "TABLE":
        print(format_table(columns, rows))
    elif args.format == "CSV":
        print(format_csv_output(columns, rows))
    elif args.format == "JSON":
        print(format_json_output(columns, rows))


if __name__ == "__main__":
    main()
