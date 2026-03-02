# Workspace Overview

Multi-repo workspace for DecisionPoint / mPulse data engineering. This directory is a task-tracking hub, not a standalone project.

## Primary Repos (Active Focus)

### DPI_Analytics_DBT
- **Location**: `/workspace/DPI_Analytics_DBT`
- **Remote**: `git@github.com:mpulsemobile/DPI_Analytics_DBT.git` (GitHub)
- **Purpose**: dbt project for Snowflake analytics (APD models, ingestion, ML)
- **Key paths**:
  - `dpi_ml_apd_dbt/models/` — staging, intermediate, marts (standard dbt layering)
  - `dpi_ingestion/` — ingestion model generation and APD source sync
  - `scripts/apd_utils/` — APD test helpers and query printing
- **Stack**: dbt, Snowflake, Python, sqlfluff, Docker
- **Lint**: `sqlfluff lint/fix` with Snowflake dialect (see `.sqlfluff` config)
- **Build**: `make dbt-dev` to start dev container; `dbt debug` to verify connectivity

### data-pipelines/snowflake-export
- **Location**: `/workspace/data-pipelines/snowflake-export`
- **Remote**: `git@bitbucket.org:decisionpointhealth/data-pipelines.git` (Bitbucket)
- **Purpose**: Python-based Snowflake data export system (parquet, parallel export, scheduling)
- **Key files**:
  - `snowflake_export.py` — main entry point
  - `parquet_parallel_exporter.py` / `parquet_stream_exporter.py` — export engines
  - `export_strategy.py`, `strategies/` — export strategy pattern
  - `config/`, `config.yml` — export configuration
  - `Jenkinsfile` — CI/CD pipeline
  - `tests/` — test suite
- **Stack**: Python, Snowflake connector, Parquet, Jenkins

## Other Repos in Workspace

| Repo | Remote | Description |
|------|--------|-------------|
| `data-pipelines` | Bitbucket (decisionpointhealth) | Monorepo with 50+ pipeline modules (snowflake-import, file-movement, hxi-export, etc.) |
| `hxi-data-pipelines` | GitHub (mpulsemobile) | HXI-specific data pipelines |
| `hxi-infra` | GitHub (mpulsemobile) | HXI infrastructure (Terraform, Snowflake account configs) |
| `public-powershell` | Bitbucket (decisionpointhealth) | PowerShell utilities |
| `python-scripts` | Bitbucket (decisionpointhealth) | Shared Python scripts |

## Snowflake Environments

Connections configured in `~/.snowflake/connections.toml`:

| Connection | Purpose | Account |
|------------|---------|---------|
| `dpi_data_ops` | Data Ops QA/Dev | nmb10465 |
| `dpi_data_ops_prod` | Data Ops Production | EGC79305 |
| `dpi_ml_prod` | ML Production | tob70205 |
| `mp_de_qa` | mPulse DE QA | vjb21090 |
| `mp_de_stage` | mPulse DE Staging | MEB84506 |
| `mp_de_prod` | mPulse DE Production | yzb01027 |
| `edw-develop` | EDW Development | oab27176 |

Terraform connections (`*_tf`) use JWT auth with service account `terraform`.

## Conventions

- **Git hosting**: GitHub for mpulsemobile org, Bitbucket for decisionpointhealth org
- **SQL style**: Snowflake dialect, sqlfluff-enforced formatting
- **dbt layering**: staging → intermediate → marts (all subdirs need `schema.yml`)
- **CI/CD**: Jenkins pipelines
- **Auth**: Snowflake external browser auth for interactive, JWT for service accounts

---

## Role: Orchestration Agent

This workspace is the **planning and orchestration layer**. The main agent (running here) only plans, tracks, and reviews. It never directly edits repository files.

- **NEVER** edit files inside the repositories
- **NEVER** write code to the repositories
- **NEVER** update documentation in the repositories
- **DO** create and manage task files in `/workspace/tasks/`
- **DO** read repo files for research and planning
- **DO** dispatch sub-agents (via the Task tool) to execute work inside repos

### Sub-Agent Execution

When a sub-task is ready for execution, launch a sub-agent with:
- The sub-task file content as context
- The target repo path as working directory
- Clear instructions on what files to modify and how

The main agent reviews sub-agent output, updates task status, and moves files through the workflow.

---

## Task Workflow

All tasks are managed through `/workspace/tasks/` using a folder-based status system.

### Folder Structure

```
tasks/
  general/                       # Parent task files
    1-todo/                      # New tasks — being spec'd out
    2-planning/                  # Spec complete, broken into repo sub-tasks
    3-in-progress/               # Sub-task work has started
    4-review/                    # All sub-task work complete, under review
    5-done/                      # Review approved, task closed
  data-pipelines/                # Sub-tasks for data-pipelines repo
    1-todo/
    2-in-progress/
    3-review/
    4-done/
  DPI_Analytics_DBT/             # Sub-tasks for DPI_Analytics_DBT repo
    1-todo/
    2-in-progress/
    3-review/
    4-done/
```

New repo folders are created as needed (same 4 sub-folders: todo, in-progress, review, done).

### Lifecycle

1. **todo** — Task is created in `general/1-todo/`. Research the codebase, spec out requirements, and document what needs to change and where. No sub-tasks exist yet — the parent file contains all details. The task stays in todo until it is fully spec'd and ready to be broken apart.
2. **planning** — Task is fully spec'd. Now break it into sub-task files (one per repo that needs changes). Sub-tasks go into their repo's `1-todo/` folder. Parent task moves from `general/1-todo/` to `general/2-planning/`. Parent file's Sub-Tasks table is populated with links to each sub-task and their current status.
3. **in-progress** — Work begins. Dispatch sub-agents to execute sub-tasks in their repos. Move parent from `general/2-planning/` to `general/3-in-progress/`. As each sub-task is actively worked on, move it from its repo's `1-todo/` to `2-in-progress/`. Update the parent's Sub-Tasks table to reflect each sub-task's status.
4. **review** — All sub-task work is complete. Move parent to `general/4-review/` and sub-tasks to their repo's `3-review/`. Thoroughly review all changes against the spec.
5. **done** — Review approved. Move parent to `general/5-done/` and all sub-tasks to their repo's `4-done/`.

### File Naming

- Parent tasks: `XXXX-short-description.md` (e.g., `0001-disease-mapping-route.md`)
- Sub-tasks: `XXXX-short-description.md` matching the parent ID in the repo's folder

### Parent Task File Format

```markdown
# Task XXXX: Title

**Status**: todo | planning | in-progress | review | done
**Created**: YYYY-MM-DD

## Summary
What and why.

## Sub-Tasks
| Sub-Task | Repo | Status | File |
|----------|------|--------|------|
| description | repo-name | todo/in-progress/review/done | relative path |

## Details
Full spec, research findings, change list, etc.
```
