Research phase for GitHub Issue #55 (EPIC: Dev Toolkit) and all its subtasks (#56-#60).

This is a large epic. Rather than researching each subtask in isolation, research them together — they inform each other. Create one team and dispatch researchers across all related topics.

## Scope

- **#55** — EPIC: Dev Toolkit — Local-First IDE for Agent Development & Operations
- **#56** — Core Framework — Server, Plugin Architecture & Form Factor Decision
- **#57** — Markdown Browser & Editor — Agent Memory, Docs, and Notes
- **#58** — jtbl 2.0 — JSON Exploration & Table Tool
- **#59** — Agent Permissions Gateway — Host-Side Artifact Runtime
- **#60** — Agent Builder — dbt-like Tool for Agent Definitions

Use `gh issue view <number>` to read the full details of each issue.

## Instructions

1. Create a single team for this research effort.
2. Dispatch 5 researchers at a time, rotating through topics until you've sent out 25-30 total research agents covering all aspects of the epic and its subtasks.
3. Research topics should span: form factor evaluation (web vs extension vs TUI vs hybrid), framework/stack options, plugin architecture patterns, existing open-source tools in this space, security models for agent permissions, markdown rendering approaches, JSON table tooling, agent definition DSLs, hot-reload patterns, and anything else relevant.
4. Each researcher should write their findings to a file under `.taskmaster/research/task-55/` with a descriptive filename (e.g., `form-factor-evaluation.md`, `plugin-architecture-patterns.md`).
5. This is research only — no implementation, no plans. Just compile thorough reports.