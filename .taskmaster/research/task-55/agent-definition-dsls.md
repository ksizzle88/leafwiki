# Agent Definition DSLs and Config Management Approaches

**Research for Issue #60: Agent Builder — dbt-like Tool for Agent Definitions**
**Date**: 2026-03-13

---

## 1. dbt Architecture Deep Dive

### 1.1 Compilation Model

dbt follows a **discover → parse → compile → execute** pipeline:

1. **Discovery**: Scans the project directory for `.sql`, `.yml`, `.py` files based on `dbt_project.yml` paths
2. **Parsing**: Reads each file, extracts Jinja templates, YAML configs, and model references
3. **Graph Construction**: Builds a DAG by resolving `ref('model_name')` and `source('schema', 'table')` references
4. **Compilation**: Renders Jinja templates into raw SQL, resolving all variable references and macros
5. **Execution**: Runs compiled SQL against the target warehouse in topological order

### 1.2 manifest.json — The Compiled Artifact

The manifest is the single output artifact of dbt's compilation step. Top-level keys:

| Key | Purpose |
|-----|---------|
| `metadata` | Project name, dbt version, schema version, adapter type |
| `nodes` | All models, tests, seeds, snapshots, analyses — the core DAG |
| `sources` | External data sources referenced by models |
| `macros` | Reusable Jinja functions |
| `docs` | Documentation blocks |
| `exposures` | Downstream consumers (dashboards, apps) |
| `metrics` | Business metric definitions |
| `parent_map` | Node → parents (upstream dependencies) |
| `child_map` | Node → children (downstream dependents) |
| `selectors` | Named selection criteria for node subsets |
| `disabled` | Nodes excluded from the DAG |

Each node has a `unique_id` formatted as `<resource_type>.<package>.<resource_name>` (e.g., `model.my_project.dim_users`). Nodes include `path`, `original_file_path`, `config`, `compiled_sql` (after execution), `depends_on`, and `tags`.

**Key insight for Agent Builder**: The manifest is the single source of truth for "what does the project actually look like right now." It's generated fresh on every compile. It enables downstream tools (docs, lineage, CI checks) without those tools needing to parse source files themselves.

### 1.3 Config Hierarchy (Precedence, Lowest to Highest)

1. **`dbt_project.yml`** — project-wide defaults, organized by path
2. **`schema.yml` / `properties.yml`** — directory-level or model-level properties
3. **`config()` Jinja block** — in-file, per-model overrides

Merging behavior is **clobber** (most specific wins) for most fields, but **additive** for `tags` — tags from all layers are combined.

**Parallel to Claude Code**: Claude Code has a similar 3-tier hierarchy:
- `~/.claude/settings.json` (global) ≈ `dbt_project.yml`
- `.claude/settings.json` (project) ≈ `schema.yml`
- `.claude/settings.local.json` (local override) ≈ `config()` block

### 1.4 Selectors and Graph Operators

dbt's node selection DSL allows targeting subsets of the DAG:

| Syntax | Meaning |
|--------|---------|
| `model_name` | Select a single model |
| `+model_name` | Model and all ancestors (upstream) |
| `model_name+` | Model and all descendants (downstream) |
| `+model_name+` | Model, ancestors, and descendants |
| `model_name+1` | Model and first-degree descendants only |
| `@model_name` | Parents/children without the model itself |
| `tag:nightly` | All nodes with a specific tag |
| `path:models/staging` | All nodes under a path |
| `config.materialized:table` | Filter by config value |

Set operators: space = union, comma = intersection.

**Relevance for Agent Builder**: The Agent Builder could use similar operators to select subsets of the agent config graph. Example: `agent-builder validate +researcher` to validate the researcher agent and everything it depends on (its tools, hooks, MCP servers).

### 1.5 Plugin/Adapter System

dbt-core defines a `BaseAdapter` interface. Each database adapter (Snowflake, BigQuery, Postgres) implements this interface as a Python package. Since the 2023 decoupling, adapters depend on `dbt-adapters` (a stable interface package) rather than `dbt-core` directly.

