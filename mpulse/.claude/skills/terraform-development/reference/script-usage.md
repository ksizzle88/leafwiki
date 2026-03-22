# Script Usage Reference

Two scripts power the agent-user interaction: `tf-2-claude` (user-facing CLI)
and `tfplan.py` (agent-facing analysis).

## tf-2-claude CLI

Location: `~/.claude/skills/terraform-development/scripts/tf-2-claude`

The **user** runs these commands. Agents must NEVER run them directly.

### Commands

```
tf-2-claude plan                     # plan + tfplan.json + auto-summary + issues
tf-2-claude p                        # alias for plan (default: -parallelism=40)
tf-2-claude p -t module.foo          # plan with -target (repeatable)
tf-2-claude p -refresh=false         # skip state refresh (fast iteration)
tf-2-claude p -parallelism=60        # override parallelism (default: 40)
tf-2-claude plan --no-analyze        # plan without auto-analysis
tf-2-claude init [-upgrade]          # terraform init
tf-2-claude apply                    # apply tfplan.out
tf-2-claude state-list               # terraform state list
tf-2-claude state-list --filter PAT  # state list with grep filter
tf-2-claude state-show <address>     # terraform state show
tf-2-claude state-rm <addr> [addr..] # terraform state rm (multiple addresses)
tf-2-claude validate                 # terraform validate
tf-2-claude output [name]            # terraform output
tf-2-claude analyze <cmd> [opts]     # run tfplan.py analysis
tf-2-claude clean [--cache]          # remove plan artifacts (--cache includes cache files)
```

### Shortcuts (pass through to analyze)

```
tf-2-claude s                        # summary
tf-2-claude m                        # modules
tf-2-claude r                        # resources
tf-2-claude i                        # imports
tf-2-claude d -f PATTERN             # details with filter
tf-2-claude u --pending              # unresolved updates only
tf-2-claude x                        # issues
tf-2-claude df                       # diff vs previous
tf-2-claude dr                       # drift
tf-2-claude st                       # migration status dashboard
```

All commands support `--dry-run`. Output goes to `*-out.txt` files.

### Output Files

| Command | Wait for this file |
|---------|-------------------|
| `plan` | `plan-report-out.txt` (combined output); also `plan-summary-out.txt`, `plan-issues-out.txt`, etc. |
| `init` | `init-out.txt` |
| `apply` | `apply-out.txt` |
| `state-list` | `state-list-out.txt` |
| `state-show` | `state-show-out.txt` |
| `state-rm` | `state-rm-out.txt` |
| `validate` | `validate-out.txt` |
| `output` | `output-out.txt` |
| `analyze <cmd>` | `analyze-<cmd>-out.txt` |

Plan runs a single `tfplan.py report` invocation that produces:
`plan-report-out.txt` (combined), plus individual `plan-summary-out.txt`,
`plan-issues-out.txt`, and (on re-plan) `plan-diff-out.txt` + `tfplan.prev.json`.
If `approved.yml` exists, also produces `plan-status-out.txt`.

### Plan Diff (Automatic)

When you re-plan, `tf-2-claude plan` automatically:
1. Copies current `tfplan.json` to `tfplan.prev.json`
2. Runs the new plan
3. Runs `tfplan.py diff` to show what changed between plans
4. If `approved.yml` exists, shows pending status

### Wait Pattern

After telling the user to run a command, use the user-exec-bridge:

```bash
since=$(date +%s)
# Tell the user the command, then:
wait-for-output /path/to/env/plan-summary-out.txt --since "$since" --timeout 600
```

Timeouts: 600s for plan (slow), 300s for everything else.

---

## tfplan.py Analysis Tool

Location: `~/.claude/skills/terraform-development/scripts/tfplan.py`

Run via Bash to get compact, structured output. **Never read tfplan.json
directly** -- it can be millions of tokens.

### Commands

