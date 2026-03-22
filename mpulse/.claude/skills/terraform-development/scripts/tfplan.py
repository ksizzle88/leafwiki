#!/usr/bin/env python3
"""
Terraform Plan Analyzer - Parse tfplan.json for quick structured analysis.

Commands:
    summary   (s)   Module table + action counts
    modules   (m)   Changes grouped by module
    resources (r)   Compact resource list with actions
    imports   (i)   Import IDs and actions (skips no-ops by default)
    details   (d)   Before/after diffs
    drift     (dr)  State vs config diffs (grouped by reason)
    moved     (mv)  Moved block resources
    updates   (u)   Update reasons (classified)
    issues    (x)   Deletes, replaces, unexpected changes
    diff      (df)  Compare two plans
    status    (st)  Approved vs pending dashboard
    approve   (ap)  Add entry to approved.yml
    report         Run multiple commands in one invocation (comma-separated)

Filters (work with most commands):
    -f, --filter PATTERN   Filter by resource address (regex)
    -m, --module MODULE    Filter by module path (substring)
    -a, --action ACTION    Filter by action (create/update/delete/replace)
    -n, --limit N          Limit output to first N resources
    --json                 JSON output (where supported)
    --pending              Show only unapproved changes (updates, issues)
    --all                  Show all entries including no-ops (imports)
    --verbose              Show all fields including noise (details)
    --no-color             Disable ANSI colors
    --output FILE          Write report to file (updates)

All commands default to ./tfplan.json if no file specified.
"""

import argparse
import io
import json
import os
import re
import sys
from pathlib import Path

import pandas as pd
import yaml
from tabulate import tabulate as tabulate_fn


# ── Color support ─────────────────────────────────────────────────────────

_use_color = True

def _init_color(force_no_color=False):
    """Set color mode based on TTY detection and NO_COLOR env var."""
    global _use_color
    if force_no_color or os.environ.get("NO_COLOR") is not None:
        _use_color = False
    elif not hasattr(sys.stdout, "isatty") or not sys.stdout.isatty():
        _use_color = False

BOLD = "\033[1m"
DIM = "\033[2m"
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
CYAN = "\033[36m"
RESET = "\033[0m"

def _c(code, text):
    return f"{code}{text}{RESET}" if _use_color else str(text)

def bold(text):   return _c(BOLD, text)
def dim(text):    return _c(DIM, text)
def red(text):    return _c(RED, text)
def green(text):  return _c(GREEN, text)
def yellow(text): return _c(YELLOW, text)
def cyan(text):   return _c(CYAN, text)


# ── Plan loading + caching ────────────────────────────────────────────────

def load_plan(path="tfplan.json"):
    """Load plan JSON, using cache if available and fresh."""
    path = Path(path)
    cache_path = path.parent / f".{path.stem}.cache.json"

    # Try cache first
    if cache_path.exists():
        try:
            stat = path.stat()
            with open(cache_path) as f:
                cache = json.load(f)
            if (cache.get("_mtime") == stat.st_mtime
                    and cache.get("_size") == stat.st_size):
                return cache["data"]
        except (json.JSONDecodeError, OSError, KeyError):
            pass  # Cache invalid, fall through to full load

    # Full load
    try:
        with open(path) as f:
            plan = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error: {path} contains invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)
    except OSError as e:
        print(f"Error: Could not read {path}: {e}", file=sys.stderr)
        sys.exit(1)

    # Write cache (best-effort)
    try:
        stat = path.stat()
        cache_data = {
            "_mtime": stat.st_mtime,
            "_size": stat.st_size,
            "data": {
                "resource_changes": plan.get("resource_changes", []),
                "format_version": plan.get("format_version"),
                "terraform_version": plan.get("terraform_version"),
            },
        }
        with open(cache_path, "w") as f:
            json.dump(cache_data, f, separators=(",", ":"))
    except OSError:
        pass  # Cache write failed, no big deal

    return plan


# ── Approved changes (YAML) ──────────────────────────────────────────────

_APPROVED_YML_HEADER = """\
# approved.yml - Reviewed changes for this plan
# Statuses: ACCEPT | FIX | SUPPRESS | SKIP | UNKNOWN
# UNKNOWN entries need manual review - classify and update status
#
# Change type reference: ~/.claude/skills/terraform-development/reference/migration-change-types.md
"""


def load_approved(plan_dir="."):
    """Load approved.yml rules from the plan directory."""
    yml_path = Path(plan_dir) / "approved.yml"
    if not yml_path.exists():
        return []
    try:
        data = yaml.safe_load(yml_path.read_text())
        return data.get("rules", []) if data else []
    except (yaml.YAMLError, OSError):
        return []


def _write_approved_yml(path, data):
    """Write approved.yml with header comment and consistent formatting."""
    body = yaml.dump(data, default_flow_style=False, sort_keys=False,
                     allow_unicode=True)
    path.write_text(_APPROVED_YML_HEADER + "\n" + body)


def check_approved(address, reason, rules):
    """Check if a resource change matches any approved rule.
    Returns (status, note) or (None, None) if not matched."""
    for rule in rules:
        addr_match = True
        reason_match = True

        if "address" in rule:
            addr_match = bool(re.search(rule["address"], address, re.IGNORECASE))
        if "reason" in rule:
            reason_match = bool(re.search(rule["reason"], reason, re.IGNORECASE))

        if "address" in rule and "reason" in rule:
            if addr_match and reason_match:
                return rule.get("status", "ACCEPT"), rule.get("note", "")
        elif "address" in rule:
            if addr_match:
                return rule.get("status", "ACCEPT"), rule.get("note", "")
        elif "reason" in rule:
            if reason_match:
                return rule.get("status", "ACCEPT"), rule.get("note", "")

    return None, None


# ── Shared helpers ────────────────────────────────────────────────────────

ACTION_NAME_MAP = {
    ("delete",): "Delete", ("delete", "create"): "Replace",
    ("create", "delete"): "Replace", ("create",): "Create",
    ("update",): "Update", ("no-op",): "No-op",
}

def get_action_label(actions):
    """Convert action tuple to human-readable label."""
    a = tuple(actions)
    return {
        ("no-op",): "no-op", ("create",): "create", ("read",): "read",
        ("update",): "update", ("delete",): "delete",
        ("delete", "create"): "replace (delete+create)",
        ("create", "delete"): "replace (create+delete)",
    }.get(a, "+".join(a))


