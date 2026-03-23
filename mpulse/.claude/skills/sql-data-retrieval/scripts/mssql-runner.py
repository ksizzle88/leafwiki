#!/usr/bin/env python3
"""Execute SQL against SQL Server via a host-side proxy, output JSON for Claude."""

import argparse
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


def send_query(proxy_url: str, conn_params: dict, sql: str, timeout: int) -> dict:
    """Send SQL to the proxy server and return the response.

    Expected request format:
        POST proxy_url
        Content-Type: application/json
        {
            "connection": { ...conn_params... },
            "sql": "SELECT ...",
            "timeout": 120,
            "format": "JSON"
        }

    Expected response format:
        {
            "columns": ["col1", "col2", ...],
            "rows": [["val1", "val2"], ...],
            "status": "OK",
            "error": null
        }
    """
    payload = {
        "connection": conn_params,
        "sql": sql,
        "timeout": timeout,
        "format": "JSON",
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


def main():
    parser = argparse.ArgumentParser(description="Execute SQL against SQL Server via proxy (JSON output)")
    parser.add_argument("--config", required=True, help="Path to TOML config file")
    parser.add_argument("--connection", required=True, help="Connection profile name")
    parser.add_argument("--timeout", type=int, default=120, help="Query timeout in seconds")
    parser.add_argument("--sql-file", required=True, help="Path to SQL file")
    args = parser.parse_args()

    proxy_url, conn_params = load_config(args.config, args.connection)

    with open(args.sql_file) as f:
        sql = f.read().strip()

    if not sql:
        print("Error: SQL file is empty", file=sys.stderr)
        sys.exit(1)

    result = send_query(proxy_url, conn_params, sql, args.timeout)

    # Handle error from proxy
    if result.get("error"):
        print(f"SQL Server Error: {result['error']}", file=sys.stderr)
        sys.exit(1)

    columns = result.get("columns", [])
    rows = result.get("rows", [])

    if not columns:
        print(json.dumps({"status": result.get("status", "OK")}))
        return

    # Always output JSON array of objects
    output = [dict(zip(columns, row)) for row in rows]
    print(json.dumps(output, indent=2, default=str))


if __name__ == "__main__":
    main()
