# Research: Scaffolding, Template Generation & CLI Tool Patterns

**Task**: GitHub Issue #60 — Agent Builder
**Epic**: GitHub Issue #55
**Researcher**: scaffolding-and-cli-tools
**Date**: 2026-03-13

---

## 1. Scaffolding Tool Comparison

### 1.1 Plop.js

**Type**: Micro-generator framework (Node.js)
**Template Engine**: Handlebars
**Configuration**: `.plopfile.js` (JavaScript)

**How it works**: Plop is glue code between Inquirer prompts and Handlebars templates. You define "generators" in a plopfile, each with a set of prompts and actions (add file, modify file, shell command).

**Strengths**:
- Very simple mental model: prompts + templates = files
- Handlebars is widely known
- Custom actions for complex logic
- Lightweight (no heavy framework)

**Weaknesses**:
- Requires Node.js runtime
- No built-in support for template updates (one-shot generation)
- Configuration is JavaScript, not declarative

**Relevance to Agent Builder**: Good template engine, but adds a Node.js dependency that may be unnecessary given Claudio already uses shell scripts for its CLI.

### 1.2 Hygen

**Type**: Convention-based code generator (Node.js)
**Template Engine**: EJS
**Configuration**: `_templates/` directory convention

**How it works**: Templates live in `_templates/{generator}/{action}/*.ejs.t` directories. Each `.ejs.t` file has a YAML frontmatter header specifying output path and action type (`to`, `inject`, `sh`). Running `hygen {generator} {action}` processes all templates in that directory.

**Strengths**:
- Convention over configuration — no config file needed
- Templates checked into the project alongside code
- Supports `inject` action to modify existing files (not just create)
- `prompt.js` for interactive prompts
- Zero-config for simple use cases

**Weaknesses**:
- Requires Node.js
- EJS templates can be verbose
- No template update/migration support

**Relevance to Agent Builder**: The convention-based approach (`_templates/` directory) is a good pattern. The frontmatter-in-templates concept mirrors how Claude Code already uses frontmatter in agent/skill definitions.

### 1.3 Yeoman

**Type**: Full project scaffolding ecosystem (Node.js)
**Template Engine**: Various (EJS by default)
**Configuration**: Generator classes extending `yeoman-generator`

**Strengths**:
- Composable generators (generators calling generators)
- Rich ecosystem of community generators
- File conflict resolution
- Mature and battle-tested

**Weaknesses**:
- Heavyweight for simple scaffolding
- Complex generator authoring
- Requires Node.js
- Overkill for generating 1-3 files

**Relevance to Agent Builder**: Too heavy. Agent Builder needs to create 1-3 files per scaffold operation, not entire project structures.

### 1.4 Cookiecutter (Python)

**Type**: Template-based project generator (Python)
**Template Engine**: Jinja2
**Configuration**: `cookiecutter.json`

**Strengths**:
- Widely used in Python ecosystem
- Jinja2 is powerful and well-documented
- Pre/post generation hooks (shell scripts)
- Can pull templates from git repos

**Weaknesses**:
- Python dependency
- No template update/migration support
- Designed for project-level scaffolding, not file-level

**Relevance to Agent Builder**: Overkill for the use case. Designed for generating entire projects, not individual files.

### 1.5 Copier (Python)

**Type**: Modern template engine with update support (Python)
**Template Engine**: Jinja2
**Configuration**: `copier.yml` / `copier.yaml`

**Strengths**:
- **Template updates**: `copier update` pulls template changes into existing projects
- Validation of user inputs
- Conditional file generation
- Migration support between template versions

**Weaknesses**:
- Python dependency
- Newer, smaller community than Cookiecutter
- Still project-oriented

**Relevance to Agent Builder**: The update mechanism is interesting if agent templates evolve over time, but adds Python dependency and is still overkill for single-file generation.

### 1.6 degit / giget

**Type**: Git repo cloner (Node.js)
**Template Engine**: None (file copy)

