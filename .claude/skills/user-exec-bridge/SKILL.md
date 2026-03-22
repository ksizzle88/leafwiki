---
name: user-exec-bridge
description: >
  Shared pattern for skills where the agent prepares work but the user must
  execute commands in their authenticated terminal. Provides the wait-for-output
  helper and the present-command/wait/read workflow. Not invoked directly —
  referenced by tf-plan-analyzer, snowflake-query, and similar skills.
  Use this whenever another skill needs the user to run a CLI command and
  you need to detect when the output is ready.
user_invocable: false
---

# User-Exec Bridge

Some commands require credentials or interactive auth that agents don't have —
Snowflake SSO, AWS SSO, Terraform cloud backends, etc. This skill documents the
standard pattern for handing execution to the user and automatically detecting
when results are ready.

## The Pattern

1. **Prepare** — Agent does its work (writes SQL, generates config, etc.)
2. **Present** — Agent tells the user the exact command to run
3. **Wait** — Agent runs `wait-for-output` to block until the output file appears
4. **Read** — Agent reads the output file and continues

## wait-for-output

Location: `/usr/local/bin/wait-for-output` (baked into Claudio base image, on PATH)

### Usage

```bash
# Capture timestamp BEFORE telling the user to run the command
since=$(date +%s)

# ... tell the user the command ...

# Block until output file appears (run in background if needed)
wait-for-output /path/to/expected-output.txt --since "$since" --timeout 300
```

### Parameters

| Flag | Default | Description |
|------|---------|-------------|
| `<out-file>` | (required) | Full path to the output file to watch |
| `--timeout <seconds>` | 300 | Max seconds to wait. Use 600 for slow ops like `terraform plan` |
| `--since <epoch>` | 0 | Only succeed if file mtime is after this timestamp |

### Exit behavior

- Prints `ready` and exits 0 when the file is detected
- Prints `timeout` and exits 1 if the max wait is exceeded

### Why --since matters

Without `--since`, a stale output file from a previous run would immediately
satisfy the check. Always capture `$(date +%s)` before presenting the command
to the user, then pass it as `--since`.

## Presenting Commands

When telling the user what to run, include:
1. The exact command (copy-pasteable, in a code block)
2. The working directory if it matters
3. Any required flags (connection, profile, target, etc.)

Keep it brief — one code block with the command, not a paragraph of explanation.

## Handling Timeout

If `wait-for-output` returns `timeout`:
- Tell the user the output wasn't detected
- Ask if they ran the command or hit an error
- Don't retry automatically — the user may need to re-authenticate

## For Plan Commands

Some CLI wrappers write multiple output files sequentially. Wait for the
**last file written**, not the first. For example, `tf-2-claude plan` writes
`plan-out.txt` first and `plan-summary-out.txt` last — wait for the summary.