def get_action_symbol(actions):
    """Action type to compact symbol for listings."""
    a = tuple(actions)
    return {
        ("no-op",): "  ", ("create",): "+ ", ("read",): "? ",
        ("update",): "~ ", ("delete",): "- ",
        ("delete", "create"): "+-", ("create", "delete"): "+-",
    }.get(a, "??")


def colorize_action(actions):
    """Color-code action symbols."""
    a = tuple(actions)
    symbol = get_action_symbol(a)
    if a == ("delete",) or a in (("delete", "create"), ("create", "delete")):
        return red(symbol)
    if a == ("create",):
        return green(symbol)
    if a == ("update",):
        return yellow(symbol)
    return symbol


def parse_module_path(address):
    """Extract the module path from a resource address."""
    parts = address.split(".")
    module_parts = []
    i = 0
    while i < len(parts):
        if parts[i] == "module" and i + 1 < len(parts):
            module_parts.append(f"module.{parts[i+1]}")
            i += 2
        else:
            break
    return ".".join(module_parts) if module_parts else "(root)"


def resource_name_from_address(address):
    """Extract the resource name (without module prefix) from an address."""
    mod = parse_module_path(address)
    return address if mod == "(root)" else address[len(mod) + 1:]


# ── DataFrame construction + filtering ────────────────────────────────────

def build_dataframe(plan):
    """Build a DataFrame from resource_changes with derived columns."""
    changes = plan.get("resource_changes", [])
    if not changes:
        return pd.DataFrame()

    records = []
    for c in changes:
        change = c["change"]
        actions = tuple(change["actions"])
        importing = change.get("importing")
        before = change.get("before") or {}
        after = change.get("after") or {}

        records.append({
            "address": c["address"],
            "module": parse_module_path(c["address"]),
            "resource_name": resource_name_from_address(c["address"]),
            "actions": actions,
            "action_label": get_action_label(actions),
            "is_import": bool(importing),
            "import_id": (importing or {}).get("id", ""),
            "action_reason": change.get("action_reason", ""),
            "previous_address": c.get("previous_address", ""),
            "before": before,
            "after": after,
        })

    return pd.DataFrame(records)


def get_changes(plan, filter_pattern=None, module_filter=None,
                action_filter=None, skip_noop=True, limit=None, **_extra):
    """Get filtered resource changes as a list of dicts (legacy interface)."""
    results = []
    for c in plan.get("resource_changes", []):
        actions = tuple(c["change"]["actions"])
        if skip_noop and actions in (("no-op",), ("read",)):
            continue

        addr = c["address"]
        if filter_pattern and not re.search(filter_pattern, addr, re.IGNORECASE):
            continue
        if module_filter and module_filter.lower() not in parse_module_path(addr).lower():
            continue
        if action_filter:
            action_str = "+".join(actions)
            if action_filter.lower() not in action_str.lower():
                if not (action_filter.lower() == "replace" and actions in (
                    ("delete", "create"), ("create", "delete"))):
                    continue

        results.append(c)
        if limit and len(results) >= limit:
            break
    return results


def filter_df(df, filter_pattern=None, module_filter=None,
              action_filter=None, skip_noop=True, limit=None, **_extra):
    """Filter a resource changes DataFrame."""
    if df.empty:
        return df
    mask = pd.Series(True, index=df.index)
    if skip_noop:
        mask &= ~df["actions"].isin([("no-op",), ("read",)])
    if filter_pattern:
        mask &= df["address"].str.contains(filter_pattern, case=False, regex=True)
    if module_filter:
        mask &= df["module"].str.contains(module_filter, case=False)
    if action_filter:
        af = action_filter.lower()
        action_str = df["actions"].apply(lambda a: "+".join(a))
        if af == "replace":
            mask &= df["actions"].isin([("delete", "create"), ("create", "delete")])
        else:
            mask &= action_str.str.contains(af, case=False)
    result = df[mask]
    if limit:
        result = result.head(limit)
    return result


def truncate(value, max_len=200):
    s = json.dumps(value) if isinstance(value, (dict, list)) else str(value)
    return s[:max_len - 3] + "..." if len(s) > max_len else s


def format_value(value, max_len=200):
    if value is None:
        return "null"
    if isinstance(value, (dict, list)):
        s = json.dumps(value, indent=2)
        if len(s) > max_len:
            if isinstance(value, list):
                return f"[{len(value)} items, truncated]"
            return f"{{{len(value)} keys, truncated}}"
        return s
    return str(value)


# ── Table printer (tabulate wrapper) ──────────────────────────────────────

def print_table(headers, rows, right_align=None, totals=None, title=None):
    """Print a formatted table with optional totals row."""
    if right_align is None:
        right_align = set(range(1, len(headers)))

    colalign = tuple("right" if i in right_align else "left"
                     for i in range(len(headers)))

    all_rows = list(rows)
    if totals:
        all_rows.append(["───"] * len(headers))
        all_rows.append([bold(str(c)) for c in totals])

    if title:
        print(title)
    print(tabulate_fn(all_rows, headers=headers, colalign=colalign,
                      tablefmt="simple"))


# ── Change classification ────────────────────────────────────────────────

def classify_change(key, before_val, after_val):
    """Classify a single attribute change into a short reason."""
    k = key.lower()

    classifiers = {
        "tags_all": lambda b, a: "default_tags added" if b in (None, {}) and isinstance(a, dict) else "tags_all changed",
        "comment": lambda b, a: f'comment added: "{str(a)[:50]}"' if b is None and a is not None else "comment changed",
        "show_output": lambda b, a: "show_output refresh (computed)",
        "describe_output": lambda b, a: "describe_output refresh (computed)",
        "policy": lambda b, a: "policy recalc (known after apply)",
        "assume_role_policy": lambda b, a: "assume_role_policy recalc",
        "disabled": lambda b, a: f'disabled: "{b}" -> "{a}"',
        "mins_to_unlock": lambda b, a: "mins_to_unlock added",
        "saml2_x509_cert": lambda b, a: "x509_cert -> sensitive",
        "saml2_requested_nameid_format": lambda b, a: "nameid_format set",
    }

    if k in classifiers:
        return classifiers[k](before_val, after_val)

    if k == "privileges":
        if before_val == [] and isinstance(after_val, list) and after_val:
            return f"privilege materialization: [] -> [{','.join(after_val)}]"
        if isinstance(before_val, list) and isinstance(after_val, list):
            added = set(after_val) - set(before_val)
            removed = set(before_val) - set(after_val)
            parts = []
            if added: parts.append(f"+{','.join(sorted(added))}")
            if removed: parts.append(f"-{','.join(sorted(removed))}")
            return f"privileges: {' '.join(parts)}"
        return "privileges changed"

    if "homepage_url" in k:
        return "homepage_url removed"

    return f"{key} changed"


