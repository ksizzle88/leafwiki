# syntax=docker/dockerfile:1

# Layer 1: Base image (changes rarely)
# Using specific version tag for reproducibility
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Build arguments
ARG DEBIAN_FRONTEND=noninteractive
ARG NODE_VERSION=20

# Layer 2: System dependencies (changes infrequently)
# Grouped by purpose for clarity, with cache mount for performance
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        # Core utilities
        ca-certificates \
        curl \
        git \
        openssh-client \
        jq \
        wget \
        # Python tooling
        python3 \
        python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Layer 3: Node.js installation (changes infrequently)
# Pinned to LTS version for stability
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Layer 4: Environment configuration (changes rarely)
ENV npm_config_update_notifier=false \
    npm_config_fund=false \
    PYTHONUNBUFFERED=1

# Layer 4.5: Install Claude Code CLI (pinned version for reproducibility)
ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Layer 5: Copy initialization scripts (changes occasionally)
COPY .devcontainer/init-claude-settings.sh /usr/local/bin/init-claude-settings.sh
RUN chmod +x /usr/local/bin/init-claude-settings.sh

# Security: Ensure vscode user has proper permissions
RUN mkdir -p /home/vscode/.claude /home/vscode/.history \
    && chown -R vscode:vscode /home/vscode/.claude /home/vscode/.history

# Healthcheck: Verify the container is functional
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node --version && npm --version && claude --version || exit 1
