# syntax=docker/dockerfile:1
# mpulse devcontainer
# Extends Claudio base with data engineering tools for:
#   - DPI_Analytics_DBT (dbt/Snowflake)
#   - data-pipelines/snowflake-export (Python data stack)
#   - hxi-infra (Terraform/AWS)

ARG CLAUDIO_TAG=develop
FROM ghcr.io/ksizzle88/claudio:${CLAUDIO_TAG}

USER root

# System dependencies for Python data packages
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
    unixodbc-dev \
    build-essential \
    gcc \
    g++ \
    wget \
    unzip \
    python3-venv \
    python3-full \
    direnv \
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

# Install AWS CLI v2 (for data-pipelines boto3 work)
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && \
    unzip /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/awscliv2.zip /tmp/aws

# Install Azure CLI (for hxi-infra Azure resources)
RUN curl -fsSL https://aka.ms/InstallAzureCLIDeb | bash

# Create a venv for mpulse Python packages
# Avoids PEP 668 externally-managed-environment error on Ubuntu 24.04
RUN python3 -m venv /opt/mpulse-venv

# Install Python packages into the venv
# Pinned versions from DPI_Analytics_DBT/requirements.txt where applicable
RUN /opt/mpulse-venv/bin/pip install --no-cache-dir \
    # --- dbt (DPI_Analytics_DBT) ---
    dbt-core==1.8.9 \
    dbt-snowflake==1.9.2 \
    dbt-postgres==1.9.0 \
    dbt-redshift==1.9.3 \
    # --- dbt code quality ---
    sqlfluff==3.4.0 \
    sqlfluff-templater-dbt==3.4.0 \
    pre-commit==4.3.0 \
    # --- Snowflake connector ---
    snowflake-connector-python==3.14.0 \
    # --- data-pipelines/snowflake-export stack ---
    boto3 \
    pyarrow \
    pandas \
    numpy \
    psycopg2-binary \
    pyodbc \
    SQLAlchemy \
    cryptography \
    python-dateutil \
    pytz \
    tzdata

# Install Snowflake CLI (snow) via pipx — fully isolated venv, no conflicts
RUN /opt/mpulse-venv/bin/pip install --no-cache-dir pipx && \
    PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin \
    /opt/mpulse-venv/bin/pipx install snowflake-cli

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
ENTRYPOINT ["/usr/local/bin/mpulse-entrypoint.sh"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD claude --version && dbt --version || exit 1
