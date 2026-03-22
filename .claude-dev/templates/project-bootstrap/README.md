# Project Bootstrap Templates

Templates for setting up a new project environment with Claude Code agent teams, structured memory, and session management.

Based on a proven workflow used in the DMS Dashboard project.

## What's Included

| File | Purpose |
|------|---------|
| `setup-template.md` | Step-by-step environment setup guide (memory symlink, workflow dir, Makefile, submodule) |
| `init-template.md` | Session bootstrap instructions piped to Claude on session start (read context, create team, set up memory) |

## How to Use

1. **Copy** both templates into your project
2. **Fill in** the `{{PLACEHOLDERS}}` with your project-specific values
3. **Remove** any optional steps you don't need
4. **Follow** `setup-template.md` to set up the environment
5. **Use** `init-template.md` with `cat init.md | claude -n "session-name"` to start sessions

## All Placeholders

| Placeholder | Used In | Description |
|-------------|---------|-------------|
| `{{PROJECT_NAME}}` | Both | Short project identifier (e.g., `my-app`) |
| `{{PROJECT_ROOT}}` | Setup | Absolute path to project root (e.g., `/workspace/my-app`) |
| `{{USER}}` | Setup | OS username (e.g., `dev`, `vscode`) |
| `{{USER_DIR}}` | Setup | Personal workflow directory (e.g., `.dev`, `.claude-dev`) |
| `{{AUTMEMORY_SLUG}}` | Setup | Auto-memory path slug — run `ls ~/.claude/projects/` to find it |
| `{{TEAM_NAME}}` | Init | Agent team name (often same as `PROJECT_NAME`) |
| `{{DESIGN_DOC}}` | Init | Path to design/architecture doc (e.g., `DESIGN.md`) |
| `{{AGENT_N_NAME}}` | Init | Short agent name (e.g., `provvy`, `testy`) |
| `{{AGENT_N_PATHS}}` | Init | File paths the agent owns (e.g., `src/api/`) |
| `{{SECTION_N}}` | Init | Memory subfolder name (e.g., `api`, `frontend`) |
| `{{SECTION_N_DESC}}` | Init | One-line description for memory index |

## Quick Example

For a project called **my-api** with a FastAPI backend and React frontend:

**init.md** agents table:
```markdown
| Agent Name | Type | Codebase Section |
|------------|------|------------------|
| `apiguy` | general | `backend/routes/`, `backend/models/` |
| `fronty` | general | `frontend/src/` |
| `testy` | general | `tests/` |
```

**Memory structure:**
```
.claude/agent-memory/
├── MEMORY.md
├── api/
│   ├── index.md
│   └── routes-overview.md
├── frontend/
│   ├── index.md
│   └── component-patterns.md
└── tests/
    ├── index.md
    └── coverage-gaps.md
```

**Makefile:**
```makefile
N ?= 1
init:
	cat .dev/init.md | claude -n "my-api-$(N)"
resume:
	claude --resume
```
