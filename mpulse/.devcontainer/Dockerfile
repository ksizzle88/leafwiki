# syntax=docker/dockerfile:1
# mpulse devcontainer
# Extends Claudio base with data engineering tools for:
#   - DPI_Analytics_DBT (dbt/Snowflake)
#   - data-pipelines/snowflake-export (Python data stack)
#   - hxi-infra (Terraform/AWS)

ARG CLAUDIO_TAG=develop
ARG CLAUDIO_IMAGE=ghcr.io/ksizzle88/claudio
FROM ${CLAUDIO_IMAGE}:${CLAUDIO_TAG}

USER root

# System dependencies for Python data packages
# Note: build-essential, libpq-dev, wget, unzip, direnv, python3-venv inherited from base
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    unixodbc-dev \
    gcc \
    g++ \
    python3-full \
    && rm -rf /var/lib/apt/lists/*

# Install Terraform (for hxi-infra)
ARG TERRAFORM_VERSION=1.10.0
RUN wget -q "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    -O /tmp/terraform.zip && \
    unzip -o /tmp/terraform.zip -d /tmp && \
    mv /tmp/terraform /usr/local/bin/terraform && \
    chmod +x /usr/local/bin/terraform && \
    rm -f /tmp/terraform.zip /tmp/LICENSE.txt

# Install Vault CLI (for hxi-infra HashiCorp suite)
ARG VAULT_VERSION=1.18.3
RUN wget -q "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" \
    -O /tmp/vault.zip && \
    unzip -o /tmp/vault.zip -d /tmp && \
    mv /tmp/vault /usr/local/bin/vault && \
    chmod +x /usr/local/bin/vault && \
    rm -f /tmp/vault.zip /tmp/LICENSE.txt

# Install Nomad CLI (for hxi-infra HashiCorp suite)
ARG NOMAD_VERSION=1.9.4
RUN wget -q "https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_amd64.zip" \
    -O /tmp/nomad.zip && \
    unzip -o /tmp/nomad.zip -d /tmp && \
    mv /tmp/nomad /usr/local/bin/nomad && \
    chmod +x /usr/local/bin/nomad && \
    rm -f /tmp/nomad.zip /tmp/LICENSE.txt

# AWS CLI v2 inherited from base image

# Install Azure CLI (for hxi-infra Azure resources)
# Manual GPG+apt install with retries (Microsoft's CDN is flaky)
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL --retry 3 --retry-delay 5 https://packages.microsoft.com/keys/microsoft.asc \
       | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg \
    && chmod go+r /etc/apt/keyrings/microsoft.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" \
       > /etc/apt/sources.list.d/azure-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends azure-cli \
    && rm -rf /var/lib/apt/lists/*

# Create a venv for mpulse Python packages
# Avoids PEP 668 externally-managed-environment error on Ubuntu 24.04
RUN uv venv /opt/mpulse-venv

# Install Python packages into the venv
# Pinned versions from DPI_Analytics_DBT/requirements.txt where applicable
# dbt core + adapters, sqlfluff, Snowflake connector, and data stack deps.
RUN uv pip install --python /opt/mpulse-venv/bin/python \
    dbt-core==1.8.9 \
    dbt-snowflake==1.9.2 \
    dbt-postgres==1.9.0 \
    dbt-redshift==1.9.3 \
    sqlfluff==3.4.0 \
    sqlfluff-templater-dbt==3.4.0 \
    pre-commit==4.3.0 \
    snowflake-connector-python==3.14.0 \
    boto3 \
    pyarrow \
    pandas \
    numpy \
    psycopg2-binary \
    pyodbc \
    SQLAlchemy \
    cryptography \
    python-dateutil \
    ruff \
    pytz \
    tzdata \
    tabulate

# Install Snowflake CLI (snow) — install to shared path so dev user can access it
RUN UV_TOOL_BIN_DIR=/usr/local/bin UV_TOOL_DIR=/opt/uv-tools uv tool install snowflake-cli

# Put venv on PATH for all users
ENV PATH="/opt/mpulse-venv/bin:$PATH"

ENV PROJECT_NAME=mpulse

# Shell customizations (edit zshrc instead of echo chains)
COPY zshrc /etc/zsh/zshrc.mpulse
RUN echo 'source /etc/zsh/zshrc.mpulse' >> /etc/zsh/zshrc

# Create directories for volume mounts with proper ownership
# (base entrypoint fixes ownership at runtime, but these are needed during build)
ARG DEV_USER=dev
RUN mkdir -p /home/dev/.config /home/dev/.local /home/dev/.cache \
    && chown -R ${DEV_USER}:${DEV_USER} /home/dev/.config /home/dev/.local /home/dev/.cache

# mpulse entrypoint: volume permissions, SSH/Snowflake seeding, drop to dev user
COPY docker-entrypoint.sh /usr/local/bin/mpulse-entrypoint.sh
RUN chmod +x /usr/local/bin/mpulse-entrypoint.sh
ENTRYPOINT ["tini", "--", "/usr/local/bin/mpulse-entrypoint.sh"]

HEALTHCHECK --interval=2m --timeout=5s --start-period=15s --retries=3 \
    CMD command -v claude >/dev/null && command -v dbt >/dev/null