**Relevance for Agent Builder**: If the Agent Builder ever needs to support different "targets" (e.g., different Claude Code versions, different LLM providers), an adapter pattern would work. However, for MVP, this is likely over-engineering. The plugin system is more relevant for output formatters (DOT, JSON, terminal).

---

## 2. Other Config-as-Code Systems Comparison

### 2.1 Terraform (HCL → Plan → Apply)

| Concept | How It Works | Agent Builder Parallel |
|---------|-------------|----------------------|
| **HCL Config** | Declarative resource definitions in `.tf` files | Agent definitions in `.md` files with frontmatter |
| **`terraform init`** | Download providers/modules, set up backend | `agent-builder init` — discover and index all definitions |
| **`terraform plan`** | Diff desired state vs current state, show changes | `agent-builder diff` — show what would change vs compiled manifest |
| **`terraform apply`** | Apply changes to reach desired state | `agent-builder compile` — generate manifest |
| **State file** | Records what resources exist and their current state | Compiled manifest (agent-manifest.json) |
| **Providers** | Plugins that know how to manage specific resource types | Adapters for different config file types (MD, JSON, YAML) |
| **Modules** | Reusable config bundles | Agent definition templates |

**Key takeaway**: Terraform's `plan → apply` workflow is powerful for "preview before change." Agent Builder should adopt this: `agent-builder compile --dry-run` shows what the manifest would look like without writing it.

### 2.2 Ansible (YAML Playbooks, Variable Precedence)

Ansible has **22 levels of variable precedence** — a cautionary tale. The Agent Builder should keep its config hierarchy to exactly 3-4 levels (global, project, local, CLI override) to avoid Ansible's complexity trap.

Ansible's **role** concept is relevant: a role bundles tasks, handlers, defaults, and files into a reusable unit. An "agent role" could bundle an agent definition, its commands, hooks, and MCP server configs into a cohesive package.

### 2.3 Nx (Monorepo Project Graph)

Nx builds a **project graph** by analyzing source code imports and `project.json` configs. Key features:

- **Affected commands**: `nx affected -t test` runs only tests for projects impacted by a code change
- **Task graph**: Separate from the project graph; represents execution dependencies
- **Interactive visualization**: Browser-based graph explorer

**Key takeaway for Agent Builder**: The "affected" concept maps well. When an agent definition changes, the Agent Builder could determine which commands, hooks, and other agents are affected. The interactive graph visualization is also directly applicable to the Dependency Graph requirement in issue #60.

### 2.4 Bazel/Buck (Hermetic Builds)

Bazel's **hermeticity** ensures builds are self-contained and reproducible. Rules are defined in Starlark (a Python dialect). Buck2's **BXL** enables introspection of the build graph for LSPs and tooling.

**Key takeaway**: While full hermeticity is overkill for agent configs, the concept of **deterministic compilation** is important. Given the same source files, `agent-builder compile` should always produce the same manifest. The graph introspection concept from BXL maps directly to the Dependency Graph feature.

---

## 3. Claude Code's Current Config System

### 3.1 File Locations and Formats

Based on actual codebase analysis and the official documentation:

#### Agent Definitions (`.claude/agents/*.md`)

YAML frontmatter with markdown body. Supported fields:

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| `name` | Yes | string | Unique identifier (lowercase, hyphens) |
| `description` | Yes | string | When Claude should delegate to this agent |
| `tools` | No | string (CSV) | Allowed tools. Inherits all if omitted |
| `disallowedTools` | No | string (CSV) | Tools to deny from inherited set |
| `model` | No | string | `sonnet`, `opus`, `haiku`, full model ID, or `inherit` |
| `permissionMode` | No | string | `default`, `acceptEdits`, `dontAsk`, `bypassPermissions`, `plan` |
| `maxTurns` | No | number | Max agentic turns |
| `skills` | No | list | Skills to preload into context |
| `mcpServers` | No | list | MCP servers (inline or by reference) |
| `hooks` | No | object | Lifecycle hooks scoped to this agent |
| `memory` | No | string | Persistent memory scope: `user`, `project`, `local` |
| `background` | No | boolean | Always run as background task |
| `isolation` | No | string | `worktree` for git worktree isolation |

