# mpulse Container Rebuild Steps & Known Issues

Tracking issues encountered when rebuilding the mpulse devcontainer and their resolutions.

## Current Issues

### 1. Auth lost on rebuild
**Symptom:** Claude asks to log in again after container rebuild.
**Cause:** init-claudio creates a symlink for `.credentials.json` but Claude Code overwrites it with a real file on first run. On rebuild, the real file is gone (was in the ephemeral container layer, not the volume).
**Workaround:** Run `claude login` after each rebuild. The long-lived token in `~/.claudio-shared/config/.env` works for `claude -p` (CLI headless) but not for interactive sessions.
**Proper fix:** TBD — need to either mount `~/.claude/` as a full volume or find a way to prevent Claude from overwriting symlinks.

### 2. Memory/sessions not persisted
**Symptom:** Previous session memories and project memory (`~/.claude/projects/-workspace-*/memory/`) are missing after rebuild.
**Cause:** Same symlink-overwrite problem. `~/.claude/projects/` becomes a real directory instead of symlink to `~/.claudio-sessions/projects/`. New session data goes to the ephemeral container layer.
**Workaround:** After rebuild, manually merge: `cp -a ~/.claude/projects/. ~/.claudio-sessions/projects/` then re-symlink.
**Proper fix:** TBD — same root cause as #1.

### 3. Snowflake SSO callback not reaching container
**Symptom:** Browser opens, Microsoft SSO completes, but redirect to `localhost:3037` returns `ERR_EMPTY_RESPONSE`.
**Cause:** Port 3037 is forwarded (compose `ports: ["3037:3037"]`) and the browser connects (no connection refused), but `snow`'s listener inside the container gets an empty response. Possibly VS Code's port forwarding proxy is interfering with Docker's port forward.
**Attempted fixes:**
- `SF_AUTH_SOCKET_PORT=3037` + `SNOWFLAKE_AUTH_SOCKET_REUSE_PORT=true` + `SNOWFLAKE_AUTH_SOCKET_MSG_DONTWAIT=true` in compose env
- `ports: ["3037:3037"]` in compose
- `forwardPorts: [3037]` + `portsAttributes` with `onAutoForward: silent` in devcontainer.json
**Status:** NOT FIXED. Browser reaches the port but snow doesn't receive the callback. Workaround: `curl` the redirect URL manually from inside the container.

### 4. `snow` binary permission issue
**Symptom:** `snow` requires sudo to run.
**Cause:** `uv tool install` puts the binary under `/root/.local/share/uv/tools/` which is inaccessible to `dev` user.
**Fix:** Changed Dockerfile to `UV_TOOL_DIR=/opt/uv-tools` so it installs to a world-readable path.
**Status:** Fixed in Dockerfile, needs rebuild.

>> not an issue in latest build.

### 5. CloudFormation LSP eating 560 MB
**Symptom:** AWS Toolkit's CloudFormation language server consumes 560 MB doing nothing.
**Cause:** AWS Toolkit extension auto-starts the CFN LSP even though we don't use CloudFormation.
**Fix:** Added `"aws.cfn.lint.enabled": false` to devcontainer.json settings. Can also kill manually: `kill <pid>`.
**Status:** Config added to devcontainer.json.