```bash
TFPLAN=~/.claude/skills/terraform-development/scripts/tfplan.py

python3 $TFPLAN summary   [path]                 # module table + action counts
python3 $TFPLAN modules   [path]                 # changes grouped by module
python3 $TFPLAN resources [path]                 # compact resource list with actions
python3 $TFPLAN imports   [path]                 # import IDs (skips no-ops)
python3 $TFPLAN imports   [path] --all           # all imports including no-ops
python3 $TFPLAN details   [path] -f PAT          # before/after diffs
python3 $TFPLAN details   [path] --verbose       # include noise fields
python3 $TFPLAN drift     [path]                 # drift grouped by reason
python3 $TFPLAN moved     [path]                 # moved block resources
python3 $TFPLAN updates   [path]                 # update reasons (classified)
python3 $TFPLAN updates   [path] --pending       # unresolved updates only
python3 $TFPLAN updates   [path] --json          # JSON output for piping
python3 $TFPLAN updates   [path] --output F.txt  # write report to file
python3 $TFPLAN issues    [path]                 # deletes, replaces, problems
python3 $TFPLAN issues    [path] --pending       # exclude approved changes
python3 $TFPLAN diff      [path] [old.json]      # compare two plans
python3 $TFPLAN status    [path]                 # approved vs pending dashboard
python3 $TFPLAN approve   [path] --reason PAT --status ACCEPT --note "reason"
python3 $TFPLAN report    cmd1,cmd2,... [path]     # multi-command, single invocation
python3 $TFPLAN report    cmd1,cmd2 [path] --save-dir .  # also write per-cmd files
```

Default path is `./tfplan.json`.

### Command Aliases

| Alias | Command |
|-------|---------|
| `s` | summary |
| `m` | modules |
| `r` | resources |
| `i` | imports |
| `d` | details |
| `u` | updates |
| `x` | issues |
| `df` | diff |
| `dr` | drift |
| `mv` | moved |
| `st` | status |
| `ap` | approve |

### Global Filters

```bash
-f, --filter PATTERN    # regex match on resource address
-m, --module MODULE     # substring match on module path
-a, --action ACTION     # filter by action type (create/update/delete/replace)
-n, --limit N           # limit to first N resources
--json                  # JSON output (updates command)
--no-color              # disable ANSI colors (auto-detected for pipes)
--pending               # show only unapproved changes (updates, issues)
--all                   # include no-ops (imports)
--verbose               # show all fields including noise (details)
```

### Approved Changes Workflow

Track reviewed plan changes with `approved.yml` (lives alongside tfplan.json):

```yaml
# approved.yml
rules:
  - reason: "default_tags added"
    status: ACCEPT
    note: "Intentional provider tags"
  - reason: "privilege materialization"
    status: ACCEPT
    note: "Expected on imported grants"
  - address: "module.snowdrift"
    reason: "show_output refresh"
    status: SKIP
    note: "Harmless computed attribute"
```

**Statuses**: ACCEPT (apply it), FIX (config change pending), SUPPRESS
(ignore_changes), SKIP (harmless, ignore)

**Workflow**:
1. `tfplan.py status` -- see what's approved vs pending
2. Review a category of changes
3. `tfplan.py approve --reason "pattern" --status ACCEPT --note "reason"`
4. `tfplan.py updates --pending` -- verify category is resolved
5. Repeat until `status` shows 0 pending

### Caching

`tfplan.py` caches parsed plan data to `.tfplan.cache.json` (alongside the
plan file). Cache is keyed by file mtime + size and auto-invalidates when
the source changes. Provides ~3x speedup on repeated runs.

Use `tf-2-claude clean --cache` to clear cache files.

### Recommended Analysis Flow

1. **Start with `summary` (s)** -- module table shows where changes concentrate
2. **Check `issues` (x)** -- surfaces deletes, replaces, import+updates
3. **Review `status` (st)** -- approved vs pending dashboard
4. **Drill with `modules -m NAME`** -- see a specific module's changes
5. **Classify with `updates` (u)** -- understand why updates happen
6. **Investigate with `details -f PAT` (d)** -- inspect specific resources
7. **After fixes, use `diff` (df)** -- compare new plan to previous

### Output Details

#### summary (compact)
Module table shows counts per module (reads excluded from table). Compact
action count summary below. If `approved.yml` exists, shows pending count.

#### imports (compact by default)
Skips no-op imports (most imports are clean). Use `--all` to see everything.
One-line format with import ID inline instead of multi-line blocks.

#### drift (grouped by reason)
Groups resources by their drift reason pattern. Shows the representative
diff once, then lists all affected resources. 90 resources with the same
tags_all change? One diff block + a list of 90 addresses.

#### details (noise filtering)
Hides `show_output`, `describe_output`, `parameters`, `fully_qualified_name`
fields. Use `--verbose` to show everything.
