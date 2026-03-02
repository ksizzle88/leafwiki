# syntax=docker/dockerfile:1
# mpulse devcontainer
# Extends Claudio base with data engineering tools for:
#   - DPI_Analytics_DBT (dbt/Snowflake)
#   - data-pipelines/snowflake-export (Python data stack)
#   - hxi-infra (Terraform/AWS)

ARG CLAUDIO_TAG=latest
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
    unzip /tmp/terraform.zip -d /tmp && \
    mv /tmp/terraform /usr/local/bin/terraform && \
    chmod +x /usr/local/bin/terraform && \
    rm /tmp/terraform.zip

# Install AWS CLI v2 (for data-pipelines boto3 work)
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && \
    unzip /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/awscliv2.zip /tmp/aws

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

# Bake shell config into zshrc
RUN echo 'eval "$(direnv hook zsh)"' >> /etc/zsh/zshrc \
    && echo 'export CLAUDE_CODE_TASK_LIST_ID="${PROJECT_NAME:-mpulse}"' >> /etc/zsh/zshrc \
    && echo '[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh || eval "$(fzf --zsh 2>/dev/null)"' >> /etc/zsh/zshrc \
    && echo 'if [ -z "$SSH_AUTH_SOCK" ] && [ -d ~/.ssh ]; then eval "$(ssh-agent -s)" > /dev/null 2>&1 && find ~/.ssh -name "id_*" ! -name "*.pub" -exec ssh-add {} \; 2>/dev/null; fi' >> /etc/zsh/zshrc

# Create directories for volume mounts with proper ownership
RUN mkdir -p /home/dev/.config /home/dev/.local /home/dev/.cache \
    && chown -R ${DEV_USER}:${DEV_USER} /home/dev/.config /home/dev/.local /home/dev/.cache

# Copy and setup entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Set working directory (entrypoint will run as root, then drop to dev user)
WORKDIR /home/dev

# Entrypoint handles permission fixes and drops to dev user
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD claude --version && dbt --version || exit 1
