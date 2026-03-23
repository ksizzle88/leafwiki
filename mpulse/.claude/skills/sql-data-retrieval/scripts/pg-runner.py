#!/usr/bin/env python3
"""Execute SQL against PostgreSQL and output JSON for Claude to read."""

import argparse
import json
import sys
import tomllib

import psycopg2
import psycopg2.extras


def load_connection(config_path: str, conn_name: str) -> dict:
    """Load a named connection profile from the TOML config."""
    with open(config_path, "rb") as f:
        cfg = tomllib.load(f)

    conns = cfg.get("connections", {})
    if conn_name not in conns:
        available = ", ".join(conns.keys()) if conns else "(none)"
        print(f"Error: connection '{conn_name}' not found. Available: {available}", file=sys.stderr)
        sys.exit(1)

    return conns[conn_name]


def run_query(conn_params: dict, sql: str, timeout: int) -> None:
    """Connect, execute SQL, and print JSON results."""
    # Build connection kwargs
    kwargs = {
        "host": conn_params.get("host", "localhost"),
        "port": conn_params.get("port", 5432),
        "dbname": conn_params.get("dbname"),
        "user": conn_params.get("user"),
        "connect_timeout": 10,
        "options": f"-c statement_timeout={timeout * 1000}",
    }

    # Password: config value or PGPASSWORD env var
    if "password" in conn_params:
        kwargs["password"] = conn_params["password"]

    # Optional sslmode
    if "sslmode" in conn_params:
        kwargs["sslmode"] = conn_params["sslmode"]

    conn = psycopg2.connect(**kwargs)
    conn.autocommit = True

    try:
        cur = conn.cursor()

        # Handle multi-statement SQL: execute all, display last result set
        cur.execute(sql)

        if cur.description:
            columns = [desc[0] for desc in cur.description]
            rows = cur.fetchall()
            result = [dict(zip(columns, [v if v is not None else None for v in row])) for row in rows]
            print(json.dumps(result, indent=2, default=str))
        else:
            status = cur.statusmessage or "OK"
            print(json.dumps({"status": status}))

        cur.close()
    finally:
        conn.close()


def main():
    parser = argparse.ArgumentParser(description="Execute SQL against PostgreSQL (JSON output)")
    parser.add_argument("--config", required=True, help="Path to TOML config file")
    parser.add_argument("--connection", required=True, help="Connection profile name")
    parser.add_argument("--timeout", type=int, default=120, help="Query timeout in seconds")
    parser.add_argument("--sql-file", required=True, help="Path to SQL file")
    args = parser.parse_args()

    conn_params = load_connection(args.config, args.connection)

    with open(args.sql_file) as f:
        sql = f.read().strip()

    if not sql:
        print("Error: SQL file is empty", file=sys.stderr)
        sys.exit(1)

    run_query(conn_params, sql, args.timeout)


if __name__ == "__main__":
    main()