def summarize_update_reasons(before, after):
    """Build a single-line reason string from all changed attributes."""
    before = before or {}
    after = after or {}
    reasons = []
    for k in sorted(set(list(before.keys()) + list(after.keys()))):
        bv, av = before.get(k), after.get(k)
        if bv != av:
            reason = classify_change(k, bv, av)
            if reason not in reasons:
                reasons.append(reason)

    primary = [r for r in reasons if "show_output" not in r and "describe_output" not in r]
    computed = [r for r in reasons if "show_output" in r or "describe_output" in r]
    return "; ".join(primary) if primary else "; ".join(computed) if computed else "(no visible diff)"


def _add_reason_column(df):
    """Add a 'reason' column to a DataFrame of update resources."""
    df["reason"] = df.apply(
        lambda r: summarize_update_reasons(r["before"], r["after"]), axis=1)
    return df


# ── Commands ──────────────────────────────────────────────────────────────

def cmd_summary(plan, **kwargs):
    """Module table + action counts. Compact overview."""
    df = build_dataframe(plan)
    if df.empty:
        print("  No changes.")
        return

    # Exclude reads from the table
    table_df = df[df["actions"] != ("read",)].copy()

    # Map each resource to its display column
    def col_name(row):
        if row["is_import"] and row["actions"] == ("no-op",):
            return "Import"
        return ACTION_NAME_MAP.get(row["actions"], "+".join(row["actions"]))

    table_df["col"] = table_df.apply(col_name, axis=1)

    total = len(table_df)
    actionable = len(table_df[~table_df["actions"].isin([("no-op",)])])
    print(f"\n{bold('Plan Summary')}: {len(df)} resources, {bold(str(actionable))} changing\n")

    if table_df.empty:
        print("  No changes.")
        return

    # Pivot: module x action column
    ct = pd.crosstab(table_df["module"], table_df["col"])

    # Reorder columns to standard order, drop empty
    col_order = [c for c in ["Create", "Update", "Replace", "Delete", "Import", "No-op"]
                 if c in ct.columns]
    ct = ct[col_order]
    ct["Total"] = ct.sum(axis=1)

    # Sort modules alphabetically, root last
    modules = sorted(m for m in ct.index if m != "(root)")
    if "(root)" in ct.index:
        modules.append("(root)")
    ct = ct.loc[modules]

    # Strip "module." prefix for display
    ct.index = [m[7:] if m.startswith("module.") else m for m in ct.index]

    # Render via print_table
    totals_row = ["TOTAL"] + [int(ct[c].sum()) for c in ct.columns]
    headers = ["Module"] + list(ct.columns)
    rows = [[idx] + [int(v) for v in row] for idx, row in ct.iterrows()]
    print_table(headers, rows, totals=totals_row)

    # Compact action counts below the table
    print()
    action_counts = df["actions"].value_counts()
    for action_key in [("delete",), ("delete", "create"), ("create", "delete"),
                       ("update",), ("create",), ("read",)]:
        count = action_counts.get(action_key, 0)
        if count:
            symbol = colorize_action(action_key)
            print(f"  {symbol} {get_action_label(action_key)}: {count}")

    # Import breakdown
    imports = df[df["is_import"]]
    if not imports.empty:
        import_noop = len(imports[imports["actions"] == ("no-op",)])
        import_update = len(imports[imports["actions"] == ("update",)])
        detail_parts = []
        if import_noop:
            detail_parts.append(f"{import_noop} clean")
        if import_update:
            detail_parts.append(f"{import_update} with updates")
        detail = f" ({', '.join(detail_parts)})" if detail_parts else ""
        print(f"  {cyan('i')}  import: {len(imports)}{detail}")

    # No-ops (excluding import no-ops)
    noop_count = action_counts.get(("no-op",), 0) - len(imports[imports["actions"] == ("no-op",)])
    if noop_count:
        print(f"     no-op: {noop_count}")

    # Pending count if approved.yml exists
    approved_rules = load_approved()
    if approved_rules:
        updates = df[df["actions"] == ("update",)].copy()
        _add_reason_column(updates)
        pending = sum(
            1 for _, r in updates.iterrows()
            if check_approved(r["address"], r["reason"], approved_rules)[0] is None
        )
        total_updates = len(updates)
        print(f"\n  {bold(f'{pending}/{total_updates}')} updates pending review "
              f"({total_updates - pending} approved)")

    print(f"\n  Use {dim('resources')} for full list, {dim('issues')} for problems, "
          f"{dim('updates --pending')} for unresolved.")


def cmd_resources(plan, **kwargs):
    """Compact resource list with action symbols."""
    changes = get_changes(plan, skip_noop=False, **kwargs)
    if not changes:
        print("No matching resources.")
        return

    print(f"Resources ({len(changes)})\n")
    for c in sorted(changes, key=lambda x: x["address"]):
        actions = tuple(c["change"]["actions"])
        importing = c.get("change", {}).get("importing")
        suffix = dim(f"  [import: {importing.get('id', '?')}]") if importing else ""
        print(f"  {colorize_action(actions)} {c['address']}  {dim(get_action_label(actions))}{suffix}")


def cmd_modules(plan, **kwargs):
    """Show changes grouped by module path."""
    df = build_dataframe(plan)
    df = filter_df(df, **kwargs)
    if df.empty:
        print("No changes detected.")
        return

    total = len(df)
    print(f"Changes by Module ({total} resources)\n")
    for mod, group in df.groupby("module", sort=True):
        print(f"── {bold(mod)} ({len(group)}) ──")
        for _, row in group.sort_values("resource_name").iterrows():
            print(f"  {colorize_action(row['actions'])} {row['resource_name']}")
        print()


