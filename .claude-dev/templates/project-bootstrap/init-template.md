# {{PROJECT_NAME}} — Initialization Instructions

You are bootstrapping a new session for the **{{PROJECT_NAME}}** project. Follow these steps in order.

## Step 1: Read Project Context

Read the following files to understand the project:

- `CLAUDE.md` — project instructions, layout, conventions
- `{{DESIGN_DOC}}` — design document / architecture overview

<!-- Customize: list any additional context files agents should read on init -->

## Step 2: Create Agent Team

Create a team called `{{TEAM_NAME}}` with the agents listed below. Each agent is responsible for one section of the codebase.

| Agent Name | Type | Codebase Section |
|------------|------|------------------|
| `{{AGENT_1_NAME}}` | general | `{{AGENT_1_PATHS}}` |
| `{{AGENT_2_NAME}}` | general | `{{AGENT_2_PATHS}}` |
| `{{AGENT_3_NAME}}` | general | `{{AGENT_3_PATHS}}` |
| `{{AGENT_4_NAME}}` | general | `{{AGENT_4_PATHS}}` |

<!--
  Customize:
  - Add or remove rows to match your project's natural boundaries
  - 3-5 agents is the sweet spot — one per logical section
  - Give agents short, memorable names related to their domain
  - Paths can be directories or specific files
-->

For each agent, dispatch it with instructions to:
1. Read every file in its assigned section
2. Build understanding of patterns, interfaces, and current state
3. Write what it learns to project memory (see Step 3)

## Step 3: Set Up Project Memory

Memory location: `.claude/agent-memory/` (symlinked from the auto-memory path).

Each agent writes memory to a subfolder matching its domain. The memory uses a **two-layer index** system:

```
.claude/agent-memory/
├── MEMORY.md              # Top-level index (<=100 lines)
├── {{SECTION_1}}/
│   ├── index.md           # Section index (<=100 lines)
│   └── *.md               # Detailed docs
├── {{SECTION_2}}/
│   ├── index.md
│   └── *.md
├── {{SECTION_3}}/
│   ├── index.md
│   └── *.md
└── {{SECTION_4}}/
    ├── index.md
    └── *.md
```

<!-- Customize: Replace section names with your project's domains -->

### Memory Rules

- **MEMORY.md**: Top-level index only. One line per folder + brief description. Target <=100 lines.
- **index.md** (per folder): Lists detail files with one-line descriptions. Target <=100 lines.
- **Detail files**: Actual documentation. One topic per file. No line limit.
- **Update, don't duplicate**: Check for existing files before writing new ones.
- **Keep indexes scannable**: No paragraphs — just table rows with file names and one-line descriptions.

### MEMORY.md Format

```markdown
# {{PROJECT_NAME}} — Agent Memory Index

| Folder | Description |
|--------|-------------|
| `{{SECTION_1}}/` | {{SECTION_1_DESC}} |
| `{{SECTION_2}}/` | {{SECTION_2_DESC}} |
| `{{SECTION_3}}/` | {{SECTION_3_DESC}} |
| `{{SECTION_4}}/` | {{SECTION_4_DESC}} |
```

### index.md Format

```markdown
# {{SECTION_NAME}} — Index

| File | Description |
|------|-------------|
| `some-topic.md` | One-line description of what this file documents |
| `another-topic.md` | One-line description |
```

## Step 4: Report Back

Once all agents have finished reading their sections and writing memory, summarize what each agent found and confirm the team is ready for work.

---

## Placeholder Reference

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{{PROJECT_NAME}}` | Short project identifier | `dms-dashboard` |
| `{{TEAM_NAME}}` | Agent team name | `dms-dashboard` |
| `{{DESIGN_DOC}}` | Path to design/architecture doc | `DESIGN.md` |
| `{{AGENT_N_NAME}}` | Agent name (short, memorable) | `provvy`, `routery` |
| `{{AGENT_N_PATHS}}` | Paths the agent owns | `backend/app/providers/` |
| `{{SECTION_N}}` | Memory subfolder name | `providers`, `routers` |
| `{{SECTION_N_DESC}}` | One-line description for index | `Data provider implementations` |
