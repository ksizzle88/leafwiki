"""SQLite query execution — direct, no user-exec bridge needed."""

from __future__ import annotations

import json
import os
import sqlite3
from pathlib import Path


def execute(sql_path: Path, connection: str, timeout: int, extra_args: list[str] | None = None, db_path: str = "") -> list[dict]:
    """Run SQL against a SQLite database, return list of dicts."""
    if not db_path:
        raise RuntimeError(f"No db path configured for connection '{connection}'. Set 'path' in connections.yaml.")

    # Resolve env vars in path
    db_path = os.path.expandvars(db_path)

    if not Path(db_path).is_file():
        raise RuntimeError(f"SQLite database not found: {db_path}")

    sql = sql_path.read_text().strip()
    if not sql:
        raise RuntimeError("SQL file is empty")

    conn = sqlite3.connect(db_path, timeout=timeout)
    conn.row_factory = sqlite3.Row
    try:
        cur = conn.execute(sql)
        if cur.description is None:
            return [{"status": "OK", "rowcount": cur.rowcount}]
        return [dict(row) for row in cur.fetchall()]
    finally:
        conn.close()