The markdown body becomes the system prompt.

#### Slash Commands (`.claude/commands/*.md`)

Frontmatter fields:

| Field | Required | Description |
|-------|----------|-------------|
| `description` | No | What the command does |
| `argument-hint` | No | Hint for argument placeholder |
| `allowed-tools` | No | Tool restrictions for this command |

Body becomes the prompt template. `$ARGUMENTS` is replaced with user input.

#### Settings (`settings.json`)

Three files merged in order:
1. `~/.claude/settings.json` (global)
2. `.claude/settings.json` (project)
3. `~/.claude/settings.local.json` (local, gitignored)

Structure:
```json
{
  "permissions": { "allow": [...], "deny": [...] },
  "env": { "KEY": "value" },
  "hooks": {
    "PreToolUse": [...],
    "PostToolUse": [...],
    "Stop": [...],
    "TeammateIdle": [...],
    "TaskCompleted": [...],
    "SubagentStart": [...],
    "SubagentStop": [...]
  },
  "statusLine": { "type": "command", "command": "..." },
  "enabledPlugins": { "plugin-name": true }
}
```

#### Hooks (`.claude/hooks/*.sh`)

Shell scripts referenced by `settings.json` hook entries. Exit codes:
- `0` = allow
- `2` = block with stderr feedback

#### CLAUDE.md

Project instructions. Loaded automatically. Multiple can exist:
- `~/.claude/CLAUDE.md` (global)
- `.claude/CLAUDE.md` (project)
- `CLAUDE.md` (project root)

### 3.2 Current Agent Definitions in This Project

This project has 5 agents forming a task pipeline:

| Agent | Model | Tools | Role |
|-------|-------|-------|------|
| `coordinator` | opus | Agent(all), TeamCreate/Delete, SendMessage, Read, Glob, Grep, Bash(limited), Write | Central orchestrator, never writes code |
| `researcher` | opus | Read, Glob, Grep, SendMessage, WebSearch, WebFetch, Bash(limited) | Read-only codebase explorer |
| `planner` | opus | Read, Glob, Grep, SendMessage, WebSearch, WebFetch, Bash(limited), Write(.taskmaster/**) | Creates implementation plans |
| `implementer` | opus | Read, Edit, Write, Bash, Glob, Grep, SendMessage, Bash(gh issue *) | Executes code changes |
| `reviewer` | opus | Read, Glob, Grep, SendMessage, Bash(limited) | Reviews and verdicts PASS/FAIL |

Key relationships:
- `coordinator` references all other agents via `tools: Agent(researcher, planner, implementer, reviewer)`
- `do-task` command orchestrates the full pipeline
- `hooks/teammate-idle.sh` and `hooks/task-completed.sh` are referenced by `settings.json`
- All agents reference `SendMessage` for team communication

### 3.3 Dependency Graph (Implicit)

The current config has **implicit** dependencies. Nothing explicitly declares them, but they exist:

```
settings.json
  ├── hooks → teammate-idle.sh
  ├── hooks → task-completed.sh
  └── permissions → controls what agents can do

coordinator.md
  ├── tools → Agent(researcher, planner, implementer, reviewer)
  ├── uses → SendMessage, TeamCreate, TeamDelete
  └── writes → .taskmaster/**

do-task.md (command)
  ├── uses → Agent(researcher, planner, implementer, reviewer)
  ├── uses → Bash(gh issue *)
  └── references → .taskmaster/plans/*, .taskmaster/tests/*

researcher.md → Bash(gh issue *), SendMessage
planner.md → SendMessage, Write(.taskmaster/**)
implementer.md → SendMessage, Bash(gh issue *)
reviewer.md → SendMessage, Bash(.taskmaster/*), Bash(git diff *)
```

---

## 4. Agent-Specific Config Patterns from Other Frameworks

### 4.1 CrewAI

CrewAI uses YAML for agent and task definitions:

```yaml
# config/agents.yaml
researcher:
  role: "{topic} Senior Data Researcher"
  goal: "Uncover cutting-edge developments in {topic}"
  backstory: "You are a seasoned researcher..."

# config/tasks.yaml
research_task:
  description: |
    Conduct thorough research on {topic}.
    Find key trends and developments.
  expected_output: "A detailed research report"
```

Key features:
- Variable substitution: `{variable_name}` resolved at runtime
- Separation of agents and tasks into different files
- `@CrewBase` decorator maps YAML to Python classes

### 4.2 Microsoft AutoGen

AutoGen defines agents programmatically (no YAML/config file approach):
- `ConversableAgent` base class
- `AssistantAgent` for LLM-powered agents
- `UserProxyAgent` for human-in-the-loop
- Roles, capabilities, tools defined as constructor parameters
- Multi-agent orchestration through message passing

AutoGen v0.4 moved to an async, event-driven architecture. The newer "Agent Framework" (combining AutoGen + Semantic Kernel) adds graph-based workflows.

### 4.3 LangChain/LangGraph

LangChain agents are primarily code-defined:
- Agent = LLM + Tools + Prompt
- LangGraph adds graph-based orchestration (nodes = functions, edges = transitions)
- LCEL (LangChain Expression Language) for declarative chain composition
- No standard YAML/config format — configuration is programmatic

---

## 5. Design Recommendations for Agent Builder

### 5.1 Compiled Manifest Schema

Drawing from dbt's manifest.json, the Agent Builder's compiled manifest should be:

```json
{
  "version": 1,
  "metadata": {
    "compiled_at": "2026-03-13T12:00:00Z",
    "project_root": "/workspace",
    "claude_code_version": "2.1.63"
  },
  "agents": {
    "coordinator": {
      "source_file": ".claude/agents/coordinator.md",
      "source_layer": "project",
      "name": "coordinator",
      "description": "Central orchestrator...",
      "model": "opus",
      "tools": ["Agent(researcher)", "Agent(planner)", "..."],
      "system_prompt": "You are a senior engineering coordinator...",
      "depends_on": ["researcher", "planner", "implementer", "reviewer"],
      "depended_by": ["do-task"]
    }
  },
  "commands": {
    "do-task": {
      "source_file": ".claude/commands/do-task.md",
      "source_layer": "project",
      "description": "Run a GitHub Issue through parallel agent teams",
      "allowed_tools": ["Agent", "Bash(gh issue *)"],
      "depends_on": ["coordinator", "researcher", "planner", "implementer", "reviewer"]
    }
  },
  "hooks": {
    "teammate-idle": {
      "source_file": ".claude/hooks/teammate-idle.sh",
      "event": "TeammateIdle",
      "referenced_by": ["settings.json"]
    }
  },
  "settings": {
    "effective": { /* merged settings from all layers */ },
    "layers": {
      "global": { /* from ~/.claude/settings.json */ },
      "project": { /* from .claude/settings.json */ },
      "local": { /* from .claude/settings.local.json */ }
    }
  },
  "mcp_servers": {},
  "parent_map": { /* node → upstream dependencies */ },
  "child_map": { /* node → downstream dependents */ },
  "validation": {
    "errors": [],
    "warnings": []
  }
}
```

### 5.2 Dependency Graph Representation

Nodes in the graph:

| Node Type | Example | Source |
|-----------|---------|--------|
| `agent` | `agent.coordinator` | `.claude/agents/coordinator.md` |
| `command` | `command.do-task` | `.claude/commands/do-task.md` |
| `hook` | `hook.teammate-idle` | `.claude/hooks/teammate-idle.sh` |
| `settings` | `settings.project` | `.claude/settings.json` |
| `mcp_server` | `mcp.github` | Referenced in settings or agent frontmatter |
| `skill` | `skill.api-conventions` | Referenced in agent frontmatter |
| `instructions` | `instructions.project` | `CLAUDE.md` files |

Edges represent:
- **references**: Agent references tools/other agents
- **configures**: Settings configure hooks/permissions
- **overrides**: Local settings override project settings

### 5.3 Validation Rules

| Rule | Type | Description |
|------|------|-------------|
| Broken agent reference | Error | Command or agent references agent that doesn't exist |
| Broken hook reference | Error | Settings reference hook script that doesn't exist |
| Non-executable hook | Warning | Hook script missing `+x` permission or shebang |
| Unused agent | Warning | Agent defined but never referenced by any command or other agent |
| Unused command | Warning | Command defined but no clear entry point |
| Conflicting settings | Warning | Same key set differently at project and local level |
| Invalid frontmatter | Error | YAML parse failure in agent/command file |
| Invalid JSON | Error | JSON parse failure in settings file |
| Missing required fields | Error | Agent missing `name` or `description` |
| Circular dependency | Error | Agent A references Agent B which references Agent A |
| Model not available | Warning | Agent specifies a model that may not be available |
| Tool not recognized | Warning | Agent lists a tool that isn't a known Claude Code tool |

### 5.4 Config Resolution Strategy

Follow dbt's pattern — **most specific wins, with clear layers**:

```
Layer 0 (lowest): Built-in defaults (Claude Code internal defaults)
Layer 1: Global user config (~/.claude/)
Layer 2: Project config (.claude/)
Layer 3: Local overrides (.claude/settings.local.json)
Layer 4 (highest): CLI flags (--agents JSON)
```

For the resolved view, track **provenance** — which layer each value came from:

```json
{
  "permissions.allow": {
    "effective_value": ["Bash(git:*)", "Bash(npm:*)"],
    "source": "project (.claude/settings.json)",
    "overrides": "global (~/.claude/settings.json)"
  }
}
```

### 5.5 CLI Interface Design

Based on dbt's CLI (compile, run, test, docs) and Terraform's (init, plan, apply):

```bash
# Discovery & Inspection (read-only, fast)
agent-builder list                        # List all definitions with source layer
agent-builder list --type agent           # Filter by type
agent-builder show <name>                 # Show single definition resolved
agent-builder resolve                     # Show merged settings with provenance
agent-builder graph                       # Output dependency graph (DOT format)
agent-builder graph --format json         # Machine-readable graph
agent-builder graph --focus coordinator   # Subgraph around one node