def cmd_imports(plan, show_all=False, **kwargs):
    """Show imported resources. Skips no-ops by default."""
    df = build_dataframe(plan)
    df = filter_df(df, skip_noop=False, **kwargs)
    imports = df[df["is_import"] | (df["action_reason"] == "import_planned")]

    if not show_all:
        imports = imports[~imports["actions"].isin([("no-op",), ("read",)])]

    if imports.empty:
        msg = "No imports with changes." if not show_all else "No imports detected."
        print(f"{msg} Use --all to include no-ops." if not show_all else msg)
        return

    print(f"Imports ({len(imports)})\n")
    for _, row in imports.sort_values("address").iterrows():
        symbol = colorize_action(row["actions"])
        label = get_action_label(row["actions"])
        import_id = dim(f"[{row['import_id'] or 'N/A'}]")
        print(f"  {symbol} {row['address']}  {dim(label)}  {import_id}")


def cmd_details(plan, verbose=False, **kwargs):
    """Show detailed before/after for specific resources."""
    changes = get_changes(plan, skip_noop=not kwargs.get("filter_pattern"), **kwargs)
    if not changes:
        print("No matching resources. Try broadening your --filter or --module.")
        return

    noise_keys = {"show_output", "describe_output", "parameters", "fully_qualified_name"}

    for c in changes:
        addr = c["address"]
        actions = tuple(c["change"]["actions"])
        change = c["change"]
        importing = change.get("importing")
        action_reason = change.get("action_reason")

        print(f"{'='*80}")
        print(f"  {bold(addr)}")
        print(f"  Action: {get_action_label(actions)}")
        if action_reason == "import_planned" or importing:
            print(f"  Import: {importing.get('id', 'N/A') if importing else 'N/A'}")
        print(f"{'='*80}")

        before = change.get("before") or {}
        after = change.get("after") or {}
        skip = set() if verbose else noise_keys

        if actions == ("create",):
            print("  NEW RESOURCE:")
            for k, v in sorted(after.items()):
                if v is not None and k not in skip:
                    print(f"    {k} = {format_value(v)}")
        elif actions == ("delete",):
            print("  DESTROYING:")
            for k, v in sorted(before.items()):
                if v is not None and k not in skip:
                    print(f"    {k} = {format_value(v)}")
        else:
            label = "CHANGES:" if actions == ("update",) else "CHANGES (before -> after):"
            print(f"  {label}")
            for k in sorted(set(list(before.keys()) + list(after.keys()))):
                bv, av = before.get(k), after.get(k)
                if bv != av:
                    if k in skip:
                        print(f"    {dim(k)}: {dim('[computed, hidden]')}")
                    else:
                        print(f"    {k}:")
                        print(f"      - {format_value(bv)}")
                        print(f"      + {format_value(av)}")
        print()


def cmd_drift(plan, **kwargs):
    """Show drift grouped by reason pattern for compact output."""
    df = build_dataframe(plan)
    df = filter_df(df, **kwargs)
    drifted = df[df["actions"].isin([("update",), ("delete", "create"), ("create", "delete")])]

    if drifted.empty:
        print("No drift detected -- config matches state.")
        return

    # Compute reasons and diffs
    drifted = drifted.copy()
    _add_reason_column(drifted)
    drifted["diffs"] = drifted.apply(
        lambda r: {k: {"before": r["before"].get(k), "after": r["after"].get(k)}
                   for k in sorted(set(list(r["before"].keys()) + list(r["after"].keys())))
                   if r["before"].get(k) != r["after"].get(k)},
        axis=1)

    grouped = drifted.groupby("reason", sort=True)
    print(f"Drift Report ({len(drifted)} resources, {grouped.ngroups} categories)\n")

    for reason, group in grouped:
        print(f"── {bold(reason)} ({len(group)} resources) ──")

        # Show the diff from the first resource as representative
        first_diffs = group.iloc[0]["diffs"]
        for k, v in sorted(first_diffs.items()):
            print(f"  {k}:")
            print(f"    - {truncate(v['before'], 120)}")
            print(f"    + {truncate(v['after'], 120)}")

        # List all affected resources
        if len(group) > 1:
            print(f"\n  Affected resources:")
            for _, row in group.sort_values("address").iterrows():
                print(f"    {row['address']}")
        else:
            print(f"  Resource: {group.iloc[0]['address']}")
        print()


def cmd_moved(plan, **kwargs):
    """Show resources that have moved blocks."""
    df = build_dataframe(plan)
    if df.empty:
        print("No moved resources detected in plan.")
        return

    moved = df[(df["previous_address"] != "") & (df["previous_address"] != df["address"])]
    if moved.empty:
        print("No moved resources detected in plan.")
        return

    print(f"Moved Resources ({len(moved)})\n")
    for _, row in moved.sort_values("address").iterrows():
        print(f"  {row['previous_address']}")
        print(f"    -> {row['address']}")
        print()


