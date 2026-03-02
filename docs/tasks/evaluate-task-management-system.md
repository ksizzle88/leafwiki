# Evaluate Task Management System for Claudio

**Status**: Pending
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

## Next Steps

1. Install Beads in a test container and try it for a real task
2. Test the `bd ready` / `bd create` workflow with Claude Code
3. If satisfactory, add to `Dockerfile.base` and document in CLAUDE.md
4. Consider GSD as complementary execution framework
