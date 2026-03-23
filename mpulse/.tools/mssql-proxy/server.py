"""
MSSQL Proxy — FastAPI server for SQL Server queries via Windows auth.
Runs on the Windows host (needs Trusted_Connection).
Containers hit this via host.docker.internal:9999.

Usage:
    pip install fastapi uvicorn pyodbc
    python server.py
    # or: uvicorn server:app --host 0.0.0.0 --port 9999

Config: connections.yaml in the same directory.
"""

from __future__ import annotations

import threading
import yaml
from contextlib import contextmanager
from pathlib import Path
from typing import Any

import pyodbc
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

# --- Config ---
CONFIG_PATH = Path(__file__).parent / "connections.yaml"


def load_config() -> dict[str, Any]:
    if CONFIG_PATH.exists():
        with open(CONFIG_PATH) as f:
            return yaml.safe_load(f) or {}
    return {}


config = load_config()
CONNECTIONS: dict[str, dict] = config.get("connections", {})
DEFAULT_PORT = config.get("server", {}).get("port", 9999)
DEFAULT_POOL_SIZE = config.get("server", {}).get("pool_size", 5)


# --- Connection Pool ---
class ConnectionPool:
    def __init__(self, conn_str: str, pool_size: int = DEFAULT_POOL_SIZE):
        self.conn_str = conn_str
        self.pool: list[pyodbc.Connection] = []
        self.lock = threading.Lock()
        self.pool_size = pool_size

    def _create(self) -> pyodbc.Connection:
        return pyodbc.connect(self.conn_str, autocommit=True)

    @contextmanager
    def get(self):
        conn = None
        with self.lock:
            if self.pool:
                conn = self.pool.pop()
        if conn is None:
            conn = self._create()
        try:
            yield conn
            with self.lock:
                if len(self.pool) < self.pool_size:
                    self.pool.append(conn)
                else:
                    conn.close()
        except Exception:
            try:
                conn.close()
            except Exception:
                pass
            raise


def build_conn_str(cfg: dict) -> str:
    driver = cfg.get("driver", "ODBC Driver 17 for SQL Server")
    server = cfg["server"]
    database = cfg["database"]
    parts = [f"DRIVER={{{driver}}}", f"SERVER={server}", f"DATABASE={database}"]
    if cfg.get("trusted", True):
        parts.append("Trusted_Connection=yes")
    else:
        parts.append(f"UID={cfg['user']}")
        parts.append(f"PWD={cfg['password']}")
    return ";".join(parts)


# Build pools for each configured connection
pools: dict[str, ConnectionPool] = {}
for name, cfg in CONNECTIONS.items():
    try:
        pools[name] = ConnectionPool(build_conn_str(cfg))
    except Exception as e:
        print(f"Warning: could not create pool for '{name}': {e}")


# --- FastAPI App ---
app = FastAPI(title="MSSQL Proxy", version="2.0.0")


class QueryRequest(BaseModel):
    sql: str
    connection: str = "default"


class QueryResponse(BaseModel):
    data: list[dict]
    columns: list[str]
    rowcount: int = 0


@app.post("/query", response_model=QueryResponse)
def query(req: QueryRequest):
    if req.connection not in pools:
        available = ", ".join(pools.keys()) or "(none configured)"
        raise HTTPException(404, f"Connection '{req.connection}' not found. Available: {available}")

    pool = pools[req.connection]
    try:
        with pool.get() as conn:
            cursor = conn.cursor()
            cursor.execute(req.sql)
            if cursor.description:
                columns = [col[0] for col in cursor.description]
                rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
                return QueryResponse(data=rows, columns=columns, rowcount=len(rows))
            return QueryResponse(data=[], columns=[], rowcount=cursor.rowcount)
    except pyodbc.Error as e:
        raise HTTPException(500, f"SQL Error: {e}")
    except Exception as e:
        raise HTTPException(500, str(e))


@app.get("/health")
def health():
    return {
        "status": "ok",
        "connections": {name: {"pool_size": len(pool.pool)} for name, pool in pools.items()},
    }


@app.get("/health/{connection}")
def health_connection(connection: str):
    """Check a specific connection with SELECT 1."""
    if connection not in pools:
        raise HTTPException(404, f"Connection '{connection}' not found. Available: {', '.join(pools.keys())}")
    try:
        with pools[connection].get() as conn:
            conn.cursor().execute("SELECT 1")
            return {"status": "ok", "connection": connection}
    except Exception as e:
        return {"status": "error", "connection": connection, "error": str(e)}


@app.get("/connections")
def list_connections():
    return {
        name: {
            "server": cfg.get("server"),
            "database": cfg.get("database"),
            "trusted": cfg.get("trusted", True),
        }
        for name, cfg in CONNECTIONS.items()
    }


if __name__ == "__main__":
    import uvicorn

    print(f"MSSQL Proxy starting on http://0.0.0.0:{DEFAULT_PORT}")
    print(f"Connections: {', '.join(pools.keys()) or '(none)'}")
    print(f"Health: http://localhost:{DEFAULT_PORT}/health")
    uvicorn.run(app, host="0.0.0.0", port=DEFAULT_PORT)