**Strengths**:
- Dead simple: clone repo, optionally transform
- No template engine overhead

**Weaknesses**:
- No variable substitution
- No prompts
- Requires git repos as template source

**Relevance to Agent Builder**: Too simple. Agent Builder needs variable substitution (agent name, description, tools).

### 1.7 Native Shell Approach (Recommended)

**Type**: Shell scripts with heredocs and `sed`/`envsubst`
**Template Engine**: Shell variable substitution or `envsubst`

**How it works**: Templates are heredocs or template files with placeholders. Shell scripts prompt the user, substitute variables, and write files.

**Strengths**:
- **Zero dependencies** — bash is already available
- **Matches existing Claudio CLI patterns** — the `claudio` CLI is already shell-based
- Simple, transparent, easy to debug
- Fast execution
- `envsubst` handles variable substitution in template files
- Heredocs handle inline templates cleanly

**Weaknesses**:
- No template inheritance or composition
- Manual prompt handling (but Claudio already has `common.sh` patterns)
- String manipulation is more awkward than Jinja2/Handlebars

**Relevance to Agent Builder**: **Best fit.** The existing `claudio` CLI is a shell-based command router with `cli/commands/*.sh` subcommands and `cli/lib/{common,output}.sh` libraries. Adding `agent-builder` as a subcommand (or separate CLI) using the same patterns keeps the architecture consistent and avoids new dependencies.

### 1.8 Bashly

**Type**: Bash CLI framework/generator (Ruby)
**Configuration**: YAML → generates bash scripts

**How it works**: You write a YAML file describing CLI structure (commands, subcommands, flags, arguments). Bashly generates a complete, shellcheck-compliant bash script with argument parsing, help text, and validation. Your business logic goes in separate handler files that get merged into the generated script.

**Strengths**:
- Generates clean, standalone bash scripts
- YAML-driven CLI design
- Automatic help generation, validation, completions
- No runtime dependency (output is pure bash)

**Weaknesses**:
- Requires Ruby for generation (dev-time dependency)
- Generated code can be harder to maintain vs hand-written
- Another layer of abstraction over bash

**Relevance to Agent Builder**: Interesting for CLI generation but adds complexity. The existing Claudio CLI pattern (manual command routing with sourced scripts) is already clean and maintainable.

---

## 2. Recommendation: Native Shell Scaffolding

### Why Shell Scripts Over External Tools

1. **Consistency**: The Claudio CLI (`/workspace/cli/claudio`) already uses a shell-based command router pattern with:
   - `cli/claudio` — main entry point with `case` routing
   - `cli/commands/*.sh` — subcommand implementations
   - `cli/lib/common.sh` — shared utilities (colors, logging, flags)
   - `cli/lib/output.sh` — formatting helpers (headers, tables, help text)
   
2. **Zero dependencies**: No Node.js, Python, or Ruby required for scaffolding
   
3. **Transparency**: Users can read and modify templates directly
   
4. **Template files + `envsubst`**: Store templates as files with `${VARIABLE}` placeholders, substitute at generation time

### Implementation Pattern

```
cli/
├── claudio                    # existing entry point
├── commands/
│   ├── help.sh               # existing
│   ├── verify.sh             # existing
│   ├── doctor.sh             # existing
│   ├── version.sh            # existing
│   └── new.sh                # NEW: scaffolding command
├── lib/
│   ├── common.sh             # existing shared utils
│   └── output.sh             # existing output formatting
└── templates/
    ├── agent/                 # NEW: agent templates
    │   └── agent.md.template
    ├── command/               # NEW: command templates  
    │   └── command.md.template
    └── hook/                  # NEW: hook templates
        └── hook.sh.template
```

The `claudio new agent <name>` command would:
1. Read template from `cli/templates/agent/agent.md.template`
2. Prompt for required fields (description, model, tools) if not provided via flags
3. Substitute variables using `envsubst` or `sed`
4. Write to `.claude/agents/<name>.md`
5. Print success message with next steps