>> I added this to the settings can we addit to the dev-container if it exists?
>> can we add a light weight yaml, jinja, toml, ini (with # for coomments ) 
>> syntax highlighting? 
>>```
>>
>> "aws.suppressPrompts": {
>>		"codeWhispererConnectionExpired": true
>>	},
>>	"yaml.languageserver.enabled": false,
>>	"aws.codeWhisperer.shareCodeWhispererContentWithAWS": false,
>>	"amazonQ.telemetry": false,
>>	"aws.cfn.lint.enabled": false,
>>	"aws.cloudformation.diagnostics.cfnGuard.enabled": false,
>>	"aws.cloudformation.diagnostics.cfnGuard.validateOnChange": false,
>>	"aws.cloudformation.diagnostics.cfnLint.lintOnChange": false,
>>	"aws.cloudformation.diagnostics.cfnLint.enabled": false,
>>	"aws.cloudformation.hover.enabled": false,
>>	"aws.telemetry": false,
>>	"aws.cloudformation.completion.enabled": false,
>>	"aws.samcli.manuallySelectedBuckets": [
>>
>>	] 
>>
>> ```



### 6. Snowflake connections.toml missing settings
**Symptom:** `data_ops_dev` connection entry missing `client_store_temporary_credential = true`, causing repeated SSO prompts.
**Cause:** `connections.toml` was seeded from the host (`~/.snowflake`) on first container boot. The host version didn't have the line. The `mpulse-snowflake` volume preserves whatever was copied on first run and never re-reads from the host.
**Fix:** Edit `~/.snowflake/connections.toml` inside the container — it writes directly to the `mpulse-snowflake` volume and persists across rebuilds.
**Note:** If you need to re-seed from host, delete `config.toml` from the volume: `docker run --rm -v mpulse-snowflake:/data alpine rm /data/config.toml` — then rebuild.

### 7. `snow-2-claude` broken — wrong script version
**Symptom:** `snow-2-claude` prepends workspace path to absolute paths, e.g. `/workspace/DPI_Analytics_DBT/data_ops_ingestion//tmp/claude/snowflake/...`
**Cause:** Two skills (`snowflake-query` and `sql-data-retrieval`) both have a script named `snow-2-claude`. The `sql-data-retrieval` version has broken path resolution. init-claudio's auto-discovery symlinks the last one it finds, which is the broken one.
**Fix:**
1. Rename the conflicting script: `mv ~/.claudio-shared/plugins/skills/sql-data-retrieval/scripts/snow-2-claude ~/.claudio-shared/plugins/skills/sql-data-retrieval/scripts/snow-2-claude.bak`
2. Repoint the symlink: `ln -sf ~/.claudio-shared/plugins/skills/snowflake-query/scripts/snow-2-claude ~/.claude/bin/snow-2-claude`
3. If mpulse has a local copy too: `mv ~/.claudio/claude/skills/sql-data-retrieval/scripts/snow-2-claude ~/.claudio/claude/skills/sql-data-retrieval/scripts/snow-2-claude.bak`
**Status:** Fixed manually in both containers. The `sql-data-retrieval` skill's unified entry point is `sql-2-claude` — it should never have had its own `snow-2-claude`.

## Root Cause: Symlink Overwrite Problem

Issues #1 and #2 share a root cause. Claude Code writes to `~/.claude/` paths assuming exclusive ownership. When it writes `.credentials.json` or creates `projects/`, it replaces symlinks with real files/directories.

### Possible Solutions (Not Yet Implemented)

1. **Mount `~/.claude/` as a full volume** — stop using symlinks for individual files. Mount the entire directory. Downside: can't share some parts while isolating others.

2. **Post-start fixup script** — after Claude initializes, re-establish symlinks for shared files. Would need to run after every `claude login`.

3. **Git-based sync** — accept isolation, use git to sync memory/sessions between containers via stop hook + start hook.

4. **Syncthing sidecar** — real-time file sync between container sessions. 63 MB image, 20 MB RAM. Overkill for local but needed for cloud.

5. **inotify watcher** — small script that detects when Claude overwrites a symlink and re-establishes it.

## Rebuild Checklist

After rebuilding the mpulse container:

- [ ] Run `claude login` (auth doesn't persist across rebuilds)
- [ ] Verify `snow connection list` works with fixed port
- [ ] Check `ls -la ~/.claude/` for symlinks vs real files
- [ ] If projects/ is a real dir, merge into sessions: `cp -a ~/.claude/projects/. ~/.claudio-sessions/projects/ && rm -rf ~/.claude/projects && ln -sf ~/.claudio-sessions/projects ~/.claude/projects`
- [ ] Verify memory files accessible: `ls ~/.claude/projects/-workspace-hxi-infra/memory/`
- [ ] Check CloudFormation LSP is disabled: `ps aux | grep -i cloud`


>> other issue needed to curl respones... we hace sso and it goes out to microsoft and back so IDK how to get it to pick it up... 
>> we added stuff for this to work but it didn't