# Validation (read-only, may be slow)
agent-builder validate                    # Check all definitions
agent-builder validate --fix              # Auto-fix (permissions, missing dirs)
agent-builder validate +coordinator       # Validate node and dependencies (dbt-style)

# Compilation
agent-builder compile                     # Generate agent-manifest.json
agent-builder compile --dry-run           # Preview without writing
agent-builder diff                        # Diff current state vs last compiled manifest

# Scaffolding
agent-builder new agent <name>            # Create agent from template
agent-builder new command <name>          # Create command from template
agent-builder new hook <event>            # Create hook script from template

# Info
agent-builder version                     # Show version info
agent-builder doctor                      # Diagnose common issues
```

### 5.6 Scaffolding Approach

Based on the research, **Hygen-style file-based templates** are the best fit:

- Templates live in `.claude/templates/` or a built-in directory
- Each template is a directory with a `prompt.md` (for interactive questions) and output files
- Handlebars-style variable substitution
- No build step, no heavy dependencies

Example template structure:
```
cli/templates/agent-builder/
  agent/
    agent.md.ejs    # -> .claude/agents/<name>.md
  command/
    command.md.ejs  # -> .claude/commands/<name>.md
  hook/
    hook.sh.ejs     # -> .claude/hooks/<event>.sh
