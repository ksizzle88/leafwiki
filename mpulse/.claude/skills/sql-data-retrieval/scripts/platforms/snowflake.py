"""Snowflake query execution via snow CLI."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path


def execute(sql_path: Path, connection: str, timeout: int, extra_args: list[str] | None = None) -> list[dict]:
    """Run SQL via snow CLI, return list of dicts."""
    cmd = ["snow", "sql", "-f", str(sql_path), "--format", "JSON", "-c", connection]
    if extra_args:
        cmd.extend(extra_args)

    result = subprocess.run(
        cmd, capture_output=True, text=True, timeout=timeout
    )

    if result.returncode != 0:
        error = result.stderr.strip() or result.stdout.strip() or f"snow exited with code {result.returncode}"
        raise RuntimeError(error)

    output = result.stdout.strip()
    if not output:
        return []

    data = json.loads(output)
    return data if isinstance(data, list) else [data]
