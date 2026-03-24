"""Output formatting — JSON to markdown table, error capture."""

from __future__ import annotations

import json
from pathlib import Path


def json_to_table(data: list[dict], max_rows: int = 0) -> str:
    """Convert a list of dicts to a markdown table string."""
    if not data:
        return "(no rows returned)"

    # Get all headers across all rows
    headers = list(dict.fromkeys(k for row in data for k in row))

    # Calculate column widths in a single pass over all rows
    widths = {h: len(h) for h in headers}
    for row in data:
        for h in headers:
            widths[h] = max(widths[h], len(str(row.get(h) or "")))
    widths = {h: min(w, 40) for h, w in widths.items()}

    # Build table
    lines = []

    # Header
    header = "| " + " | ".join(f"{h:<{widths[h]}}" for h in headers) + " |"
    sep = "| " + " | ".join("-" * widths[h] for h in headers) + " |"
    lines.append(header)
    lines.append(sep)

    # Rows
    total = len(data)
    limit = min(max_rows, total) if max_rows > 0 else total

    for row in data[:limit]:
        cells = []
        for h in headers:
            val = str(row.get(h) if row.get(h) is not None else "NULL")[:40]
            cells.append(f"{val:<{widths[h]}}")
        lines.append("| " + " | ".join(cells) + " |")

    if max_rows > 0 and total > max_rows:
        lines.append(f"... ({max_rows} of {total} rows shown)")

    return "\n".join(lines)


def write_output(query_dir: Path, data: list[dict]) -> tuple[Path, Path]:
    """Write dual output files. Returns (json_path, md_path)."""
    query_dir.mkdir(parents=True, exist_ok=True)
    json_path = query_dir / "out.json"
    md_path = query_dir / "out.md"

    json_path.write_text(json.dumps(data, indent=2, default=str))
    md_path.write_text(json_to_table(data))

    return json_path, md_path


def write_error(query_dir: Path, message: str, exit_code: int = 1, suggestion: str = "") -> None:
    """Write error to both output files."""
    query_dir.mkdir(parents=True, exist_ok=True)

    error_json = {"error": message, "exit_code": exit_code}
    (query_dir / "out.json").write_text(json.dumps(error_json, indent=2))

    md_lines = ["## Error", "", message]
    if suggestion:
        md_lines.extend(["", suggestion])
    (query_dir / "out.md").write_text("\n".join(md_lines))


def print_preview(data: list[dict], query_dir: Path) -> None:
    """Print first 20 rows to console + file paths."""
    if not data:
        print("  (no rows returned)")
    else:
        print(f"  Rows: {len(data)}\n")
        print(json_to_table(data, max_rows=20))

    print(f"\n  Folder: {query_dir}/")
    print(f"  JSON:   {query_dir}/out.json")
    print(f"  Table:  {query_dir}/out.md")
