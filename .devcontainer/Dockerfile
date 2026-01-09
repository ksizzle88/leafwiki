# syntax=docker/dockerfile:1

# Layer 1: Base image (changes rarely)
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG DEBIAN_FRONTEND=noninteractive

# Layer 2: System dependencies (changes infrequently)
# Grouped by purpose for clarity
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        # Core utilities
        ca-certificates \
        curl \
        git \
        openssh-client \
        jq \
        # Python tooling
        python3 \
        python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Layer 3: Node.js installation (changes infrequently)
# Pinned to LTS version for stability
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Layer 4: Environment configuration (changes rarely)
ENV npm_config_update_notifier=false \
    npm_config_fund=false

# Layer 5: Copy initialization scripts (changes occasionally)
COPY .devcontainer/init-claude-settings.sh /usr/local/bin/init-claude-settings.sh
RUN chmod +x /usr/local/bin/init-claude-settings.sh

# Note: Claude Code CLI is installed via postCreateCommand in devcontainer.json
# This allows faster rebuilds when only Claude Code version changes
