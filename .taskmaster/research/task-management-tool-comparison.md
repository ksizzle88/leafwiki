# Research: Lightweight Task Management Tool Comparison

## Date: 2026-03-06

## Context

Evaluating replacements for Taskmaster (task-master-ai v0.43.0) which occupies 1.1 GB with 460 npm dependencies, mostly from 15+ unused AI provider integrations. Need: REST API, CLI, Web UI/Kanban, SQLite storage, self-hosted.

## Comparison Table

| Tool | API | CLI | Kanban | SQLite | Docker Size | RAM | Maintained | Verdict |
|------|-----|-----|--------|--------|-------------|-----|------------|---------|
| **Kanboard** | JSON-RPC ✅ | Python client ⚠️ | ✅ Swimlanes | ✅ Default | 29 MB | ~15 MB | Maintenance mode | **Top pick** |
| **Vikunja** | REST ✅ | `vja` ⚠️ | ✅ + Gantt + Table | ✅ | 35 MB | Low | Very active | **Runner up** |
| **Tududi** | REST ✅ | ❌ | ❌ (task list only) | ✅ | ~100 MB | Moderate | Active | Partial fit |
| **GitHub Projects** | GraphQL ✅ | `gh` CLI ✅ | ✅ | N/A (cloud) | N/A | N/A | Active | Good, needs internet |
| **Taskwarrior** | ❌ (wrappers) | ✅ Best | ❌ Community UIs | Flat files | Light | Light | Active | CLI-only |
| **Planka** | REST ✅ | ❌ | ✅ Beautiful | ❌ Postgres | Heavy | Moderate | Active | Too heavy |
| **Wekan** | REST ✅ | ❌ | ✅ | ❌ MongoDB | Heavy | 1 GB+ | Active | Too heavy |
| **Focalboard** | REST ✅ | ❌ | ✅ | ✅ Standalone | Moderate | Moderate | **Abandoned** | Risky |
| **Nullboard** | ❌ | ❌ | ✅ Minimal | localStorage | None | None | Minimal | Browser-only |
| **todo.txt** | ❌ | ✅ | ❌ | Text file | None | None | Stable | CLI-only |
| **Kan.bn** | Unclear | ❌ | ✅ | ❌ Postgres | Moderate | Moderate | Active | Disqualified |

## Recommendation: Kanboard

- 29 MB Docker image vs Taskmaster's 1.1 GB
- ~15 MB RAM at runtime
- Single container: NGINX + PHP 8.4 + SQLite
- Comprehensive JSON-RPC API for agent integration
- Built-in Kanban with drag-and-drop, swimlanes, WIP limits
- Zero AI bloat
- MIT license
- Python API client: `pip install kanboard`

## Runner Up: Vikunja

- 35 MB Docker image, Go binary
- REST API with OpenAPI/Swagger docs
- Multiple views: Kanban, List, Gantt, Table
- Community CLI (`vja`)
- Very actively developed
- AGPLv3 license

## Decision

Adopted two-phase approach:
1. **Phase 1**: Wrapper script for `task-master update-task` to bypass AI (direct JSON manipulation)
2. **Phase 2**: Migrate to GitHub Issues/Projects for online projects; evaluate Kanboard for local/private work

## Sources
- [Kanboard Docs](https://docs.kanboard.org/) | [GitHub](https://github.com/kanboard/kanboard) | [API](https://docs.kanboard.org/v1/api/)
- [Vikunja](https://vikunja.io/) | [GitHub](https://github.com/go-vikunja/vikunja) | [Docs](https://vikunja.io/docs/installing/)
- [Planka](https://planka.app/) | [Wekan](https://github.com/wekan/wekan)
- [Focalboard](https://github.com/mattermost-community/focalboard)
- [Taskwarrior](https://taskwarrior.org/)
- [Awesome Self-Hosted](https://awesome-selfhosted.net/tags/task-management--to-do-lists.html)
