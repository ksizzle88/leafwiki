# Existing Design Documents Analysis

**Researcher**: design-docs-analyst
**Date**: 2026-03-13
**Scope**: All design documents, PRDs, and research papers relevant to Epic #55 (Dev Toolkit)

---

## Documents Analyzed

| # | Document | Path | Type | Relevance |
|---|----------|------|------|-----------|
| 1 | jtbl 2.0 Design Doc | `/workspace/mpulse/tasks/jqtbl/Jtbl_2.0.md` | Design Doc | Primary spec for Issue #58 |
| 2 | jqtbl PRD (original) | `/workspace/mpulse/tasks/jqtbl/PRD.md` | PRD | Earlier version of #58 spec |
| 3 | jqtbl vs jtable Gap Analysis | `/workspace/mpulse/tasks/jqtbl/jqtbl_vs_jtable.md` | Analysis | Shows what prototype covers vs gaps |
| 4 | Agent Permissions Gateway PRD | `/workspace/mpulse/tasks/agent-permisions-gateway/PRD.md` | PRD | Primary spec for Issue #59 |
| 5 | User-Exec Bridge Research | `/workspace/mpulse/tasks/research/user-exec-bridge-patterns.md` | Research | Related patterns for #59 |
| 6 | Analysis Tools Review | `/workspace/mpulse/tasks/research/analysis-tools-review.md` | Review | Context for jtable/jtbl lineage |
| 7 | Agent Best Practices | `/workspace/mpulse/tasks/research/agent-best-practices.md` | Reference | Foundation for Issue #60 |
| 8 | Agent Build System v1 | `/workspace/mpulse/tasks/research/agent-build-system.md` | Research | Foundation for Issue #60 |
| 9 | Agent Build System v2 | `/workspace/mpulse/tasks/research/agent-build-system-v2.md` | Design | Detailed design for Issue #60 |
| 10 | Team Agent Tool Access | `/workspace/mpulse/tasks/research/team-agent-tool-access.md` | Research | Platform constraints affecting all tools |

---

## 1. jtbl 2.0 Design Document (Issue #58)

**Path**: `/workspace/mpulse/tasks/jqtbl/Jtbl_2.0.md`
**Length**: 618 lines, thorough and implementation-ready

### Key Decisions Already Made

1. **Language/stack**: Python + pandas + Streamlit. NOT TypeScript/React. "Revisit only if Streamlit becomes a hard blocker."
2. **jq execution**: Shell out to `jq` binary with dot-path fallback when jq unavailable. No WASM.
3. **Query model**: jq is the query language for everything. `--where` (pre-projection, jq on source rows) and `--having` (post-projection, jq on projected rows).
4. **Array vs stream mode**: Explicit `--stream` flag. Array is default. Never guess.
5. **Column failure semantics**: Warn and show null for missing fields. Fail only on syntax errors.
6. **Mixed-type sorting**: Stringify fallback with warning.
7. **Packaging**: Two files only — `jtbl.py` (CLI + core) and `jtbl-ui.py` (Streamlit launcher). PEP 723 inline metadata for zero-install via `uv run`.
8. **Config format**: JSON matching CLI flags 1:1. `--save-config` / `--config`.
9. **Web framework**: Streamlit with streamlit-ace for editor component.
10. **CLI is source of truth**: Web UI builds CLI commands. Every UI action maps to a flag.

### Open Questions