---

## 3. CLI Framework Comparison

### 3.1 Shell-Based (Current Pattern)

| Aspect | Current Claudio CLI |
|--------|-------------------|
| Language | Bash |
| Routing | `case` statement in main script |
| Subcommands | Sourced from `cli/commands/*.sh` |
| Shared code | `cli/lib/common.sh`, `cli/lib/output.sh` |
| Flag parsing | Manual `while/case` loop with `parse_common_flags()` |
| Help | `print_concise_help()`, `print_extensive_help()` |
| Output | Colored output, JSON mode, quiet/verbose modes |
| Testing | Can be tested with bats or simple shell assertions |

**Verdict**: Already sufficient. The existing patterns handle everything the Agent Builder CLI needs.

### 3.2 Python Click

**Strengths**: Decorator-based, very popular (38.7% of Python CLIs in 2025), excellent docs, composable groups.
**Weaknesses**: Python dependency, separate from existing CLI, packaging overhead.
**Verdict**: Would be excellent for a standalone tool, but splitting the CLI between bash and Python creates maintenance burden.

### 3.3 Python Typer

**Strengths**: Modern Click wrapper using type hints, auto-generated help, less boilerplate.
**Weaknesses**: Same as Click plus Typer-specific dependency.
**Verdict**: Same concern as Click — language mismatch with existing CLI.

### 3.4 Python argparse

**Strengths**: Standard library, no external deps.
**Weaknesses**: Verbose, less ergonomic than Click/Typer.
**Verdict**: If Python is chosen, Click or Typer is better.

### 3.5 Node.js Commander.js

**Strengths**: Lightweight, widely used, simple API.
**Weaknesses**: Node.js dependency (already present in container though).
**Verdict**: Viable but creates language split.

### 3.6 Node.js yargs

**Strengths**: Feature-rich, built-in completion, middleware.
**Weaknesses**: Heavier than Commander.
**Verdict**: Overkill for this use case.

### 3.7 Node.js oclif

**Strengths**: Plugin system, TypeScript, auto-docs, scaffolding built-in. Used by Salesforce.
**Weaknesses**: Heavy framework, TypeScript overhead, overkill.
**Verdict**: Way too heavy for agent scaffolding commands.

### 3.8 Go Cobra

**Strengths**: Standard Go CLI framework, compiled binary, fast.
**Weaknesses**: Go dependency, compile step, different ecosystem.
**Verdict**: Wrong ecosystem.

### CLI Framework Recommendation

**Extend the existing Claudio bash CLI.** The `claudio` command already has:
- Clean command routing (`cli/claudio` main entry)
- Shared libraries for output formatting, color, flags
- Help system with concise and extensive modes
- Support for `--json`, `--quiet`, `--verbose`, `--no-color`
- Established patterns that contributors understand

Adding `agent-builder` functionality as `claudio new <type> <name>` subcommands fits naturally. No new dependencies, no language mismatch, no packaging changes.

