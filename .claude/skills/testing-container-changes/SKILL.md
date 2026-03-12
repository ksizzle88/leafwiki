---
name: testing-container-changes
description: Safe workflow for testing Claudio base image, devcontainer config, or infrastructure changes in a side-by-side container without disrupting the running environment.
user_invocable: true
---

# Testing Container Changes

Use this workflow whenever you modify the Claudio base image (`Dockerfile.base`), devcontainer configuration, initialization scripts, or any infrastructure that could break the running container.

## When to Use

- Changes to `Dockerfile.base` (new packages, layer modifications)
- Changes to `docker-compose.yml` (volumes, ports, environment)
- Changes to `.devcontainer/` scripts (`init-claude-settings.sh`, `docker-entrypoint.sh`)
- Changes to `cli/` (Claudio CLI commands)
- Any change that affects container startup or runtime behavior

## When NOT to Use

- Changes to `.claude/` files (settings, agents, skills, commands) — these are bind-mounted and take effect immediately
- Changes to application code in `workspace/` directories
- Documentation-only changes

## Workflow

### Step 1: Make Changes

All changes are made on the workspace bind mount (shared between containers). Edit files normally in the current container.

### Step 2: Build the Test Image

```bash
# Build fresh image with your changes baked in
docker compose build devcontainer-test
```

If the build fails, fix the issues and rebuild. The current container is unaffected.

### Step 3: Start Test Container

```bash
# Start alongside current container (uses separate volumes)
docker compose up -d devcontainer-test
```

The test container uses its own volumes (`claudio-test`, `commandhistory-test`) so it won't interfere with your active session.

### Step 4: Verify in Test Container

**Option A: Exec from current terminal**
```bash
docker compose exec devcontainer-test zsh
```

**Option B: Attach VS Code**
- Remote Explorer → Containers → devcontainer-test

### Step 5: Run Verification Checks

Inside the test container:

```bash
# Basic health checks
claude --version
codex --version
node --version
python --version
gh --version

# Claudio-specific checks
claudio verify
claudio version

# Check initialization ran correctly
echo $CLAUDE_CONFIG_DIR
ls -la ~/.claude/

# Test whatever you changed
# e.g., if you added a new package:
gh --version

# If you modified init scripts:
cat /usr/local/bin/init-claude-settings.sh | head -50
```

### Step 6: Clean Up

```bash
# Stop and remove test container
docker compose stop devcontainer-test
docker compose rm -f devcontainer-test
```

### Step 7: Apply to Main Container

Once verified, rebuild the main devcontainer:
- VS Code: Command Palette (Ctrl+Shift+P) → "Dev Containers: Rebuild Container"
- Or commit changes and let the next container rebuild pick them up

## Architecture Notes

The `devcontainer-test` service in `docker-compose.yml`:
- Extends `claudio-standalone` (same image, same build)
- Uses separate volumes: `claudio-test` and `commandhistory-test`
- Shares the workspace bind mount (sees your file changes immediately)
- Has its own labels for identification

## Troubleshooting

### Build fails
```bash
# Check build output for errors
docker compose build --no-cache devcontainer-test

# Test Dockerfile directly
docker build -f Dockerfile.base .
```

### Container won't start
```bash
# Check logs
docker compose logs devcontainer-test

# Check entrypoint
docker compose run --entrypoint bash devcontainer-test
```

### Changes not reflected
- Ensure you rebuilt the image (`docker compose build devcontainer-test`)
- Bind-mounted files (`.claude/`, workspace) reflect immediately
- Image-baked files require rebuild