1. **Plugin integration with core framework (#56)**: The doc says "Can run standalone via `uv run jtbl.py` or as a dev-toolkit plugin" but doesn't specify the plugin interface. How jtbl registers as a plugin depends on the form factor decision in #56.
2. **Tree Explorer implementation details**: The design describes the concept (navigable expandable/collapsible JSON tree) but doesn't specify which Streamlit component or library to use.
3. **Performance thresholds**: No specific benchmarks for "how large is too large" for in-memory JSON processing. The doc mentions performance mitigations but sets no limits.
4. **jq binary availability**: The doc assumes jq is available or falls back gracefully. For the Claudio devcontainer, jq should be pre-installed in the base image — this is not stated.

### Technical Constraints (Locked In)

- Python 3.10+ required
- Dependencies: pandas >= 2.0, tabulate >= 0.9, streamlit >= 1.30, streamlit-ace >= 0.1.1
- External dependency on `jq` binary (optional but needed for full functionality)
- Single-file CLI with PEP 723 metadata (no setup.py, no virtualenv)
- Data model: Python dataclasses (`Row`, `ProjectedRow`), pandas DataFrame for pipeline

### Dependencies

- Issue #55 Core Framework — for plugin integration (but can be built standalone first)
- `jq` binary (external)
- Python 3.10+, pandas, tabulate, streamlit

### Gaps

1. **No specification of how jtbl becomes a dev-toolkit plugin.** The design doc covers standalone operation thoroughly but the plugin interface is undefined.
2. **No error recovery strategy.** The error handling section defines error messages but not what happens next (retry? partial results? abort?).
3. **No accessibility considerations.** The web UI design has no mention of keyboard navigation, screen reader support, or color contrast.
4. **Post-MVP items are deprioritized but some feel essential.** `--having` (post-projection filter), `--offset`, and `--config` / `--save-config` are all marked post-MVP. The `--having` filter is fundamental to the two-stage filter model described in the query model section — having it be post-MVP creates a design inconsistency.

### Relationship to Earlier PRD

The original PRD (`/workspace/mpulse/tasks/jqtbl/PRD.md`) proposed a TypeScript + React stack and a more abstract data model with TypeScript interfaces. The jtbl 2.0 design doc explicitly supersedes this, choosing Python/Streamlit based on prototyping experience. Section 14 ("Resolved Design Decisions") documents every decision that was open in the original PRD.

The gap analysis (`/workspace/mpulse/tasks/jqtbl/jqtbl_vs_jtable.md`) provides a detailed feature-by-feature comparison showing that the existing `jtable.py` prototype covers input loading and basic CLI well, but has major gaps in: jq support (only dot-path traversal), row inspector, inferred columns, config model, and error handling.

### Conflicts with GitHub Issue #58

None significant. The GitHub issue body is a well-structured summary of the design doc. One minor difference: the issue mentions "Web UI: interactive grid" as an MVP item but the design doc's interactive grid is Streamlit's `st.dataframe()`, which is basic (not a full AG Grid-style component). This may set expectations higher than the Streamlit implementation delivers.

---

## 2. Agent Permissions Gateway PRD (Issue #59)

**Path**: `/workspace/mpulse/tasks/agent-permisions-gateway/PRD.md`
**Length**: 655 lines, comprehensive and well-structured

### Key Decisions Already Made

1. **Architecture**: Host-side runtime. The host machine is trusted; the agent container is untrusted. Credentials never enter the agent's environment.
2. **Communication channel**: Filesystem artifacts. Agent writes request files; host writes output files. No API, no sockets, no network between agent and host.
3. **Action model**: Stable, named slots for recurring objectives (not ad-hoc commands). Agent reuses an action when the goal is the same; creates new for different goals.
4. **Approval model**: Human approval tied to exact content hash + user identity + timestamp.
5. **Ledger model**: Append-only, hash-chained JSONL. Entry types: REQUEST_OBSERVED, APPROVAL_GRANTED, EXECUTION_STARTED, EXECUTION_FINISHED, RESULT_RECORDED.
6. **Output model**: JSON for control plane, files for data plane. Outputs live in files (stdout.log, stderr.log, result.json), not embedded in metadata.
7. **Signing model**: Detached signatures or separate approval records. No inline signing.
8. **MVP runners**: `shell` and `snowflake_sql` only.
9. **Human interface**: Host-side CLI (`agent-runtime status/diff/approve/run/history/verify`).
10. **Tool extensibility**: New tools added as host-side runners + registry entries + agent instructions. Agent never gets new credentials.

### Open Questions

1. **Implementation language/stack**: The PRD is entirely language-agnostic. No decision on Python vs Go vs Node for the host runtime. This is a significant gap for planning.
2. **File watcher implementation**: The PRD says "host runtime watches action directories" but doesn't specify polling vs inotify vs fswatch. The User-Exec Bridge research (`/workspace/mpulse/tasks/research/user-exec-bridge-patterns.md`) notes that file polling is the current pattern with 2-second intervals.
3. **Approval persistence**: How are approvals stored? The PRD mentions `approval.sig` files but doesn't specify the format or what "signing" means at MVP (GPG? HMAC? plain JSON with user identity?).
4. **Concurrent actions**: Can multiple actions be pending simultaneously? The PRD implies yes (multiple action directories) but doesn't discuss race conditions or ordering.
5. **Agent notification**: How does the agent know when execution is complete? The PRD says "filesystem update is the notification channel" but the agent must be polling — what interval? The User-Exec Bridge research confirms this is a known pain point.
6. **Web UI integration**: Issue #59 mentions a web UI for approval (when dev-toolkit is available) but the PRD only specifies a CLI. The web UI design is undefined.

### Technical Constraints (Locked In)

- Host-side execution only (credentials never in container)
- Filesystem-based communication (shared mount between host and container)
- Append-only, hash-chained ledger (JSONL format)
- Action directories as the organizational unit
- Content-hash-based approval (approve specific payload, not action name)

### Dependencies

- Issue #55 Core Framework — for web UI plugin (CLI works standalone)
- Shared volume mount between host and container (Claudio's existing architecture supports this)
- Host-side Snowflake client (for `snowflake_sql` runner)
- Host-side shell access (for `shell` runner)

### Gaps

1. **No implementation language decision.** This is the biggest blocker. The PRD needs a stack decision before planning can begin.
2. **No specification for the `request.meta.json` format.** The PRD mentions it contains "action name, runner/tool type, entrypoint file, created timestamp, last approved content hash, current state, last execution ID" but doesn't provide a JSON schema.
3. **No specification for the `receipt.json` format.** Same as above — described conceptually but no schema.
4. **No specification for the `registry.json` format.** The tool registry is mentioned but not defined.
5. **No specification for `AGENT_INSTRUCTIONS.md` generation.** The PRD says this is auto-generated but doesn't describe the generation logic.
6. **No error handling for runner failures.** What happens if a runner crashes? Timeout? OOM? The PRD mentions exit codes in receipts but not error recovery.
7. **No specification for ledger verification.** `agent-runtime verify` is listed as a CLI command but the verification algorithm (check hash chain integrity) is not described.
8. **MCP Elicitation connection**: The User-Exec Bridge research identifies MCP Elicitation as the ideal long-term solution for user approval (when Claude Code supports it). The PRD doesn't mention this migration path, but the research recommends designing with a fallback architecture that could adopt elicitation later.

### Conflicts with GitHub Issue #59

None significant. The issue is a faithful summary of the PRD. One nuance: the issue lists "Web UI shows pending actions with diff view (when dev-toolkit is available)" as an acceptance criterion, but the PRD only designs a CLI. The web UI for approvals is entirely unspecified.

---

## 3. Related Research Documents

### User-Exec Bridge Patterns (`/workspace/mpulse/tasks/research/user-exec-bridge-patterns.md`)

**Key insight for #59**: The current user-exec-bridge pattern (file-polling at 2s intervals, `wait-for-output` scripts) is the same fundamental architecture as the Agent Permissions Gateway, just less formalized. The research identifies that **stdio MCP servers inherit the user's credentials** — meaning the "right" long-term architecture is an MCP server that runs commands in the user's inherited environment after getting approval via elicitation. The Permissions Gateway's filesystem-based approach is the correct interim solution until Claude Code supports MCP Elicitation (tracked in Claude Code issue #2799, 150+ upvotes, still open as of March 2026).

**Implication**: The Agent Permissions Gateway should be designed with awareness that its approval interface may eventually be replaced by MCP Elicitation. The filesystem artifact model and ledger remain valuable regardless.

### Team Agent Tool Access (`/workspace/mpulse/tasks/research/team-agent-tool-access.md`)

**Key constraint for all tools**: Agent teams do NOT inherit tool configurations from `.claude/agents/` definitions. This is a known platform limitation. Teammates get a reduced, fixed tool set regardless of what agent definitions specify. The only workaround is pre-approving Bash patterns in global `settings.json`.

**Implication for #58 (jtbl)**: If jtbl is invoked by agent teammates via Bash, the command must work without requiring additional permission prompts. Pre-approved Bash patterns or standalone binary installation may be needed.

**Implication for #59 (Permissions Gateway)**: The agent side of the gateway must work with the limited tool set available to teammates. Writing files to the shared mount should work via Write/Edit tools (which teammates do have), but any Bash-based file operations may hit permission issues.

### Agent Build System v2 (`/workspace/mpulse/tasks/research/agent-build-system-v2.md`)

**Key design for #60 (Agent Builder)**: This is a comprehensive, implementation-ready design for a Python build system that compiles `agents.yml` + Jinja2 templates into `.claude/agents/*.md` files. The design covers:
- Declarative YAML configuration format
- Template inheritance (`_base-researcher.md.j2` -> `terraform-planner.md.j2`)
- Shared partials (safety rules, environment context)
- CLI commands: `build`, `validate`, `diff`, `test`
- CI integration (GitHub Actions check for drift)
- Hybrid approach: generate + commit (like `go generate`)

**Implication for #60**: Much of the "Agent Builder" CLI already has a detailed design. The dev-toolkit web UI is the main new work — adding visual DAG, resolved config viewer, and live editing.

### Agent Best Practices (`/workspace/mpulse/tasks/research/agent-best-practices.md`)

**Reference material for #60**: Documents the full anatomy of agent files and skills, including all frontmatter fields, scope/priority rules, built-in agents, permission modes, and anti-patterns. This is essential context for the Agent Builder's validation and scaffolding features.

### Analysis Tools Review (`/workspace/mpulse/tasks/research/analysis-tools-review.md`)

**Context for #58**: Documents the lineage from `extract-updates.py` -> `tfplan.py updates` -> `jtable` -> `jtbl 2.0`. Confirms that jtable is a general-purpose JSON exploration tool (not terraform-specific) that has diverged into two versions (`~/.claude/bin/jtable` and `analysis/jtable.py`). Recommends merging. This validates that jtbl 2.0 is a clean-slate rewrite that subsumes both versions.

---

## 4. Cross-Cutting Analysis

### What's Been Decided vs What Still Needs Research

| Area | Decided | Needs Research |
|------|---------|----------------|
| **jtbl stack** | Python + pandas + Streamlit | Plugin interface with core framework |
| **jtbl query model** | jq subprocess + dot-path fallback | Performance limits for large JSON |
| **jtbl packaging** | PEP 723, two files, `uv run` | How this packages inside the Claudio base image |
| **Gateway architecture** | Host-side, filesystem artifacts, hash-chained ledger | Implementation language, runner timeout handling |
| **Gateway security** | Content-hash approval, detached signatures | Signing mechanism for MVP (GPG vs HMAC vs plain) |
| **Gateway MVP runners** | `shell` + `snowflake_sql` | Runner implementation details, error handling |
| **Agent Builder CLI** | `agents.yml` + Jinja2 templates + Python generator | Web UI for visual DAG and resolved config |
| **Core framework form factor** | Leaning web server | Not formally evaluated yet — this is #56's job |
| **Core framework stack** | Options listed (FastAPI vs Node, HTMX vs React) | No decision made |

### Dependency Chain

```
#56 Core Framework (BLOCKS everything with web UI)
  ├── #57 Markdown Browser (needs plugin host)
  ├── #58 jtbl 2.0 (CLI standalone, web needs plugin host)
  ├── #59 Agent Permissions Gateway (CLI standalone, web approval UI needs host)
  └── #60 Agent Builder (CLI from v2 design, web needs plugin host + #57)
```

Critical insight: **Every sub-issue can be built as a standalone CLI first**, then integrated as a dev-toolkit plugin later. The core framework (#56) only blocks the web UI portions. This means implementation can start on #58, #59, and #60 in parallel with #56 as long as the plugin interface contract is agreed upon.

### Risk Areas

1. **Form factor uncertainty (#56)**: If the form factor decision changes from "web server" to "VS Code extension," the plugin model for all tools changes significantly. This is the highest-risk decision.

2. **Streamlit limitations (#58)**: The jtbl design is built on Streamlit, but if the core framework uses FastAPI + React, jtbl's web UI would need to be rewritten. Alternatively, jtbl's Streamlit app could run as a standalone tool outside the framework.

3. **MCP Elicitation timeline (#59)**: The Permissions Gateway's file-polling approval model is a known interim solution. If Claude Code ships elicitation support soon, the approval interface design may become obsolete — though the ledger and artifact model remain valuable.

4. **Agent teams limitation (#60)**: The Agent Builder's value proposition includes managing agent definitions for teams, but teams don't use agent definitions today (platform limitation). The build system is still useful for standalone subagents and direct use, but the "teams" story is weak until the platform catches up.

### Key Decisions the Planner Should Be Aware Of

1. **jtbl 2.0 explicitly chose Python over TypeScript.** The original PRD proposed TS; this was overruled based on prototyping experience. Do not re-open this decision.

2. **The Agent Permissions Gateway is a host-side tool, not a container-side tool.** This has architectural implications: it runs outside Docker, uses host credentials, and communicates via shared filesystem. It does NOT run inside the Claudio devcontainer.

3. **Agent Build System v2 is a mature design ready for implementation.** The research is done. The CLI design, config format, template system, and validation rules are all specified. The web UI is the new work for #60.

4. **The existing jtable prototype is being replaced, not extended.** jtbl 2.0 is a clean-slate design informed by jtable's lessons. The gap analysis (`jqtbl_vs_jtable.md`) documents exactly what to keep and what to redesign.

5. **All tools must work standalone before plugin integration.** The dependency chain makes this clear: #56 is not started, so nothing should block on having a plugin host ready.

---

## 5. Summary: Document Quality and Completeness

| Document | Quality | Completeness | Ready for Planning? |
|----------|---------|-------------|-------------------|
| jtbl 2.0 Design Doc | Excellent — thorough, opinionated, implementation-ready | High — CLI fully specified, web UI layout detailed | Yes, with minor gaps noted |
| jqtbl PRD (original) | Good — but superseded by jtbl 2.0 | N/A — historical | No (use jtbl 2.0 instead) |
| jqtbl vs jtable Gap Analysis | Excellent — precise feature-by-feature comparison | Complete | Yes (context for jtbl implementation) |
| Agent Permissions Gateway PRD | Very good — architecture and concepts clear | Medium — missing schemas, language choice, error handling | Partially — needs stack decision + schema definitions |
| User-Exec Bridge Research | Excellent — thorough survey with clear recommendation | Complete | Yes (informs #59 design) |
| Agent Build System v2 | Excellent — implementation-ready with code examples | High — CLI, config, templates, validation all specified | Yes (for CLI); web UI needs design |
| Agent Best Practices | Very good — comprehensive reference | Complete | Yes (reference for #60) |
| Analysis Tools Review | Good — clear lineage and recommendations | Complete | Yes (context for #58) |
| Team Agent Tool Access | Critical — documents a hard platform constraint | Complete | Yes (constraint for all tools) |