For the **web UI** portion (Issue #60 mentions a Dev Toolkit Plugin), that would use whatever framework the Dev Toolkit uses (likely React/TypeScript based on the project structure), but the CLI scaffolding should stay in bash.

---

## 4. Template Content Structures

Based on analysis of the actual files in this repository, here are the exact formats that templates must produce.

### 4.1 Agent Definition Template

**Location**: `.claude/agents/<name>.md`
**Format**: YAML frontmatter + Markdown body

Based on the existing agents in `/workspace/.claude/agents/`:

```yaml
---
name: {{name}}
description: {{description}}
tools: {{tools}}
model: {{model}}
---

{{system_prompt_body}}
```

**Frontmatter fields** (from Claude Code docs):

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| `name` | Yes | string | Lowercase letters, numbers, hyphens. Max 64 chars. |
| `description` | Yes | string | When Claude should delegate to this agent |
| `tools` | No | comma-separated | Tool allowlist. Inherits all if omitted |
| `disallowedTools` | No | comma-separated | Tool denylist |
| `model` | No | string | `sonnet`, `opus`, `haiku`, full model ID, or `inherit` |
| `permissionMode` | No | string | `default`, `acceptEdits`, `dontAsk`, `bypassPermissions`, `plan` |
| `maxTurns` | No | number | Max agentic turns |
| `skills` | No | list | Skills to preload into context |
| `mcpServers` | No | list | MCP servers available to this agent |
| `hooks` | No | object | Lifecycle hooks scoped to this agent |
| `memory` | No | string | `user`, `project`, or `local` |
| `background` | No | boolean | Always run as background task |
| `isolation` | No | string | `worktree` for isolated git worktree |

**Tool syntax examples** (from existing agents):
- Simple: `Read, Glob, Grep, WebSearch`
- With patterns: `Bash(gh issue *), Bash(git log *)`
- Agent spawning: `Agent(researcher, planner, implementer, reviewer)`
- Write restrictions: `Write(.taskmaster/**)`

**Example template file** (`cli/templates/agent/agent.md.template`):

```markdown
---
name: ${AGENT_NAME}
description: ${AGENT_DESCRIPTION}
tools: Read, Glob, Grep, Bash
model: inherit
---

You are a ${AGENT_ROLE}. 

## Your Job

${AGENT_JOB_DESCRIPTION}

## Process

1. Understand the task requirements
2. Research the relevant code and context
3. Execute your work
4. Report results

## Rules

- Follow existing patterns and conventions in the codebase
- Be thorough but focused
- Report back with specific file paths and details
```

### 4.2 Slash Command / Skill Template

**Location**: `.claude/commands/<name>.md` or `.claude/skills/<name>/SKILL.md`
**Format**: YAML frontmatter + Markdown body

Based on existing commands in `/workspace/.claude/commands/`:

```yaml
---
description: {{description}}
argument-hint: {{argument_hint}}
allowed-tools: {{tools}}
---

# {{Title}}: {{Subtitle}}

## Objective

{{objective}}

## Process

### 1. {{Step 1 title}}

{{step 1 details}}

## Output

{{output_description}}
```

**Frontmatter fields** (from Claude Code docs):

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| `name` | No | string | Display name. Defaults to directory/file name |
| `description` | Recommended | string | What the skill does and when to use it |
| `argument-hint` | No | string | Hint for autocomplete, e.g., `<issue-number>` |
| `disable-model-invocation` | No | boolean | Prevent Claude from auto-loading |
| `user-invocable` | No | boolean | Show in `/` menu. Default: true |
| `allowed-tools` | No | comma-separated | Tools allowed without permission prompts |
| `model` | No | string | Model to use when skill is active |
| `context` | No | string | `fork` to run in a subagent |
| `agent` | No | string | Agent type when `context: fork` |
| `hooks` | No | object | Hooks scoped to this skill |

**Variable substitutions available in skills**:
- `$ARGUMENTS` — all arguments passed when invoking
- `$ARGUMENTS[N]` or `$N` — specific argument by index
- `${CLAUDE_SESSION_ID}` — current session ID
- `${CLAUDE_SKILL_DIR}` — directory containing SKILL.md
- `` !`command` `` — shell command injection (preprocessed)

**Example template file** (`cli/templates/command/command.md.template`):

```markdown
---
description: ${CMD_DESCRIPTION}
argument-hint: ${CMD_ARGUMENT_HINT}
allowed-tools: Read, Glob, Grep, Bash
---

# ${CMD_TITLE}

## Objective

${CMD_OBJECTIVE}

## Process

### 1. Gather Context

Read the relevant files and understand the current state.

### 2. Execute

Perform the requested operation.

### 3. Verify

Confirm the operation completed successfully.

## Output

Provide a summary of what was done and any relevant details.
```

### 4.3 Lifecycle Hook Template

**Location**: `.claude/hooks/<event-name>.sh`
**Format**: Shell script with specific exit code conventions

Based on existing hooks in `/workspace/.claude/hooks/`:

```bash
#!/bin/bash
# .claude/hooks/{{event_name}}.sh
# Quality gate: runs when {{event_description}}.
# Exit 0 = allow. Exit 2 = block with feedback (stderr).
#
# {{additional_description}}

# Read hook input from stdin (JSON)
# INPUT=$(cat)

# Your validation logic here

exit 0
```

**Hook events** (from Claude Code docs):

| Event | Matcher Input | When it fires |
|-------|--------------|---------------|
| `PreToolUse` | Tool name | Before a tool is used |
| `PostToolUse` | Tool name | After a tool is used |
| `Stop` | (none) | When Claude stops |
| `TeammateIdle` | (none) | When a teammate is about to idle |
| `TaskCompleted` | (none) | When a task is marked complete |
| `SubagentStart` | Agent type name | When a subagent begins |
| `SubagentStop` | Agent type name | When a subagent completes |

**Exit codes**:
- `0` — Allow the action to proceed
- `2` — Block the action, send stderr as feedback

**Example template file** (`cli/templates/hook/hook.sh.template`):

```bash
#!/bin/bash
# .claude/hooks/${HOOK_EVENT}.sh
# Quality gate: runs when ${HOOK_DESCRIPTION}.
# Exit 0 = allow action. Exit 2 = block action with feedback (stderr).

set -euo pipefail

# Read hook input from stdin (JSON with tool_input, etc.)
INPUT=$(cat)

# --- Your validation logic here ---
# Example: Extract the tool command
# COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Allow by default
exit 0
```

### 4.4 MCP Server Config Snippet

**Location**: `.claude/mcp.json`
**Format**: JSON

Based on `/workspace/.claude/mcp.json`:

```json
{
  "mcpServers": {
    "{{server_name}}": {
      "type": "stdio",
      "command": "{{command}}",
      "args": [{{args}}]
    }
  }
}
```

For MCP, the scaffolding should **merge** into the existing `mcp.json` rather than overwriting it. This is a JSON merge operation, not a file creation.

### 4.5 Settings.json Entries

**Location**: `.claude/settings.json`
**Format**: JSON

Based on `/workspace/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": ["Tool(pattern)"]
  },
  "env": {
    "KEY": "value"
  },
  "hooks": {
    "EventName": [
      {
        "matcher": "pattern",
        "hooks": [
          {
            "type": "command",
            "command": "path/to/script.sh"
          }
        ]
      }
    ]
  }
}
```

For settings, scaffolding should **merge** new entries into the existing settings.json, not overwrite.

---

## 5. Proposed CLI Command Structure

Based on the Claudio CLI patterns and the Agent Builder requirements from Issue #60:

```bash
# Scaffolding (new subcommand on claudio CLI)
claudio new agent <name>           # Create .claude/agents/<name>.md
claudio new command <name>         # Create .claude/commands/<name>.md
claudio new skill <name>           # Create .claude/skills/<name>/SKILL.md  
claudio new hook <event>           # Create .claude/hooks/<event>.sh

# Browse and inspect (could be separate `agent-builder` or under `claudio`)
claudio agents list                # List all agent definitions
claudio agents show <name>         # Show resolved agent definition
claudio agents resolve settings    # Show merged settings.json
claudio agents graph               # Output dependency graph (DOT format)

# Validate
claudio agents validate            # Check all definitions
claudio agents validate --fix      # Auto-fix what's possible

# Build
claudio agents compile             # Compile all to manifest
claudio agents diff                # Show pending changes
```

**Alternative**: Issue #60 specifies `agent-builder` as the command name. This could be:
- A separate CLI (`agent-builder`) installed alongside `claudio`
- A `claudio agent-builder` subcommand group
- Aliased: `claudio ab` for short

### Implementation Approach for `claudio new`

Add to `cli/claudio` case statement:
```bash
new)
    source "${SCRIPT_DIR}/commands/new.sh"
    shift
    cmd_new "$@"
    ;;
```

The `cmd_new` function routes to type-specific handlers:
```bash
cmd_new() {
    local type="${1:-}"
    local name="${2:-}"
    
    case "${type}" in
        agent)    new_agent "${name}" "${@:3}" ;;
        command)  new_command "${name}" "${@:3}" ;;
        skill)    new_skill "${name}" "${@:3}" ;;
        hook)     new_hook "${name}" "${@:3}" ;;
        *)        error "Unknown type: ${type}" ;;
    esac
}
```

---

## 6. Key Decisions for the Planner

### Decision 1: CLI Tool vs. Separate Binary
**Recommendation**: Extend existing `claudio` CLI. Keeps architecture simple, reuses existing patterns.

### Decision 2: Template Storage Location
**Recommendation**: Store templates in `cli/templates/` (already exists) with new subdirectories for agent, command, skill, and hook templates. These ship with the Docker image at `/usr/local/lib/claudio/templates/`.

### Decision 3: Variable Substitution Method
**Recommendation**: Use `envsubst` for template files. It is available on all Linux systems, handles `${VAR}` syntax cleanly, and the templates remain readable as plain Markdown/shell.

Fallback: `sed -e "s/\${VAR}/value/g"` for systems without `envsubst`.

### Decision 4: Interactive vs. Flag-Based Input
**Recommendation**: Support both:
- `claudio new agent my-researcher` — interactive prompts for description, tools, model
- `claudio new agent my-researcher --description "..." --tools "Read,Grep" --model sonnet` — fully non-interactive for automation

### Decision 5: Skill vs. Command Templates
**Recommendation**: Default to skills format (`.claude/skills/<name>/SKILL.md`) since Claude Code docs say skills are the recommended approach and commands are a legacy compatibility layer. But support `--format command` flag to generate old-style `.claude/commands/<name>.md` for backward compatibility.

### Decision 6: Where Agent Builder Lives in Issue Scope
Issue #60 covers both CLI and Web UI. The scaffolding (CLI) portion is Phase 1 and can be implemented independently of the web UI (which depends on #55 Core Framework and #57 Markdown Editor).

---

## 7. Risks and Concerns

1. **Claude Code format evolution**: The frontmatter schema for agents/skills is still evolving (e.g., `memory`, `isolation`, `background` are newer fields). Templates should include only the core fields and document optional fields in comments.

2. **Template drift**: As new frontmatter fields are added to Claude Code, templates may become outdated. Consider a `claudio new agent --list-fields` command that documents available fields.

3. **JSON merge for settings/mcp**: Merging JSON is harder in bash than file creation. May need `jq` as a dependency (already present in the Claudio Docker image).

4. **Web UI dependency**: The browse/inspect/validate/compile features from Issue #60 are much more complex than scaffolding and depend on #55 and #57. Scaffolding can ship first as a standalone feature.

---

## 8. Summary Table

| Tool | Language | Template Engine | Dependencies | Fit for Agent Builder |
|------|----------|----------------|-------------|----------------------|
| Plop.js | Node.js | Handlebars | npm install | Medium — good engine, wrong ecosystem |
| Hygen | Node.js | EJS | npm install | Medium — nice conventions, wrong ecosystem |
| Yeoman | Node.js | Various | npm install | Low — too heavy |
| Cookiecutter | Python | Jinja2 | pip install | Low — project-level, not file-level |
| Copier | Python | Jinja2 | pip install | Low-Medium — update support nice, still overkill |
| degit/giget | Node.js | None | npm install | Low — too simple |
| **Native shell** | **Bash** | **envsubst/heredoc** | **None** | **High — matches existing CLI patterns** |
| Bashly | Ruby (gen) | YAML→bash | gem install | Medium — interesting but adds complexity |

**Winner: Native shell approach** using the existing Claudio CLI patterns, `envsubst` for template substitution, and template files stored in `cli/templates/`.

