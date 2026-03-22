#!/usr/bin/env python3
"""Execute SQL against PostgreSQL and format output for Claude to read."""

import argparse
import csv
import io
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


def format_table(columns: list[str], rows: list[tuple]) -> str:
    """Format results as an aligned text table."""
    if not columns:
        return "(no columns)"
    if not rows:
        return " | ".join(columns) + "\n(0 rows)"

    # Calculate column widths
    str_rows = [[str(v) if v is not None else "NULL" for v in row] for row in rows]
    widths = [max(len(col), max((len(r[i]) for r in str_rows), default=0)) for i, col in enumerate(columns)]

    # Header
    header = " | ".join(col.ljust(w) for col, w in zip(columns, widths))
    separator = "-+-".join("-" * w for w in widths)

    # Rows
    lines = [header, separator]
    for row in str_rows:
        lines.append(" | ".join(val.ljust(w) for val, w in zip(row, widths)))
    lines.append(f"({len(rows)} row{'s' if len(rows) != 1 else ''})")

    return "\n".join(lines)


def format_csv_output(columns: list[str], rows: list[tuple]) -> str:
    """Format results as CSV."""
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(columns)
    for row in rows:
        writer.writerow(["NULL" if v is None else v for v in row])
    return buf.getvalue()


def format_json_output(columns: list[str], rows: list[tuple]) -> str:
    """Format results as JSON array of objects."""
    result = []
    for row in rows:
        result.append(dict(zip(columns, [v if v is not None else None for v in row])))
    return json.dumps(result, indent=2, default=str)


def run_query(conn_params: dict, sql: str, timeout: int, fmt: str) -> None:
    """Connect, execute SQL, and print formatted results."""
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
        # psycopg2 executes the full string; we fetch from the last statement that returns rows
        cur.execute(sql)

        if cur.description:
            columns = [desc[0] for desc in cur.description]
            rows = cur.fetchall()

            if fmt == "TABLE":
                print(format_table(columns, rows))
            elif fmt == "CSV":
                print(format_csv_output(columns, rows))
            elif fmt == "JSON":
                print(format_json_output(columns, rows))
        else:
            status = cur.statusmessage or "OK"
            print(status)

        cur.close()
    finally:
        conn.close()


def main():
    parser = argparse.ArgumentParser(description="Execute SQL against PostgreSQL")
    parser.add_argument("--config", required=True, help="Path to TOML config file")
    parser.add_argument("--connection", required=True, help="Connection profile name")
    parser.add_argument("--format", choices=["TABLE", "JSON", "CSV"], default="TABLE")
    parser.add_argument("--timeout", type=int, default=120, help="Query timeout in seconds")
    parser.add_argument("--sql-file", required=True, help="Path to SQL file")
    args = parser.parse_args()

    conn_params = load_connection(args.config, args.connection)

    with open(args.sql_file) as f:
        sql = f.read().strip()

    if not sql:
        print("Error: SQL file is empty", file=sys.stderr)
        sys.exit(1)

    run_query(conn_params, sql, args.timeout, args.format)


if __name__ == "__main__":
    main()