def cmd_updates(plan, output_json=False, pending_only=False,
                output_file=None, output_json_file=None, **kwargs):
    """Show update resources with classified reasons."""
    df = build_dataframe(plan)
    df = filter_df(df, **kwargs)
    updates = df[df["actions"] == ("update",)].copy()

    if updates.empty:
        if pending_only:
            print(f"{bold('All updates approved!')} No pending changes.")
        else:
            print("No update resources in plan.")
        return

    _add_reason_column(updates)

    # Check approval status
    approved_rules = load_approved() if pending_only else []
    if approved_rules:
        updates[["status", "note"]] = updates.apply(
            lambda r: pd.Series(check_approved(r["address"], r["reason"], approved_rules)),
            axis=1)
        if pending_only:
            updates = updates[updates["status"].isna()]

    # Compute attr_changes for JSON output
    def attr_changes(row):
        before, after = row["before"], row["after"]
        return [{"attribute": k, "old": before.get(k), "new": after.get(k)}
                for k in sorted(set(list(before.keys()) + list(after.keys())))
                if before.get(k) != after.get(k)]

    updates = updates.sort_values("address")

    # JSON output
    if output_json:
        updates["changes"] = updates.apply(attr_changes, axis=1)
        json_data = {
            "total": len(updates),
            "updates": [{"index": i, "address": r["address"], "reason": r["reason"],
                         "changes": r["changes"]}
                        for i, (_, r) in enumerate(updates.iterrows(), 1)],
        }
        print(json.dumps(json_data, indent=2))
        return

    # File outputs
    if output_file:
        updates["changes"] = updates.apply(attr_changes, axis=1)
        max_addr = updates["address"].str.len().max() + 2
        with open(output_file, "w") as f:
            label = "PENDING" if pending_only else "ALL"
            f.write(f"PLAN UPDATES - {label} ({len(updates)} resources)\n")
            f.write(f"{'=' * (max_addr + 80)}\n")
            f.write(f"{'#':<4} {'RESOURCE ADDRESS':<{max_addr}} REASON\n")
            f.write(f"{'---':<4} {'-' * (max_addr - 1)} {'-' * 78}\n")
            for i, (_, u) in enumerate(updates.iterrows(), 1):
                f.write(f"{i:<4} {u['address']:<{max_addr}} {u['reason']}\n")
            f.write(f"\n{'=' * (max_addr + 80)}\n")
            f.write(f"TOTAL: {len(updates)} updates\n")
        print(f"Report written to: {output_file}")

    if output_json_file:
        updates["changes"] = updates.apply(attr_changes, axis=1)
        json_data = {
            "total": len(updates),
            "updates": [{"index": i, "address": r["address"], "reason": r["reason"],
                         "changes": r["changes"]}
                        for i, (_, r) in enumerate(updates.iterrows(), 1)],
        }
        with open(output_json_file, "w") as f:
            json.dump(json_data, f, indent=2)
        print(f"JSON report written to: {output_json_file}")

    if output_file or output_json_file:
        return

    # Terminal output
    max_addr = updates["address"].str.len().max()
    addr_width = min(max_addr + 2, 70)

    label = "Pending Updates" if pending_only else "Updates"
    print(f"{label} ({len(updates)} resources)\n")
    print(f"{'#':<4} {'RESOURCE ADDRESS':<{addr_width}} REASON")
    print(f"{'---':<4} {'-' * (addr_width - 1)} {'-' * 50}")

    for i, (_, u) in enumerate(updates.iterrows(), 1):
        addr = u["address"]
        if len(addr) > addr_width - 2:
            addr = addr[:addr_width - 5] + "..."
        print(f"{i:<4} {addr:<{addr_width}} {u['reason']}")

    print(f"\nTotal: {len(updates)} {label.lower()}")


def cmd_issues(plan, pending_only=False, **kwargs):
    """Show only problems: deletes, replaces, and imports needing attention."""
    df = build_dataframe(plan)
    df = filter_df(df, skip_noop=False, **kwargs)

    if df.empty:
        print(f"{bold('No issues found.')} Plan looks clean.")
        return

    approved_rules = load_approved() if pending_only else []

    # Filter out approved updates if pending_only
    if pending_only and approved_rules:
        updates_mask = df["actions"] == ("update",)
        updates = df[updates_mask].copy()
        if not updates.empty:
            _add_reason_column(updates)
            updates["approved"] = updates.apply(
                lambda r: check_approved(r["address"], r["reason"], approved_rules)[0] is not None,
                axis=1)
            approved_addrs = set(updates[updates["approved"]]["address"])
            df = df[~df["address"].isin(approved_addrs)]

    deletes = df[df["actions"] == ("delete",)]
    replaces = df[df["actions"].isin([("delete", "create"), ("create", "delete")])]
    import_updates = df[df["is_import"] & (df["actions"] == ("update",))]
    unexpected_creates = df[
        (df["actions"] == ("create",)) & ~df["is_import"] &
        (df["action_reason"] != "import_planned")
    ]

    total = len(deletes) + len(replaces) + len(import_updates) + len(unexpected_creates)
    if total == 0:
        print(f"{bold('No issues found.')} Plan looks clean.")
        return

    print(f"{bold('Issues Found')}: {total} resources need attention\n")

    if not deletes.empty:
        print(f"{red('=== DELETES')} ({len(deletes)}) {red('===')}")
        print("  These resources will be DESTROYED.\n")
        for _, c in deletes.sort_values("address").iterrows():
            print(f"  {red('-')} {c['address']}")
        print()

    if not replaces.empty:
        print(f"{red('=== REPLACES')} ({len(replaces)}) {red('===')}")
        print("  These will be destroyed and recreated.\n")
        for _, c in replaces.sort_values("address").iterrows():
            before, after = c["before"], c["after"]
            diffs = [k for k in sorted(set(list(before.keys()) + list(after.keys())))
                     if before.get(k) != after.get(k)]
            diff_str = ", ".join(diffs[:5])
            if len(diffs) > 5:
                diff_str += f" (+{len(diffs)-5} more)"
            print(f"  {red('+-')} {c['address']}")
            print(f"       changed: {diff_str}")
        print()

    if not import_updates.empty:
        _add_reason_column(import_updates)
        print(f"{yellow('=== IMPORT + UPDATE')} ({len(import_updates)}) {yellow('===')}")
        print("  Imported resources that will also be updated.\n")
        for _, c in import_updates.sort_values("address").iterrows():
            print(f"  {yellow('~')} {c['address']}")
            print(f"       import_id: {c['import_id'] or '?'}")
            print(f"       reason:    {c['reason']}")
        print()

    if not unexpected_creates.empty:
        print(f"{green('=== NEW RESOURCES')} ({len(unexpected_creates)}) {green('===')}")
        print("  New resources being created. Verify these are intentional.\n")
        for _, c in unexpected_creates.sort_values("address").iterrows():
            print(f"  {green('+')} {c['address']}")
        print()