```

### 5.7 How Deep Should the dbt Analogy Go?

| dbt Feature | Include in Agent Builder? | Rationale |
|-------------|--------------------------|-----------|
| Compilation to manifest | **Yes** | Core value prop |
| Config layering with provenance | **Yes** | Solves "what does the agent see?" |
| Dependency graph (DAG) | **Yes** | Core requirement |
| Node selection syntax (+, tag:, path:) | **Partial** — start with name-based | Full syntax is overkill for <50 nodes |
| Test framework | **No** (MVP) | Validation covers most needs |
| Lineage tracking | **No** (MVP) | Git history covers this |
| Selectors/YAML selectors | **No** (MVP) | Too complex for initial release |
| Adapter/plugin system | **No** (MVP) | Single target (Claude Code) |
| Docs generation | **Post-MVP** | Useful but not essential |

---

## 6. Comparison Matrix

| System | Config Format | Compilation Step | DAG | Config Layers | Plugin System | CLI Pattern |
|--------|--------------|------------------|-----|---------------|---------------|-------------|
| **dbt** | SQL + YAML + Jinja | Yes (manifest.json) | Yes (ref-based) | 3 (project, yml, in-file) | Adapters (Python) | compile, run, test, docs |
| **Terraform** | HCL | Yes (plan) | Yes (implicit from refs) | 2 (root, module) | Providers (Go) | init, plan, apply |
| **Ansible** | YAML | No (interpreted) | No (sequential) | 22 levels | Roles, Collections | playbook, role |
| **Nx** | JSON + source analysis | Yes (project graph) | Yes (import-based) | 2 (workspace, project) | Plugins (JS) | affected, graph, run |
| **Bazel** | Starlark | Yes (action graph) | Yes (rule-based) | 2 (workspace, package) | Rules (Starlark) | build, test, query |
| **CrewAI** | YAML | No (runtime) | No | 1 (file) | None | Python API |
| **Claude Code** | MD + JSON | **No** (runtime) | **Implicit** | 3 (global, project, local) | Plugins | `/agents`, settings |
| **Agent Builder** (proposed) | MD + JSON (existing) | **Yes** (manifest.json) | **Explicit** | 4 (global, project, local, CLI) | Output formatters | list, show, validate, compile, graph |

---

## 7. Open Questions for the Planner

1. **MCP server management**: Should Agent Builder parse `.mcp.json` / `mcp.json` files and include MCP servers in the dependency graph? The frontmatter already supports `mcpServers` — this seems valuable.

2. **Profiles**: Should Agent Builder support switching between agent setups (e.g., "production" vs "development" agent configs)? Terraform has workspaces, dbt has targets. This could be post-MVP.

3. **Watch mode**: Should `agent-builder compile --watch` exist for the web UI's live-updating preview? The dev-toolkit plugin likely needs this.

4. **Language choice**: The CLI should be shell (bash) to match existing Claudio CLI patterns, or Node.js for JSON handling and potential web UI integration. Given the heavy JSON/YAML parsing needed, Node.js or Python would be more practical than pure bash.

5. **Where does the manifest live?**: Candidates:
   - `.claude/agent-manifest.json` (alongside source configs)
   - `.taskmaster/agent-manifest.json` (with other build artifacts)
   - `agent-builder.json` (project root)

6. **Git tracking**: Should the manifest be checked in (like `package-lock.json`) or gitignored (like `node_modules/`)? For reproducibility, checking it in is better. For simplicity, generating it fresh is easier.

---

## Sources

- [dbt Manifest JSON](https://docs.getdbt.com/reference/artifacts/manifest-json)
- [dbt Model Configurations](https://docs.getdbt.com/reference/model-configs)
- [dbt Configs and Properties](https://docs.getdbt.com/reference/configs-and-properties)
- [dbt Graph Operators](https://docs.getdbt.com/reference/node-selection/graph-operators)
- [dbt Node Selection Methods](https://docs.getdbt.com/reference/node-selection/methods)
- [dbt Adapter Creation](https://docs.getdbt.com/guides/adapter-creation)
- [Terraform Modules](https://developer.hashicorp.com/terraform/language/modules/configuration)
- [Terraform Plan](https://developer.hashicorp.com/terraform/cli/commands/plan)
- [Nx Mental Model](https://nx.dev/docs/concepts/mental-model)
- [Nx Explore Graph](https://nx.dev/docs/features/explore-graph)
- [Bazel Hermeticity](https://bazel.build/basics/hermeticity)
- [Buck2 Architecture](https://www.tweag.io/blog/2023-07-06-buck2/)
- [CrewAI YAML Configuration](https://deepwiki.com/crewAIInc/crewAI/8.2-yaml-configuration)
- [Claude Code Custom Subagents](https://code.claude.com/docs/en/sub-agents)
- [Scaffolding Tools Comparison](https://blog.overctrl.com/code-scaffolding-tools-which-one-should-you-choose/)
