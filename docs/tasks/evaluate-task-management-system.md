# Evaluate Task Management System for Claudio

**Status**: In Progress — Taskmaster AI selected, integration partially complete
**Priority**: Medium
**Scope**: Claudio project workflow

## Goal

Choose and integrate a persistent task management system for AI coding workflows across Claudio containers. Currently, Claude Code tasks are in-memory and lost when sessions end. We need tasks to persist across sessions and be accessible from any container.

## Context

`CLAUDE_CODE_TASK_LIST_ID=main` is now set in the base image zshrc, which gives Claude Code's native task system a stable ID. But the native system stores tasks in `~/.claude/tasks` which may not persist reliably across container rebuilds depending on volume setup.

## Top Candidates

### 1. Beads (`bd`) — Recommended

- **GitHub**: https://github.com/steveyegge/beads (~17.9k stars)
- **Storage**: `.beads/` directory in repo (Dolt versioned SQL DB)
- **Install**: `npm install -g @beads/bd` or `brew install beads`
- **Integration**: First-class Claude Code support via `.claude-plugin`

**Why it fits Claudio**:
- Git-native: `.beads/` lives in workspace bind mount, survives container rebuilds
- Hash-based IDs prevent merge collisions across multiple containers/branches
- `bd ready` / `bd create` / `bd update --claim` workflow designed for AI agents
- Memory compaction summarizes old tasks to save context windows
- No external services — fully local, works offline
- Foundation layer for Gastown (ecosystem momentum)

**Concerns**:
- Requires Dolt SQL server process (embedded in recent versions)
- ~500 issue limit per project for full-file reads

**Integration plan**:
1. Add `bd` to `Dockerfile.base` via npm
2. `.beads/` directory persists in workspace bind mount
3. Optional `bd init --quiet` in `init-claudio`

### 2. GSD (Get Shit Done)

- **GitHub**: https://github.com/glittercowboy/get-shit-done (~23.3k stars)
- **Storage**: `.planning/` directory with structured markdown files
- **Install**: `npx get-shit-done-cc@latest`

**Why it's good**:
- Solves context rot with fresh subagent contexts per task
- File-based, git-tracked — same portability as Beads
- Each task = atomic git commit
- Parallel execution via wave system

**Why it ranks lower**:
- More of a workflow framework than persistent tracker
- Best for sprint-style "given a spec, ship it" work
- Task state spread across multiple markdown files
- Full planning cycle takes 45-60 minutes per iteration

**Could complement Beads** — GSD for execution methodology, Beads for persistent state.

### 3. Taskmaster AI

- **GitHub**: https://github.com/eyaltoledano/claude-task-master (~25.7k stars)
- **Storage**: `.taskmaster/` directory (file-based, in git)
- **Install**: `claude mcp add taskmaster-ai -- npx -y task-master-ai`

**Why it's good**:
- Highest adoption / largest community
- MCP server integration — one-line install
- PRD-driven approach with auto task decomposition
- Could add to Claudio's shared MCP volume (`claudio-shared-mcp`)

**Why it ranks lower**:
- Designed primarily for Cursor-style editors, Claude Code support secondary
- Less autonomous-agent-friendly than Beads
- Requires active developer engagement

### Newer Alternatives Researched

| Tool | What | Differentiator |
|------|------|---------------|
| **Intent** (Augment Code) | Agent workspace with "living specs" | Self-maintaining documentation |
| **Kelos** | Kubernetes-native agent orchestration | GitOps workflows as YAML |
| **Shrimp Task Manager** | MCP server with chain-of-thought | Reflection and research modes |
| **Claude Forge** | oh-my-zsh for Claude Code | Plugin framework, security hooks |
| **Mission Control** | Kanban board with JSON task files | Agent-first design |
| **Zenflow** (Zencoder) | Multi-LLM verification desktop app | Models critique each other |

## Decision Criteria

1. **Git-native storage** — tasks survive container rebuilds via workspace bind mount
2. **Agent-first design** — AI agents can self-manage tasks without human steering
3. **Low operational overhead** — no external services, databases, or UIs required
4. **Ecosystem momentum** — active development, growing community
5. **Claudio compatibility** — works with volume architecture and multi-container model

## Decision

**Taskmaster AI selected** — highest community adoption, MCP-native, PRD-driven task decomposition, file-based git storage. Integrated into Claudio base image and multi-agent orchestration system.

## Integration Progress

### Completed

- [x] `Dockerfile.base` — added `task-master-ai` to Layer 8 npm install
- [x] `.claude/mcp.json` — created with Taskmaster MCP server config
- [x] `docker-compose.yml` — added port 5565 for Task Studio UI
- [x] `.devcontainer/init-claude-settings.sh` — added `agents` to overlay sync (line 43) and shared plugin sync (line 238)
- [x] `.claude/agents/coordinator.md` — coordinator agent definition
- [x] `.claude/agents/researcher.md` — researcher agent definition
- [x] `.claude/agents/implementer.md` — implementer agent definition
- [x] `.claude/agents/reviewer.md` — reviewer agent definition
- [x] `.claude/skills/coordinating-agents/` — orchestration skill with reference docs and templates
- [x] `.claude/skills/testing-container-changes/` — safe container testing workflow skill

### Remaining

- [ ] `task-master init` in `/workspace/` — initialize `.taskmaster/` directory (requires `sudo npm install -g task-master-ai` or image rebuild)
- [ ] Test in side-by-side container (`docker compose build devcontainer-test`)
- [ ] Verify: `task-master --version`, `task-master list`, Task Studio, `claude --agent coordinator`
- [ ] Commit all changes on develop branch
- [ ] Rebuild main devcontainer

### Resume Instructions

To continue from where we left off:

```bash
# Install task-master-ai (needs sudo for /usr/lib/node_modules)
sudo npm install -g task-master-ai

# Initialize Taskmaster in workspace
cd /workspace && task-master init

# Commit .taskmaster/ to git

# Test in side-by-side container
docker compose build devcontainer-test
docker compose up -d devcontainer-test
docker compose exec devcontainer-test zsh
# Inside: task-master --version && claudio verify
```