def cmd_diff(plan, old_plan_path=None, **kwargs):
    """Compare current plan to a previous plan."""
    if not old_plan_path:
        for candidate in ["tfplan.prev.json", "tfplan.old.json"]:
            if Path(candidate).exists():
                old_plan_path = candidate
                break

    if not old_plan_path or not Path(old_plan_path).exists():
        print("Usage: tfplan.py diff [current.json] [previous.json]")
        print("\nTo use plan diff:")
        print("  1. Before re-planning: cp tfplan.json tfplan.prev.json")
        print("  2. Re-run plan")
        print("  3. tfplan.py diff tfplan.json tfplan.prev.json")
        return

    old_plan = load_plan(old_plan_path)

    # Build address -> action maps (exclude no-ops and reads)
    new_df = build_dataframe(plan)
    old_df = build_dataframe(old_plan)

    new_active = new_df[~new_df["actions"].isin([("no-op",), ("read",)])]
    old_active = old_df[~old_df["actions"].isin([("no-op",), ("read",)])]

    new_map = dict(zip(new_active["address"], new_active["actions"]))
    old_map = dict(zip(old_active["address"], old_active["actions"]))

    all_addrs = sorted(set(list(new_map.keys()) + list(old_map.keys())))

    fixed, new_issues, changed, unchanged = [], [], [], []
    for addr in all_addrs:
        old_a, new_a = old_map.get(addr), new_map.get(addr)
        if old_a and not new_a:
            fixed.append((addr, old_a))
        elif new_a and not old_a:
            new_issues.append((addr, new_a))
        elif old_a != new_a:
            changed.append((addr, old_a, new_a))
        else:
            unchanged.append((addr, new_a))

    print(f"\n{bold('Plan Diff')}: comparing to {old_plan_path}\n")

    if fixed:
        print(f"{green(f'=== FIXED ({len(fixed)}) ===')}")
        for addr, action in fixed:
            print(f"  {green('OK')} {addr}  {dim(f'was: {get_action_label(action)}')}")
        print()

    if new_issues:
        print(f"{red(f'=== NEW ISSUES ({len(new_issues)}) ===')}")
        for addr, action in new_issues:
            print(f"  {red('!!')} {addr}  {get_action_label(action)}")
        print()

    if changed:
        print(f"{yellow(f'=== ACTION CHANGED ({len(changed)}) ===')}")
        for addr, old_a, new_a in changed:
            print(f"  {yellow('~>')} {addr}")
            print(f"       {get_action_label(old_a)} -> {get_action_label(new_a)}")
        print()

    if unchanged:
        print(f"  {dim(f'{len(unchanged)} resources still changing (unchanged between plans)')}")

    if not fixed and not new_issues and not changed:
        print("  No differences between plans.")

    print(f"\nSummary: {len(fixed)} fixed, {len(new_issues)} new, "
          f"{len(changed)} changed action, {len(unchanged)} unchanged")


def cmd_status(plan, **kwargs):
    """Dashboard showing approved vs pending counts by category."""
    df = build_dataframe(plan)
    df = filter_df(df, **kwargs)
    updates = df[df["actions"] == ("update",)].copy()

    if updates.empty:
        print("No updates in plan.")
        return

    approved_rules = load_approved()

    # Add reason + approval status
    _add_reason_column(updates)
    updates[["status", "note"]] = updates.apply(
        lambda r: pd.Series(check_approved(r["address"], r["reason"], approved_rules)),
        axis=1)
    updates["status"] = updates["status"].fillna("PENDING")

    print(f"\n{bold('Migration Status')}: {len(updates)} total updates\n")

    # Status counts
    status_counts = updates["status"].value_counts()
    pending = status_counts.get("PENDING", 0)

    status_colors = {"PENDING": red, "ACCEPT": green, "FIX": yellow,
                     "SUPPRESS": cyan, "SKIP": dim}
    headers = ["Status", "Count"]
    rows = []
    # PENDING first, then sorted
    for status in ["PENDING"] + sorted(s for s in status_counts.index if s != "PENDING"):
        count = status_counts.get(status, 0)
        if count:
            color_fn = status_colors.get(status, str)
            rows.append([color_fn(status), count])
    print_table(headers, rows, right_align={1})

    # Pending by reason category
    if pending:
        print(f"\n{bold('Pending by Category')}:\n")
        pending_df = updates[updates["status"] == "PENDING"]
        reason_counts = pending_df.groupby("reason")["address"].count().sort_values(ascending=False)
        for reason, count in reason_counts.items():
            print(f"  {yellow(f'{count:>3}')}  {reason}")

    # Approved rules summary
    if approved_rules:
        print(f"\n{dim(f'{len(approved_rules)} rules in approved.yml')}")
    else:
        print(f"\n{dim('No approved.yml found. Create one to track review progress.')}")
        print(f"{dim('  tfplan.py approve --reason \"pattern\" --status ACCEPT --note \"reason\"')}")


def cmd_approve(plan, reason_pattern=None, address_pattern=None,
                approve_status="ACCEPT", approve_note="", **kwargs):
    """Add an entry to approved.yml."""
    if not reason_pattern and not address_pattern:
        print("Usage: tfplan.py approve --reason PATTERN [--status STATUS] [--note NOTE]")
        print("       tfplan.py approve --address PATTERN [--status STATUS] [--note NOTE]")
        print("\nStatuses: ACCEPT, FIX, SUPPRESS, SKIP")
        return

    yml_path = Path("approved.yml")

    # Show what would match
    df = build_dataframe(plan)
    df = filter_df(df, **kwargs)
    updates = df[df["actions"] == ("update",)].copy()
    _add_reason_column(updates)

    matches = 0
    for _, r in updates.iterrows():
        addr_match = bool(re.search(address_pattern, r["address"], re.IGNORECASE)) if address_pattern else True
        reason_match = bool(re.search(reason_pattern, r["reason"], re.IGNORECASE)) if reason_pattern else True
        if addr_match and reason_match:
            matches += 1

    # Load/modify/dump round-trip
    if yml_path.exists():
        data = yaml.safe_load(yml_path.read_text()) or {}
    else:
        data = {}
    rules_list = data.setdefault("rules", [])
    entry = {}
    if reason_pattern:
        entry["reason"] = reason_pattern
    if address_pattern:
        entry["address"] = address_pattern
    entry["status"] = approve_status
    if approve_note:
        entry["note"] = approve_note
    rules_list.append(entry)
    _write_approved_yml(yml_path, data)

    print(f"Added rule to approved.yml ({matches} resources match):")
    if reason_pattern:
        print(f"  reason:  {reason_pattern}")
    if address_pattern:
        print(f"  address: {address_pattern}")
    print(f"  status:  {approve_status}")
    if approve_note:
        print(f"  note:    {approve_note}")


# ── Generate approved.yml ─────────────────────────────────────────────────

def _reason_to_pattern(reason):
    """Convert a full reason string to a reasonable regex pattern for matching."""
    # For compound reasons, use the first part before semicolon
    parts = reason.split(";")
    core = parts[0].strip()

    # For privilege materialization, generalize the specific privileges
    if "privilege materialization: [] -> " in core:
        return "privilege materialization"
    # For privileges: +X, keep the pattern
    if core.startswith("privileges: +"):
        return "privileges: \\\\+"
    # For comment added with content, generalize
    if core.startswith("comment added:"):
        return "comment added"
    return core


