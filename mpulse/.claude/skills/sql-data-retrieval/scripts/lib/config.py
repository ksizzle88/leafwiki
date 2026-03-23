"""Connection config parsing from connections.yaml."""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Any

import yaml


def find_config() -> Path:
    """Find connections.yaml in standard locations."""
    candidates = []

    # 1. CLAUDE_SKILL_DIR (set by Claude Code)
    skill_dir = os.environ.get("CLAUDE_SKILL_DIR", "")
    if skill_dir:
        candidates.append(Path(skill_dir) / "connections.yaml")
        candidates.append(Path(skill_dir).parent / "connections.yaml")

    # 2. Script's own dir (../../connections.yaml from lib/)
    candidates.append(Path(__file__).parent.parent.parent / "connections.yaml")

    # 3. User fallback
    candidates.append(Path.home() / ".connections.yaml")

    for p in candidates:
        if p.is_file():
            return p

    print("Error: connections.yaml not found. Searched:", file=sys.stderr)
    for p in candidates:
        print(f"  {p}", file=sys.stderr)
    sys.exit(1)


def load_config(path: Path | None = None) -> dict[str, Any]:
    """Load and return the full config."""
    path = path or find_config()
    with open(path) as f:
        return yaml.safe_load(f) or {}


def lookup_connection(name: str, cfg: dict | None = None) -> tuple[str, str, dict]:
    """Look up a connection by name. Returns (platform, env, config_dict)."""
    if cfg is None:
        cfg = load_config()

    connections = cfg.get("connections", {})
    for platform, entries in connections.items():
        if not isinstance(entries, dict):
            continue
        if name in entries:
            entry = entries[name] or {}
            env = entry.get("env", name) if isinstance(entry, dict) else name
            return platform, env, entry if isinstance(entry, dict) else {}

    all_names = []
    for entries in connections.values():
        if isinstance(entries, dict):
            all_names.extend(entries.keys())

    print(f"Error: connection '{name}' not found", file=sys.stderr)
    print(f"Available: {', '.join(all_names)}", file=sys.stderr)
    sys.exit(1)


def list_connections(cfg: dict | None = None) -> None:
    """Print all connections grouped by platform."""
    if cfg is None:
        cfg = load_config()

    connections = cfg.get("connections", {})
    total = sum(len(v) for v in connections.values() if isinstance(v, dict))
    print(f"Connections ({total} total):\n")

    for platform in sorted(connections):
        entries = connections[platform]
        if not isinstance(entries, dict):
            continue
        print(f"  {platform} ({len(entries)}):")
        for name, c in entries.items():
            env = c.get("env", name) if isinstance(c, dict) else name
            label = c.get("label", "") if isinstance(c, dict) else ""
            extra = f"  # {label}" if label else ""
            print(f"    {name:25s} env={env}{extra}")
        print()
