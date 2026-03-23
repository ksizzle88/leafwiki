"""File and project resolution utilities."""

from __future__ import annotations

import subprocess
from pathlib import Path


def project_name() -> str:
    """Get project name from git root or CWD."""
    try:
        root = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5
        )
        if root.returncode == 0:
            return Path(root.stdout.strip()).name
    except Exception:
        pass
    return Path.cwd().name


def find_query_sql(query_name: str, query_dir: Path, env: str, base_dir: Path) -> Path | None:
    """Find query.sql in standard locations."""
    # 1. Per-query folder
    if (query_dir / "query.sql").is_file():
        return query_dir / "query.sql"

    # 2. CWD
    cwd_file = Path.cwd() / f"{query_name}.sql"
    if cwd_file.is_file():
        return cwd_file

    # 3. Scan all project dirs
    for d in base_dir.iterdir():
        if not d.is_dir():
            continue
        candidate = d / env / query_name / "query.sql"
        if candidate.is_file():
            return candidate

    return None


def check_connection_safety(sql_path: Path, target_conn: str) -> None:
    """Warn if SQL file's -- connection: header doesn't match -c flag."""
    if not sql_path.is_file():
        return

    for line in sql_path.read_text().splitlines()[:5]:
        if line.startswith("-- connection:"):
            declared = line.split(":", 1)[1].strip()
            if declared and declared != target_conn:
                print(f"\nWARNING: query.sql was written for '{declared}' but you're running with -c {target_conn}")
                input("Press Enter to continue or Ctrl+C to abort...")
            return
