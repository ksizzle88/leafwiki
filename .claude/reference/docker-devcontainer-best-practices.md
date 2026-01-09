# Docker & Devcontainer Best Practices Reference

A comprehensive guide for building production-ready Docker images, Docker Compose configurations, and VS Code devcontainers following 2026 best practices.

---

## Table of Contents

1. [Dockerfile Best Practices](#1-dockerfile-best-practices)
2. [.dockerignore Patterns](#2-dockerignore-patterns)
3. [Docker Compose Best Practices](#3-docker-compose-best-practices)
4. [Volume Management](#4-volume-management)
5. [Devcontainer Configuration](#5-devcontainer-configuration)
6. [Security Best Practices](#6-security-best-practices)
7. [Performance Optimization](#7-performance-optimization)
8. [Healthchecks](#8-healthchecks)
9. [Multi-Project Setup](#9-multi-project-setup)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Dockerfile Best Practices

### Layer Optimization

**Order instructions from least to most frequently changing:**

```dockerfile
# Layer 1: Base image (rarely changes)
FROM node:20-alpine

# Layer 2: System dependencies (infrequent changes)
RUN apk add --no-cache git curl

# Layer 3: Copy dependency files only
COPY package*.json ./

# Layer 4: Install dependencies
RUN npm ci --production

# Layer 5: Copy application code (frequent changes)
COPY . .

# Layer 6: Build step (if needed)
RUN npm run build

CMD ["node", "dist/index.js"]
```

**Why?** Docker caches layers. If an early layer changes, all subsequent layers must rebuild. Ordering by change frequency maximizes cache hits.

### BuildKit Cache Mounts

**Use cache mounts for package managers:**

```dockerfile
# Enable BuildKit
# syntax=docker/dockerfile:1

# Python pip cache
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

# Node npm cache
RUN --mount=type=cache,target=/root/.npm \
    npm ci --production

# APT cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y git
```

**Benefits:**
- 3-5x faster rebuilds
- Shared cache across builds
- No manual cache cleanup needed

### Multi-Stage Builds

**Separate build and runtime environments:**

```dockerfile
# Stage 1: Build
FROM node:20 AS builder
WORKDIR /app
COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY . .
RUN npm run build

# Stage 2: Production
FROM node:20-alpine
WORKDIR /app

# Copy only production dependencies
COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --production

# Copy built artifacts
COPY --from=builder /app/dist ./dist

# Run as non-root
USER node

CMD ["node", "dist/index.js"]
```

**Benefits:**
- 50-70% smaller images
- No build tools in production
- Better security (minimal attack surface)

### Base Image Selection

| Use Case | Recommended Base | Size | Security |
|----------|------------------|------|----------|
| Development | `node:20` | ~900MB | Good |
| Production (Node) | `node:20-alpine` | ~180MB | Better |
| Production (Python) | `python:3.11-slim` | ~120MB | Better |
| Maximum security | `gcr.io/distroless/nodejs20` | ~100MB | Best |

**Alpine Linux benefits:**
- Minimal size (5MB base)
- Security-focused (musl libc, fewer packages)
- Fast package manager (apk)

**Distroless benefits:**
- No shell or package manager (can't be exploited)
- Only runtime dependencies
- Smallest possible attack surface

### Build Arguments

**Make builds configurable:**

```dockerfile
ARG NODE_VERSION=20
ARG BUILD_ENV=production

FROM node:${NODE_VERSION}-alpine

ENV NODE_ENV=${BUILD_ENV}

# Use in docker-compose.yml:
# build:
#   args:
#     NODE_VERSION: 22
#     BUILD_ENV: development
```

---

## 2. .dockerignore Patterns

### Essential Exclusions

```
# Version control
.git
.gitignore
.gitattributes

# Dependencies (rebuilt in container)
node_modules/
__pycache__/
*.pyc
.venv/
venv/
vendor/

# Environment and secrets
.env
.env.*
!.env.example
*.key
*.pem
*.crt
credentials.json
secrets.yaml

# Development files
*.log
*.tmp
.vscode/
.idea/
*.swp
*.swo

# Build artifacts
dist/
build/
*.test
coverage/
.pytest_cache/

# OS files
.DS_Store
Thumbs.db
desktop.ini

# Documentation (except README)
*.md
!README.md

# Docker files themselves
Dockerfile*
docker-compose*.yml
.dockerignore

# CI/CD configs
.github/
.gitlab-ci.yml
.circleci/
```

### Performance Impact

| Build Context Size | Without .dockerignore | With .dockerignore | Improvement |
|--------------------|-----------------------|--------------------|-------------|
| Small project | 50MB | 2MB | 25x faster |
| Medium project | 500MB | 10MB | 50x faster |
| Large monorepo | 5GB | 50MB | 100x faster |

---

## 3. Docker Compose Best Practices

### Complete Service Configuration

```yaml
version: '3.8'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        NODE_VERSION: 20
    image: myapp:latest
    container_name: myapp-dev
    hostname: myapp

    volumes:
      # Source code (bind mount with cache)
      - .:/app:cached
      # Dependencies (named volume for performance)
      - node_modules:/app/node_modules
      # Persistent data
      - app-data:/app/data

    environment:
      - NODE_ENV=${NODE_ENV:-development}
      - DATABASE_URL=${DATABASE_URL}
      - TZ=${TZ:-UTC}

    # Healthcheck
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

    # Resource limits
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 1G
        reservations:
          cpus: '0.5'
          memory: 512M

    # Labels
    labels:
      com.myapp.description: "Main application service"
      com.myapp.version: "1.0.0"

    # Dependencies with health conditions
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started

    networks:
      - app-network

    restart: unless-stopped

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-network

volumes:
  node_modules:
  app-data:
  postgres-data:

networks:
  app-network:
    driver: bridge
```

### Resource Limits Guidelines

| Service Type | CPU Limit | Memory Limit | CPU Reservation | Memory Reservation |
|--------------|-----------|--------------|-----------------|-------------------|
| Web app (Node) | 1.0 | 1G | 0.5 | 512M |
| API (Python) | 2.0 | 2G | 1.0 | 1G |
| PostgreSQL | 2.0 | 4G | 1.0 | 2G |
| Redis | 0.5 | 512M | 0.25 | 256M |
| Frontend (dev) | 1.0 | 2G | 0.5 | 1G |

**Reservations** guarantee minimum resources.
**Limits** prevent resource hogging.

---

## 4. Volume Management

### Named Volumes vs Bind Mounts

**Use named volumes for:**

```yaml
volumes:
  # Package directories (huge performance boost on macOS/Windows)
  - node_modules:/app/node_modules
  - vendor:/app/vendor

  # Database data (persistence + performance)
  - postgres-data:/var/lib/postgresql/data

  # Cache directories
  - build-cache:/app/.cache

  # User settings (persist across rebuilds)
  - user-settings:/home/user/.config
```

**Use bind mounts for:**

```yaml
volumes:
  # Source code (need live editing)
  - .:/app:cached  # cached = better performance on macOS/Windows

  # Configuration files
  - ./nginx.conf:/etc/nginx/nginx.conf:ro  # ro = read-only

  # Development workflows
  - ./scripts:/scripts
```

### Performance Comparison

| Platform | Named Volume | Bind Mount (cached) | Bind Mount (default) |
|----------|--------------|---------------------|----------------------|
| Linux | ★★★★★ | ★★★★★ | ★★★★★ |
| macOS | ★★★★★ | ★★★★☆ | ★★☆☆☆ |
| Windows | ★★★★★ | ★★★★☆ | ★★☆☆☆ |

**Key principle:** Named volumes bypass host filesystem overhead, providing native container filesystem performance.

### Volume Maintenance

```bash
# List all volumes
docker volume ls

# Inspect volume
docker volume inspect claudio_claude-settings

# Remove unused volumes (frees disk space)
docker volume prune

# Remove specific volume
docker volume rm claudio_claude-settings

# Backup volume
docker run --rm -v myvolume:/data -v $(pwd):/backup \
  alpine tar czf /backup/myvolume-backup.tar.gz -C /data .

# Restore volume
docker run --rm -v myvolume:/data -v $(pwd):/backup \
  alpine tar xzf /backup/myvolume-backup.tar.gz -C /data
```

---

## 5. Devcontainer Configuration

### Complete devcontainer.json

```json
{
  "name": "Project Name",
  "dockerComposeFile": "../docker-compose.yml",
  "service": "devcontainer",
  "workspaceFolder": "/workspace",
  "remoteUser": "vscode",

  "features": {
    "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {},
    "ghcr.io/devcontainers/features/node:1": {
      "version": "20",
      "nodeGypDependencies": true
    },
    "ghcr.io/devcontainers/features/python:1": {
      "version": "3.11"
    },
    "ghcr.io/devcontainers/features/git:1": {
      "ppa": true,
      "version": "latest"
    }
  },

  "postCreateCommand": "npm install && npm run setup",
  "postStartCommand": "npm run dev",

  "customizations": {
    "vscode": {
      "extensions": [
        "dbaeumer.vscode-eslint",
        "esbenp.prettier-vscode",
        "ms-azuretools.vscode-docker",
        "github.copilot"
      ],
      "settings": {
        "editor.formatOnSave": true,
        "editor.defaultFormatter": "esbenp.prettier-vscode",
        "terminal.integrated.defaultProfile.linux": "bash"
      }
    }
  },

  "forwardPorts": [3000, 5432, 6379],
  "portsAttributes": {
    "3000": {
      "label": "Application",
      "onAutoForward": "notify"
    }
  },

  "mounts": [
    "source=${localEnv:HOME}/.ssh,target=/home/vscode/.ssh,readonly,type=bind"
  ]
}
```

### Lifecycle Commands

**postCreateCommand** (runs once on container creation):
```json
{
  "postCreateCommand": "npm install && git config --global user.name 'Your Name'"
}
```

Use for:
- Dependency installation
- Initial setup scripts
- Git configuration
- Directory initialization

**postStartCommand** (runs every container start):
```json
{
  "postStartCommand": "npm run dev"
}
```

Use for:
- Starting development servers
- Running background services
- Checking for updates

**postAttachCommand** (runs when VS Code attaches):
```json
{
  "postAttachCommand": "echo 'Welcome back!'"
}
```

Use for:
- User notifications
- Quick status checks

### Features Best Practices

Features are reusable devcontainer components that install tools:

```json
{
  "features": {
    // Docker access from inside container
    "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {},

    // Language runtimes with version control
    "ghcr.io/devcontainers/features/node:1": {
      "version": "20"
    },

    // Development tools
    "ghcr.io/devcontainers/features/github-cli:1": {},

    // Custom features
    "ghcr.io/your-org/features/custom-tool:1": {
      "option": "value"
    }
  }
}
```

**Benefits:**
- Reusable across projects
- Version-controlled tool installation
- Automatic updates
- Community marketplace

---

## 6. Security Best Practices

### Non-Root User

**Always run as non-root:**

```dockerfile
# Create user
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Set ownership
RUN chown -R appuser:appuser /app

# Switch to non-root
USER appuser

# Or use existing non-root user
USER node  # Node.js images
USER www-data  # Nginx images
```

**Why?**
- Limits damage from container breakout
- Prevents privilege escalation
- Industry standard security practice

### Secrets Management

**Never commit secrets:**

```dockerfile
# ❌ BAD - Secret in image
ENV API_KEY="secret123"

# ✅ GOOD - Runtime environment variable
# Set in docker-compose.yml:
environment:
  - API_KEY=${API_KEY}
```

**BuildKit secrets for build-time:**

```dockerfile
# Dockerfile
RUN --mount=type=secret,id=npm_token \
    echo "//registry.npmjs.org/:_authToken=$(cat /run/secrets/npm_token)" > ~/.npmrc && \
    npm install && \
    rm ~/.npmrc

# Build command
docker build --secret id=npm_token,src=$HOME/.npmrc .
```

### Security Scanning

**Scan images regularly:**

```bash
# Using Trivy (open source)
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image myapp:latest

# Output
myapp:latest (alpine 3.18.4)
==========================
Total: 0 (UNKNOWN: 0, LOW: 0, MEDIUM: 0, HIGH: 0, CRITICAL: 0)

# Using Snyk (commercial, more features)
snyk container test myapp:latest
```

**Automate scanning in CI/CD:**

```yaml
# .github/workflows/security.yml
name: Security Scan
on: [push]
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build image
        run: docker build -t myapp:${{ github.sha }} .
      - name: Run Trivy
        run: docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
          aquasec/trivy image --exit-code 1 --severity HIGH,CRITICAL myapp:${{ github.sha }}
```

### Additional Security Measures

```dockerfile
# Read-only root filesystem
docker run --read-only myapp

# Drop capabilities
docker run --cap-drop=ALL --cap-add=NET_BIND_SERVICE myapp

# No new privileges
docker run --security-opt=no-new-privileges myapp

# Resource limits (prevent DoS)
deploy:
  resources:
    limits:
      cpus: '1.0'
      memory: 1G
```

---

## 7. Performance Optimization

### BuildKit Optimization

**Enable BuildKit globally:**

```bash
# ~/.docker/daemon.json
{
  "features": {
    "buildkit": true
  }
}

# Or per-build
DOCKER_BUILDKIT=1 docker build .
```

**BuildKit features:**
- Parallel build stages
- Cache mounts
- Secrets management
- SSH forwarding
- Advanced layer caching

### Layer Caching Strategies

```dockerfile
# ❌ BAD - Changes to code invalidate dependency layer
COPY . .
RUN npm install

# ✅ GOOD - Dependency layer cached unless package.json changes
COPY package*.json ./
RUN npm install
COPY . .
```

### Multi-Stage Build Optimization

```dockerfile
# Use specific stages for different purposes
FROM node:20 AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM node:20 AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=deps /app/node_modules ./node_modules
USER node
CMD ["node", "dist/index.js"]
```

### Build Cache Analysis

```bash
# See cache hits/misses
DOCKER_BUILDKIT=1 docker build --progress=plain .

# Analyze layer sizes
docker history myapp:latest

# Clean build cache
docker builder prune
```

---

## 8. Healthchecks

### Application Healthchecks

```dockerfile
# In Dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1
```

```yaml
# In docker-compose.yml
healthcheck:
  test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

### Database Healthchecks

```yaml
# PostgreSQL
healthcheck:
  test: ["CMD", "pg_isready", "-U", "postgres"]
  interval: 10s
  timeout: 5s
  retries: 5
  start_period: 30s

# MySQL
healthcheck:
  test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
  interval: 10s
  timeout: 5s
  retries: 5

# Redis
healthcheck:
  test: ["CMD", "redis-cli", "ping"]
  interval: 10s
  timeout: 5s
  retries: 5

# MongoDB
healthcheck:
  test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
  interval: 10s
  timeout: 5s
  retries: 5
```

### Healthcheck Best Practices

| Parameter | Recommendation | Reasoning |
|-----------|----------------|-----------|
| interval | 30s for apps, 10s for DBs | Balance monitoring vs overhead |
| timeout | 10s for apps, 5s for DBs | Enough time for response |
| retries | 3-5 | Avoid false positives from transient issues |
| start_period | 40s+ for apps, 30s for DBs | Account for initialization time |

**Test functionality, not just process existence:**

```bash
# ❌ BAD - Only checks if process exists
HEALTHCHECK CMD ps aux | grep node

# ✅ GOOD - Tests actual functionality
HEALTHCHECK CMD curl -f http://localhost:3000/health || exit 1
```

### Dependency Health Conditions

```yaml
services:
  app:
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
```

**Conditions:**
- `service_started`: Wait for container to start
- `service_healthy`: Wait for healthcheck to pass
- `service_completed_successfully`: Wait for one-shot containers

---

## 9. Multi-Project Setup

### Approach 1: Multiple .devcontainer Folders

```
monorepo/
├── .devcontainer/              # Root configuration
│   ├── Dockerfile
│   └── devcontainer.json
├── frontend/
│   └── .devcontainer/          # Frontend-specific
│       └── devcontainer.json
└── backend/
    └── .devcontainer/          # Backend-specific
        └── devcontainer.json
```

### Approach 2: Docker Compose with Multiple Services

```yaml
# docker-compose.yml
version: '3.8'

services:
  frontend:
    build: ./frontend
    volumes:
      - ./frontend:/app
    networks:
      - dev-network

  backend:
    build: ./backend
    volumes:
      - ./backend:/app
    depends_on:
      - db
    networks:
      - dev-network

  db:
    image: postgres:16-alpine
    volumes:
      - db-data:/var/lib/postgresql/data
    networks:
      - dev-network

networks:
  dev-network:

volumes:
  db-data:
```

```json
// .devcontainer/devcontainer.json
{
  "name": "Full Stack",
  "dockerComposeFile": "../docker-compose.yml",
  "service": "frontend",  // or "backend"
  "workspaceFolder": "/app"
}
```

### Approach 3: Shared Base Image

```dockerfile
# .devcontainer/base/Dockerfile
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y git curl

# .devcontainer/frontend/Dockerfile
FROM base:latest
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash -

# .devcontainer/backend/Dockerfile
FROM base:latest
RUN apt-get install -y python3-pip
```

---

## 10. Troubleshooting

### Common Issues

**Issue: Container won't start**
```bash
# Check logs
docker logs container-name

# Check container status
docker ps -a

# Inspect container
docker inspect container-name

# Check healthcheck
docker inspect container-name | grep -A 10 Health
```

**Issue: Slow performance on macOS/Windows**
```yaml
# Use cached bind mounts
volumes:
  - .:/app:cached

# Use named volumes for dependencies
volumes:
  - node_modules:/app/node_modules

# Allocate more resources in Docker Desktop settings
```

**Issue: Build cache not working**
```bash
# Check BuildKit is enabled
docker buildx ls

# Use --no-cache to force rebuild
docker build --no-cache .

# Check .dockerignore excludes changing files
cat .dockerignore
```

**Issue: Permission denied errors**
```dockerfile
# Ensure non-root user owns files
RUN chown -R vscode:vscode /app

# Or match host user ID (Linux only)
ARG USER_UID=1000
ARG USER_GID=1000
RUN groupmod -g $USER_GID vscode && \
    usermod -u $USER_UID -g $USER_GID vscode
```

**Issue: Out of disk space**
```bash
# Remove unused containers
docker container prune

# Remove unused volumes
docker volume prune

# Remove unused images
docker image prune -a

# Full cleanup (CAREFUL - removes everything)
docker system prune -a --volumes
```

---

## Quick Reference

### Essential Commands

```bash
# Build with BuildKit
DOCKER_BUILDKIT=1 docker build -t myapp .

# Build with docker-compose
docker-compose build

# Start services
docker-compose up -d

# View logs
docker-compose logs -f

# Execute command in container
docker-compose exec service-name bash

# Restart service
docker-compose restart service-name

# Stop and remove
docker-compose down

# Stop and remove with volumes
docker-compose down -v

# Check resource usage
docker stats

# Check healthcheck status
docker ps

# Inspect container details
docker inspect container-name
```

### Performance Checklist

- [ ] Use BuildKit cache mounts
- [ ] Order Dockerfile layers by change frequency
- [ ] Use .dockerignore to exclude unnecessary files
- [ ] Use multi-stage builds to reduce image size
- [ ] Use alpine or distroless base images
- [ ] Use named volumes for package directories
- [ ] Use cached bind mounts on macOS/Windows
- [ ] Set appropriate resource limits
- [ ] Enable BuildKit globally

### Security Checklist

- [ ] Run as non-root user
- [ ] Never commit secrets to images
- [ ] Use BuildKit secrets for build-time secrets
- [ ] Scan images with Trivy or Snyk
- [ ] Pin base image versions
- [ ] Use .dockerignore to exclude secrets
- [ ] Set resource limits
- [ ] Enable read-only root filesystem (where possible)
- [ ] Drop unnecessary capabilities
- [ ] Use healthchecks

---

## Resources

**Docker:**
- [Docker Documentation](https://docs.docker.com/)
- [Dockerfile Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [BuildKit Documentation](https://docs.docker.com/build/buildkit/)

**Docker Compose:**
- [Compose File Reference](https://docs.docker.com/compose/compose-file/)
- [Compose Best Practices](https://docs.docker.com/compose/production/)

**Devcontainers:**
- [Dev Containers Documentation](https://code.visualstudio.com/docs/devcontainers/containers)
- [Dev Container Features](https://containers.dev/features)
- [Dev Container Specification](https://containers.dev/)

**Security:**
- [Trivy Scanner](https://github.com/aquasecurity/trivy)
- [Snyk Container Security](https://snyk.io/product/container-vulnerability-management/)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)

**Performance:**
- [Docker Build Cache](https://docs.docker.com/build/cache/)
- [Multi-Stage Builds](https://docs.docker.com/build/building/multi-stage/)
- [BuildKit Cache Backends](https://docs.docker.com/build/cache/backends/)
