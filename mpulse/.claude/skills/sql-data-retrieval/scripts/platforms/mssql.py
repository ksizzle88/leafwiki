"""SQL Server query execution via HTTP proxy."""

from __future__ import annotations

import json
import os
import urllib.request
import urllib.error
from pathlib import Path

PROXY_URL = os.environ.get("MSSQL_PROXY_URL", "http://host.docker.internal:9999")


def execute(sql_path: Path, connection: str, timeout: int, extra_args: list[str] | None = None) -> list[dict]:
    """Run SQL via MSSQL proxy, return list of dicts."""
    # Health check
    try:
        urllib.request.urlopen(f"{PROXY_URL}/health", timeout=3)
    except Exception:
        raise RuntimeError(f"MSSQL proxy not reachable at {PROXY_URL}\nStart it: cd mpulse/.tools/mssql-proxy && start.bat")

    sql = sql_path.read_text().strip()
    if not sql:
        raise RuntimeError("SQL file is empty")

    payload = json.dumps({"sql": sql, "connection": connection}).encode()
    req = urllib.request.Request(
        f"{PROXY_URL}/query",
        data=payload,
        headers={"Content-Type": "application/json"},
    )

    try:
        resp = urllib.request.urlopen(req, timeout=timeout + 10)
        result = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode() if e.fp else ""
        try:
            detail = json.loads(body).get("detail", body)
        except Exception:
            detail = body
        raise RuntimeError(f"Proxy error ({e.code}): {detail}")
    except urllib.error.URLError as e:
        raise RuntimeError(f"Proxy connection failed: {e.reason}")

    if "error" in result:
        raise RuntimeError(result["error"])

    return result.get("data", [result])