def cmd_generate_approved(plan, plan_dir=".", **kwargs):
    """Generate or update approved.yml from plan data.

    - Discovers all update categories from the plan
    - Existing rules whose reasons still match are preserved as-is
    - New categories get status UNKNOWN for manual review
    - Rules whose reasons no longer appear are dropped
    """
    df = build_dataframe(plan)
    df = filter_df(df, **kwargs)
    updates = df[df["actions"] == ("update",)].copy()

    if updates.empty:
        print("No updates in plan. Nothing to generate.")
        return

    yml_path = Path(plan_dir) / "approved.yml"

    # Load existing rules
    existing_rules = load_approved(plan_dir)
    existing_by_reason = {r["reason"]: r for r in existing_rules
                         if "reason" in r and "address" not in r}
    existing_by_address = {(r.get("address", ""), r.get("reason", "")): r
                          for r in existing_rules if "address" in r}

    # Compute reasons and patterns
    _add_reason_column(updates)
    updates["pattern"] = updates["reason"].apply(_reason_to_pattern)

    # Group by pattern — dedup is automatic
    grouped = updates.groupby("pattern").agg(
        count=("address", "size"),
        first_reason=("reason", "first"),
    ).sort_values("count", ascending=False)

    rules = []
    preserved = 0
    new_rules = 0

    for pattern, row in grouped.iterrows():
        # Check if an existing rule already covers this reason
        matched_existing = None
        for existing_reason, rule in existing_by_reason.items():
            try:
                if re.search(existing_reason, row["first_reason"], re.IGNORECASE):
                    matched_existing = rule
                    break
            except re.error:
                if existing_reason.lower() in row["first_reason"].lower():
                    matched_existing = rule
                    break

        if matched_existing:
            if matched_existing not in rules:
                rules.append(matched_existing)
            preserved += 1
            continue

        # New pattern — always UNKNOWN, human decides
        rules.append({
            "reason": pattern,
            "status": "UNKNOWN",
            "note": f"{row['count']} resources",
        })
        new_rules += 1

    # Also preserve address-specific rules that still match plan resources
    all_addrs = set(updates["address"])
    for (addr_pat, reason_pat), rule in existing_by_address.items():
        try:
            if any(re.search(addr_pat, a, re.IGNORECASE) for a in all_addrs):
                rules.append(rule)
                preserved += 1
        except re.error:
            pass

    _write_approved_yml(yml_path, {"rules": rules})

    print(f"\n{bold('Generated approved.yml')}: {len(rules)} rules")
    if preserved:
        print(f"  {cyan(str(preserved))} preserved from existing")
    if new_rules:
        print(f"  {yellow(str(new_rules))} new (UNKNOWN — needs manual review)")
    print(f"\n  Run {dim('tfplan.py status')} to see the dashboard.")


# ── Report (multi-command) ────────────────────────────────────────────────

def cmd_report(plan, commands, save_dir=None, old_plan_path=None,
               pending_only=False, verbose=False, show_all=False,
               output_json=False, output_file=None, output_json_file=None,
               generate_approved=False, plan_dir=".",
               **kwargs):
    """Run multiple commands in one invocation. Prints each with a header,
    optionally saves each section to its own file in save_dir."""

    def make_runner(cmd_name):
        runners = {
            "summary":   lambda: cmd_summary(plan, **kwargs),
            "modules":   lambda: cmd_modules(plan, **kwargs),
            "resources": lambda: cmd_resources(plan, **kwargs),
            "imports":   lambda: cmd_imports(plan, show_all=show_all, **kwargs),
            "details":   lambda: cmd_details(plan, verbose=verbose, **kwargs),
            "drift":     lambda: cmd_drift(plan, **kwargs),
            "moved":     lambda: cmd_moved(plan, **kwargs),
            "updates":   lambda: cmd_updates(plan, output_json=output_json,
                                             pending_only=pending_only,
                                             output_file=output_file,
                                             output_json_file=output_json_file,
                                             **kwargs),
            "issues":    lambda: cmd_issues(plan, pending_only=pending_only, **kwargs),
            "diff":      lambda: cmd_diff(plan, old_plan_path=old_plan_path, **kwargs),
            "status":    lambda: cmd_status(plan, **kwargs),
        }
        return runners.get(cmd_name)

    if save_dir:
        Path(save_dir).mkdir(parents=True, exist_ok=True)

    for i, raw_cmd in enumerate(commands):
        cmd_name = ALIASES.get(raw_cmd, raw_cmd)
        runner = make_runner(cmd_name)
        if runner is None:
            print(f"Unknown report command: {raw_cmd}", file=sys.stderr)
            continue

        print(f"=== {cmd_name.title()} ===")

        if save_dir:
            save_path = Path(save_dir) / f"plan-{cmd_name}-out.txt"
            buf = io.StringIO()
            old_stdout = sys.stdout
            sys.stdout = _Tee(old_stdout, buf)
            try:
                runner()
            finally:
                sys.stdout = old_stdout
            save_path.write_text(buf.getvalue())
        else:
            runner()

        print()

    # After all report commands, optionally generate/update approved.yml
    if generate_approved:
        cmd_generate_approved(plan, plan_dir=plan_dir, **kwargs)


class _Tee:
    """Write to two streams simultaneously (stdout + StringIO buffer)."""
    __slots__ = ("_a", "_b")

    def __init__(self, a, b):
        self._a = a
        self._b = b

    def write(self, data):
        self._a.write(data)
        self._b.write(data)

    def flush(self):
        self._a.flush()
        self._b.flush()

    def isatty(self):
        return self._a.isatty()

    def fileno(self):
        return self._a.fileno()


# ── argparse setup ────────────────────────────────────────────────────────

ALIASES = {
    "s": "summary", "m": "modules", "r": "resources", "i": "imports",
    "d": "details", "u": "updates", "x": "issues", "df": "diff",
    "dr": "drift", "mv": "moved", "st": "status", "ap": "approve",
    "ga": "generate-approved",
}

