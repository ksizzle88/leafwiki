---
name: terraform-development
description: >
  Use this skill when working in a Terraform environment: analyzing plans,
  resolving drift, writing import or moved blocks, fixing plan issues,
  performing state migrations, or iterating on terraform plan/apply cycles.
  Triggers on: terraform plan, terraform apply, tfplan.json, import blocks,
  moved blocks, resource drift, state migration, "what's changing",
  "fix the plan", "analyze the plan". Uses user-exec-bridge for authenticated
  CLI commands.
---

# Terraform Development

Interactive plan-analyze-fix loop for Terraform environments. The agent
prepares work; the user executes authenticated commands via `tf-2-claude`.

See `~/.claude/skills/user-exec-bridge/SKILL.md` for the wait/detect pattern.

## The Loop

```
Plan --> Analyze --> Identify Issues --> Fix --> Re-plan
  ^                                               |
  +-----------------------------------------------+
```

### 1. Plan

Tell the user the command. **Never run terraform or tf-2-claude directly.**

```
Please run:  tf-2-claude plan
```

Wait for output:
```bash
since=$(date +%s)
wait-for-output /path/to/env/plan-summary-out.txt --since "$since" --timeout 600
```

Read `plan-summary-out.txt`, then drill down with analysis scripts.
See `./reference/script-usage.md` for all commands and output files.

### 2. Analyze

Start broad, drill into problems:

```bash
TFPLAN=~/.claude/skills/terraform-development/scripts/tfplan.py
python3 $TFPLAN summary                  # module table + action counts (compact)
python3 $TFPLAN issues                   # deletes, replaces, problems only
python3 $TFPLAN modules --module NAME    # drill into one module
python3 $TFPLAN resources --action delete # compact list filtered by action
python3 $TFPLAN updates                  # classify update reasons
python3 $TFPLAN details --filter PAT     # before/after diffs (noise filtered)
python3 $TFPLAN diff                     # compare to previous plan
```

All commands support `--filter`, `--module`, `--action`, `--limit`.
See `./reference/script-usage.md` for full details.

### 3. Identify Issues

Use `issues` command first -- it surfaces problems automatically. Then classify:

| Situation | Fix |
|-----------|-----|
| Exists in Snowflake, not in state | Write `import` block |
| In state under wrong address | Write `moved` block |
| Unexpected update (drift) | Set explicit value or `lifecycle.ignore_changes` |
| Unexpected delete | Investigate -- likely needs import instead |
| Unexpected replace | Check for force-new attributes |
| In state, should be unmanaged | `terraform state rm` (confirm with user) |

For updates during state migrations, classify the change type before deciding
on a resolution. See `./reference/migration-change-types.md` for the full
catalog of change types, decision framework, and resolution patterns:

| Change Type | Example | Typical Resolution |
|-------------|---------|-------------------|
| Metadata convergence | `comment: "" -> "..."` | ACCEPT or FIX |
| Privilege materialization | `privileges: [] -> ["USAGE"]` | ACCEPT (always) |
| Computed attribute refresh | `show_output: (known after apply)` | ACCEPT (always) |
| Policy recomputation | `policy: {...} -> (known after apply)` | ACCEPT |
| New privilege addition | `privileges: +REFERENCES` | ACCEPT or FIX |
| Module default vs existing | `setting: "old" -> "new"` | FIX (config/variable) |
| Module missing config | `attr: "value" -> null` | FIX (add variable) |
| Certificate normalization | `cert: "\r\n" -> "\n"` | ACCEPT |

See `./reference/migration-patterns.md` for import/moved syntax and ID formats.

### 4. Fix

Edit `.tf` files to resolve issues. Common fixes:

- Add `import {}` blocks for existing resources
- Add `moved {}` blocks for address changes
- Set explicit attribute values to match imported state
- Add `lifecycle { ignore_changes = [...] }` for phantom drift

### 5. Re-plan

Ask the user to re-run `tf-2-claude plan`. The script automatically:
- Saves the previous plan as `tfplan.prev.json`
- Runs the new plan with summary + issues
- Shows a diff comparing old vs new plan (what got fixed, what's new)

Repeat until `issues` reports "No issues found. Plan looks clean."

## Rules

- **NEVER** run `tf-2-claude` or `terraform` via Bash
- **ALWAYS** use `wait-for-output` with `--since` after presenting a command
- **NEVER** read `tfplan.json` directly -- use `tfplan.py` scripts
- For `plan`, wait for `plan-summary-out.txt` (last file written)

## Persistent Memory

This skill maintains memory at `./memory/`. Use it to track:
- Recurring drift patterns for this environment
- Import ID formats discovered during sessions
- Module-specific quirks and workarounds

## Reference

- `./reference/script-usage.md` -- tf-2-claude CLI + tfplan.py commands
- `./reference/migration-patterns.md` -- Import/moved syntax, Snowflake IDs
- `./reference/migration-change-types.md` -- Plan diff classification, decision framework, resolution patterns
- `./reference/snowflake-import-ids.md` -- Snowflake resource import ID formats
- `./reference/terraform-style-guide.md` -- HCL conventions (HashiCorp official)
- `./reference/hashicorp-official/` -- Full HashiCorp agent skills repo
