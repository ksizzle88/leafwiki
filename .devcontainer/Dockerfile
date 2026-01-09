# syntax=docker/dockerfile:1

# A small, stable base that works well with VS Code Dev Containers
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG DEBIAN_FRONTEND=noninteractive

# Install Node.js (for Claude Code), plus common dev tooling.
# We intentionally keep this minimal and rely on npm for the Claude Code CLI.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        openssh-client \
        python3 \
        python3-pip \
        jq \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js LTS (currently 20.x)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Keep npm a bit more reliable in containers
ENV npm_config_update_notifier=false \
    npm_config_fund=false
