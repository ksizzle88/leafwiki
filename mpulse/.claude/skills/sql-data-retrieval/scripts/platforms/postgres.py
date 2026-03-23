"""PostgreSQL query execution via psycopg2."""

from __future__ import annotations

import json
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib  # type: ignore

CONFIG_PATH = Path.home() / ".pg-2-claude.toml"


def _load_pg_config(connection: str) -> dict:
    """Load connection params from ~/.pg-2-claude.toml."""
    if not CONFIG_PATH.is_file():
        raise RuntimeError(f"Config not found: {CONFIG_PATH}\nRun 'sql-2-claude connections' for setup.")

    with open(CONFIG_PATH, "rb") as f:
        cfg = tomllib.load(f)

    conns = cfg.get("connections", {})
    if connection not in conns:
        raise RuntimeError(f"Connection '{connection}' not in {CONFIG_PATH}. Available: {', '.join(conns)}")

    return conns[connection]


def execute(sql_path: Path, connection: str, timeout: int, extra_args: list[str] | None = None) -> list[dict]:
    """Run SQL via psycopg2, return list of dicts."""
    import psycopg2

    pg_cfg = _load_pg_config(connection)

    kwargs = {
        "host": pg_cfg.get("host", "localhost"),
        "port": pg_cfg.get("port", 5432),
        "dbname": pg_cfg.get("dbname", pg_cfg.get("database", "")),
        "user": pg_cfg.get("user", ""),
        "options": f"-c statement_timeout={timeout * 1000}",
    }
    if "password" in pg_cfg:
        kwargs["password"] = pg_cfg["password"]
    if "sslmode" in pg_cfg:
        kwargs["sslmode"] = pg_cfg["sslmode"]

    sql = sql_path.read_text().strip()
    if not sql:
        raise RuntimeError("SQL file is empty")

    conn = psycopg2.connect(**kwargs)
    try:
        conn.autocommit = True
        cur = conn.cursor()
        cur.execute(sql)

        if cur.description is None:
            return [{"status": "OK", "rowcount": cur.rowcount}]

        columns = [desc[0] for desc in cur.description]
        rows = cur.fetchall()
        return [dict(zip(columns, row)) for row in rows]
    finally:
        conn.close()
