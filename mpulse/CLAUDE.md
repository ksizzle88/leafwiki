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
