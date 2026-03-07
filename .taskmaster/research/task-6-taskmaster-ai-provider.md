# Research: Taskmaster AI Provider Configuration (Task #6)

## Date: 2026-03-06

## Root Cause

The `claude-code` provider in Taskmaster is configured correctly but fails because:

1. **`CLAUDECODE=1` env var** — Set by running Claude Code sessions. When Taskmaster's claude-code provider shells out to `claude -p ...`, the CLI detects this and refuses to start: "Claude Code cannot be launched inside another Claude Code session." This is a [known upstream bug](https://github.com/anthropics/claude-agent-sdk-python/issues/573).

2. **No env override in config** — The `claudeCode` config schema (validated by Zod) supports: `pathToClaudeCodeExecutable`, `maxTurns`, `customSystemPrompt`, `appendSystemPrompt`, `permissionMode`, `allowedTools`, `disallowedTools`, `mcpServers`, `commandSpecific`. There is NO `env` field.

3. **Missing `permissionMode`** — Without `permissionMode: "bypassPermissions"` in the `claudeCode` config, the spawned Claude subprocess prompts for tool permissions interactively, causing another hang.

## Config State (Working)

All three model roles are correctly set to `claude-code` provider in `/workspace/.taskmaster/config.json`:
- Main: claude-code / sonnet
- Research: claude-code / sonnet
- Fallback: claude-code / haiku

## Key Files

| File | Purpose |
|------|---------|
| `/workspace/.taskmaster/config.json` | Taskmaster config, `claudeCode: {}` section |
| `/usr/local/share/npm-global/lib/node_modules/task-master-ai/dist/ai-services-unified-DNZsHZ1J.js` | Claude Code provider class |
| `/usr/local/share/npm-global/lib/node_modules/task-master-ai/dist/config-manager-DsRE1v6M.js` | Config manager with claudeCode Zod schema |
| `/usr/local/share/npm-global/lib/node_modules/task-master-ai/node_modules/ai-sdk-provider-claude-code/dist/index.js` | AI SDK provider for Claude Code |
| `/usr/local/share/npm-global/lib/node_modules/task-master-ai/node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs` | Claude Agent SDK (env inheritance at line 8592) |

## update-task vs add-task Gap

- `add-task` has manual bypass: `--title` + `--description` flags skip AI entirely
- `update-task` has NO manual bypass: `--prompt` always calls AI
- Only exception: hidden metadata-only path (not useful for title/description updates)

### add-task Manual Path (source reference)
```js
// In commands-Dj_y8V5M.js ~line 123
let t = e.title && e.description;  // true if both manual fields provided
if (t) {
  s = {title: e.title, description: e.description, details: e.details || ''};
  // NO AI CALL — writes directly
}
```

### update-task (no manual path)
```js
// In commands-Dj_y8V5M.js ~line 91
// ALWAYS requires prompt, ALWAYS calls AI service
await C(r.getTasksPath(), s, c, u, {projectRoot: r.getProjectRoot(), tag: o}, 'text', d)
```

## Resolution

Instead of fixing the upstream issue, we opted to:
1. **Phase 1**: Create a wrapper script that intercepts `update-task` and does direct JSON manipulation via jq
2. **Phase 2**: Migrate to GitHub Issues/Projects

## Related Issues
- [anthropics/claude-agent-sdk-python#573](https://github.com/anthropics/claude-agent-sdk-python/issues/573)
- [eyaltoledano/claude-task-master#1223](https://github.com/eyaltoledano/claude-task-master/issues/1223)
- [anthropics/claude-code#4744](https://github.com/anthropics/claude-code/issues/4744)
- [anthropics/claude-code#17540](https://github.com/anthropics/claude-code/issues/17540)