def build_parser():
    parser = argparse.ArgumentParser(
        description="Terraform Plan Analyzer",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("command", help="Command to run (or alias)")
    parser.add_argument("plan_file", nargs="?", default="tfplan.json",
                        help="Path to tfplan.json (default: ./tfplan.json)")
    parser.add_argument("old_plan_file", nargs="?", default=None,
                        help="Previous plan file (for diff command)")

    # Global filters
    parser.add_argument("-f", "--filter", dest="filter_pattern",
                        help="Filter by resource address (regex)")
    parser.add_argument("-m", "--module", dest="module_filter",
                        help="Filter by module path (substring)")
    parser.add_argument("-a", "--action", dest="action_filter",
                        help="Filter by action (create/update/delete/replace)")
    parser.add_argument("-n", "--limit", type=int,
                        help="Limit output to N resources")

    # Command-specific flags
    parser.add_argument("--json", dest="output_json", action="store_true",
                        help="JSON output (updates)")
    parser.add_argument("--pending", dest="pending_only", action="store_true",
                        help="Show only unapproved changes")
    parser.add_argument("--all", dest="show_all", action="store_true",
                        help="Show all entries including no-ops")
    parser.add_argument("--verbose", action="store_true",
                        help="Show all fields including noise")
    parser.add_argument("--no-color", dest="no_color", action="store_true",
                        help="Disable ANSI colors")
    parser.add_argument("--output", dest="output_file",
                        help="Write report to file (updates)")
    parser.add_argument("--output-json", dest="output_json_file",
                        help="Write JSON report to file (updates)")
    parser.add_argument("--save-dir", dest="save_dir",
                        help="Save each report section to <save-dir>/plan-<cmd>-out.txt")
    parser.add_argument("--generate-approved", dest="generate_approved",
                        action="store_true",
                        help="Generate/update approved.yml from plan data")

    # Approve-specific
    parser.add_argument("--reason", dest="reason_pattern",
                        help="Reason pattern for approve command")
    parser.add_argument("--address", dest="address_pattern",
                        help="Address pattern for approve command")
    parser.add_argument("--status", dest="approve_status", default="ACCEPT",
                        help="Status for approve (ACCEPT/FIX/SUPPRESS/SKIP)")
    parser.add_argument("--note", dest="approve_note", default="",
                        help="Note for approve entry")

    return parser


def main():
    parser = build_parser()

    # Handle bare -h / --help / no args
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        sys.exit(0)

    args = parser.parse_args()

    # Resolve command alias
    cmd = ALIASES.get(args.command, args.command)

    # Init color
    _init_color(force_no_color=args.no_color)

    # Commands that need a plan file
    commands_needing_plan = {
        "summary", "modules", "resources", "imports", "details",
        "drift", "moved", "updates", "issues", "diff", "status", "approve",
        "report", "generate-approved",
    }

    if cmd not in commands_needing_plan:
        print(f"Unknown command: {cmd}")
        all_cmds = sorted(commands_needing_plan)
        alias_str = ", ".join(f"{a}={v}" for a, v in sorted(ALIASES.items()))
        print(f"Available: {', '.join(all_cmds)}")
        print(f"Aliases: {alias_str}")
        sys.exit(1)

    filter_kwargs = {
        "filter_pattern": args.filter_pattern,
        "module_filter": args.module_filter,
        "action_filter": args.action_filter,
        "limit": args.limit,
    }

    # Report command: run multiple commands in one invocation
    # argparse sees: command=report, plan_file=<comma-list>, old_plan_file=<actual plan>
    if cmd == "report":
        report_cmds_str = args.plan_file
        actual_plan = args.old_plan_file or "tfplan.json"

        if Path(report_cmds_str).exists() and "," not in report_cmds_str:
            print("Usage: tfplan.py report <cmd1,cmd2,...> [plan.json]")
            print("Example: tfplan.py report summary,issues,diff,status tfplan.json")
            sys.exit(1)

        if not Path(actual_plan).exists():
            print(f"Error: {actual_plan} not found.")
            print("Run: tf-2-claude plan")
            sys.exit(1)

        plan = load_plan(actual_plan)
        report_cmds = [c.strip() for c in report_cmds_str.split(",") if c.strip()]

        cmd_report(plan, report_cmds, save_dir=args.save_dir,
                   old_plan_path=None,  # diff auto-discovers prev file
                   pending_only=args.pending_only,
                   verbose=args.verbose,
                   show_all=args.show_all,
                   output_json=args.output_json,
                   output_file=args.output_file,
                   output_json_file=args.output_json_file,
                   generate_approved=args.generate_approved,
                   plan_dir=str(Path(actual_plan).parent),
                   **filter_kwargs)
        return

    # Standard single-command path
    if not Path(args.plan_file).exists():
        print(f"Error: {args.plan_file} not found.")
        print("Run: tf-2-claude plan")
        sys.exit(1)

    plan = load_plan(args.plan_file)

    dispatch = {
        "summary": lambda: cmd_summary(plan, **filter_kwargs),
        "modules": lambda: cmd_modules(plan, **filter_kwargs),
        "resources": lambda: cmd_resources(plan, **filter_kwargs),
        "imports": lambda: cmd_imports(plan, show_all=args.show_all, **filter_kwargs),
        "details": lambda: cmd_details(plan, verbose=args.verbose, **filter_kwargs),
        "drift": lambda: cmd_drift(plan, **filter_kwargs),
        "moved": lambda: cmd_moved(plan, **filter_kwargs),
        "updates": lambda: cmd_updates(plan, output_json=args.output_json,
                                        pending_only=args.pending_only,
                                        output_file=args.output_file,
                                        output_json_file=args.output_json_file,
                                        **filter_kwargs),
        "issues": lambda: cmd_issues(plan, pending_only=args.pending_only, **filter_kwargs),
        "diff": lambda: cmd_diff(plan, old_plan_path=args.old_plan_file, **filter_kwargs),
        "status": lambda: cmd_status(plan, **filter_kwargs),
        "approve": lambda: cmd_approve(plan, reason_pattern=args.reason_pattern,
                                        address_pattern=args.address_pattern,
                                        approve_status=args.approve_status,
                                        approve_note=args.approve_note,
                                        **filter_kwargs),
        "generate-approved": lambda: cmd_generate_approved(plan,
                                        plan_dir=str(Path(args.plan_file).parent),
                                        **filter_kwargs),
    }

    dispatch[cmd]()


if __name__ == "__main__":
    main()
