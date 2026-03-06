# Task 21: Add build provenance stamps to Claudio base image

## Summary

Add OCI-standard image labels and a shell-sourceable `/etc/claudio-release` file to every Claudio base image build, so that any running container can report exactly what code produced it. This requires changes across all four build paths (Dockerfile.base, build-base.sh, GitHub Actions workflow, pre-push hook), the docker-compose.yml build args, and the `claudio version` CLI command. The implementation uses Dockerfile ARGs with safe defaults so that builds always succeed even without explicit `--build-arg` flags.

## Research Findings

### Dockerfile.base (`/workspace/Dockerfile.base`, 194 lines)

- **Zero existing LABEL instructions.** No OCI labels, no custom labels.
- **Existing ARGs** are on lines 14-30, covering user config (DEV_USER, DEV_UID, etc.), tool versions (NODE_VERSION, ZSH_IN_DOCKER_VERSION), and git config (GIT_USER_EMAIL, etc.).
- **Last meaningful layer** is the HEALTHCHECK on lines 193-194. The ENTRYPOINT is on line 190.
- **Layer ordering concern**: ARGs bust the cache for all subsequent layers. The new provenance ARGs (BUILD_COMMIT, BUILD_DATE, etc.) change on every build. They MUST be declared as late as possible -- immediately before the LABEL and `/etc/claudio-release` RUN -- to avoid busting the cache for all prior layers.
- The Dockerfile uses `USER ${DEV_USER}` / `USER root` toggling (e.g., lines 115-117, 126-138, 175-185). The `/etc/claudio-release` RUN must execute as root (the default before ENTRYPOINT).

### build-base.sh (`/workspace/build-base.sh`, 165 lines)

- **Docker build command** is on lines 117-126. It passes `--build-arg` for NODE_VERSION, ZSH_IN_DOCKER_VERSION, GIT_USER_EMAIL, GIT_USER_NAME, GIT_GPG_SIGN, GIT_SIGNING_KEY.
- **Branch detection** already exists on line 59: `CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | sed 's/[^a-zA-Z0-9._-]/-/g')`.
- No existing git SHA, dirty check, or timestamp logic.
- The `.env` file is loaded on line 72-78 via `export $(grep -v '^#' .env | grep -v '^$' | xargs)`.

### GitHub Actions workflow (`/workspace/.github/workflows/build-push-image.yml`, 108 lines)

- **Uses `docker/metadata-action@v5`** (lines 43-57) which auto-generates OCI labels like `org.opencontainers.image.revision`, `org.opencontainers.image.created`, etc.
- **`docker/build-push-action@v6`** is on lines 59-70. It currently passes NO `build-args` at all.
- The metadata-action labels are applied via `labels: ${{ steps.meta.outputs.labels }}` on line 67 -- these are external Docker labels that override same-named Dockerfile LABELs.
- **Coexistence strategy**: Dockerfile LABELs provide defaults for local/pre-push builds. In CI, metadata-action labels override them (Docker applies external labels after Dockerfile LABELs). However, `/etc/claudio-release` inside the image requires build-args since it is baked in at build time.

### claudio version command (`/workspace/cli/commands/version.sh`, 161 lines)

- `show_version_info()` function is at lines 71-117.
- **Human-readable output** (lines 88-114): Uses `print_header`, `print_table_row` from `/workspace/cli/lib/output.sh`.
- **JSON output** (lines 72-87): Builds a JSON heredoc with tool versions.
- **CLAUDIO_VERSION** is imported from `/workspace/cli/lib/common.sh` line 6 as `readonly CLAUDIO_VERSION="1.0.0"`.
- The command already checks `in_container()` on line 107, which returns true if `/.dockerenv` or `/run/.containerenv` exists.
- **Pattern to follow**: The existing code sections are "Claudio Platform:" and "Development Tools:" and "Container Tools:". The new build provenance section should appear as "Build Information:" after "Claudio Platform:" and before "Development Tools:".

### cli/lib/common.sh (`/workspace/cli/lib/common.sh`, 211 lines)

- `CLAUDIO_VERSION="1.0.0"` on line 6.
- `in_container()` function on lines 127-129.
- `has_command()` on lines 104-106.
- Output helpers: `error()`, `warn()`, `success()`, `info()`, `log()`, `verbose()`.

### cli/lib/output.sh (`/workspace/cli/lib/output.sh`, 227 lines)

- `print_table_row()` on lines 220-226: Takes 3 args, formats as `printf "  %-30s %-15s %s\n"`.
- `print_header()` on lines 13-18.
- `print_json()` on lines 162-168: Pipes through `jq` if available.

### Pre-push hook (`/workspace/.devcontainer/hooks/pre-push`, 234 lines)

- **COMMIT_SHA** computed on line 104: `COMMIT_SHA=$(git rev-parse --short=7 HEAD)`.
- **GIT_TAG** computed on line 107: `GIT_TAG=$(git describe --exact-match --tags 2>/dev/null || echo "")`.
- **BRANCH** computed on line 83: `BRANCH=$(git rev-parse --abbrev-ref HEAD | sed 's/[^a-zA-Z0-9._-]/-/g')`.
- **BUILD_CMD** assembled on lines 177-190. Tags are `-t` flags appended in a loop (lines 185-187). The Dockerfile is specified as `-f Dockerfile.base .` on line 190.
- No existing `--build-arg` flags beyond BUILDKIT_INLINE_CACHE on line 178.

### docker-compose.yml (`/workspace/docker-compose.yml`, 137 lines)

- Build args are on lines 13-23 under `services.claudio-standalone.build.args`.
- Currently passes: DEV_USER, DEV_UID, DEV_GID, DEV_PASSWORD, NODE_VERSION, ZSH_IN_DOCKER_VERSION, GIT_USER_EMAIL, GIT_USER_NAME, GIT_GPG_SIGN, GIT_SIGNING_KEY.

### install-claudio.sh (`/workspace/.devcontainer/install-claudio.sh`, 113 lines)

- This is the multi-stage build installation script. It does NOT need to copy `/etc/claudio-release` because that file will already be in the base image layer. When used in multi-stage pattern (`FROM claudio-base:latest AS claudio`), the file exists in the claudio stage and would need explicit `COPY --from=claudio /etc/claudio-release /etc/claudio-release` if the consumer wants it. However, this is a nice-to-have, not required for this task.

## Files to Change

| File | Action | What Changes |
|------|--------|-------------|
| `/workspace/Dockerfile.base` | Modify | Add provenance ARGs (after all layers, before ENTRYPOINT), LABEL instructions, and RUN to write `/etc/claudio-release` |
| `/workspace/build-base.sh` | Modify | Compute git SHA (with dirty check), branch, tag, timestamp, and pass as `--build-arg` flags |
| `/workspace/.github/workflows/build-push-image.yml` | Modify | Add `build-args` to `docker/build-push-action` step with GitHub Actions context variables |
| `/workspace/.devcontainer/hooks/pre-push` | Modify | Add `--build-arg` flags to BUILD_CMD using existing COMMIT_SHA, BRANCH, GIT_TAG variables |
| `/workspace/docker-compose.yml` | Modify | Add BUILD_COMMIT, BUILD_DATE, BUILD_VERSION, BUILD_BRANCH args (with safe defaults) |
| `/workspace/cli/commands/version.sh` | Modify | Read `/etc/claudio-release` and display build provenance in both human and JSON output |

**Total: 6 files to modify, 0 files to create, 0 files to delete.**

## Implementation Steps

### Step 1: Add provenance ARGs, LABELs, and `/etc/claudio-release` to Dockerfile.base

**File**: `/workspace/Dockerfile.base`

**What to do**: Insert new content between the current line 185 (`USER root`) and line 187 (`# Runtime configuration`). The provenance ARGs must come AFTER all cacheable layers to avoid cache busting.

**Insert after line 185** (after `USER root` from the git config layer, before `# Runtime configuration` comment on line 187):

```dockerfile
# Layer 16: Build provenance (last layer before runtime - ARGs change every build)
ARG BUILD_COMMIT=unknown
ARG BUILD_DATE=unknown
ARG BUILD_VERSION=dev
ARG BUILD_BRANCH=unknown
ARG BUILD_BUILDER=unknown

LABEL org.opencontainers.image.revision="${BUILD_COMMIT}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${BUILD_VERSION}" \
      org.opencontainers.image.source="https://github.com/ksizzle88/claudio" \
      org.opencontainers.image.title="Claudio" \
      org.opencontainers.image.description="Production-ready devcontainer for Claude Code development"

RUN echo "BUILD_COMMIT=${BUILD_COMMIT}" > /etc/claudio-release \
    && echo "BUILD_DATE=${BUILD_DATE}" >> /etc/claudio-release \
    && echo "BUILD_VERSION=${BUILD_VERSION}" >> /etc/claudio-release \
    && echo "BUILD_BRANCH=${BUILD_BRANCH}" >> /etc/claudio-release \
    && echo "BUILD_BUILDER=${BUILD_BUILDER}" >> /etc/claudio-release
```

**Key details**:
- ARG defaults are `unknown` / `dev` so the image always builds, even without any `--build-arg`.
- The ARG block is intentionally placed AFTER Layer 15 (git config) because ARGs that change on every build invalidate the cache for all subsequent layers.
- The LABEL instruction uses OCI standard keys (`org.opencontainers.image.*`).
- The RUN writes a simple `KEY=VALUE` file (like `/etc/os-release`) that can be sourced in shell scripts.
- The RUN must execute as root (which it is at this point -- line 185 is `USER root`).

**Gotchas**:
- Do NOT place the ARG block near the top of the file (lines 14-30) -- this would bust the cache for ALL subsequent layers on every build.
- The HEALTHCHECK on lines 193-194 should remain as the very last instruction. The provenance layer goes between the git config and the runtime section.
- Make sure the `# Runtime configuration` comment and everything after it (WORKDIR, ENTRYPOINT, HEALTHCHECK) remain unchanged and come AFTER this new block.

**Verification**:
```bash
docker build -f Dockerfile.base -t claudio-test:provenance . 2>&1 | tail -5
docker run --rm claudio-test:provenance cat /etc/claudio-release
docker inspect claudio-test:provenance --format '{{index .Config.Labels "org.opencontainers.image.revision"}}'
```

---

### Step 2: Update build-base.sh to compute and pass provenance build args

**File**: `/workspace/build-base.sh`

**What to do**: Add provenance computation logic after the `.env` loading section (after line 78), and add `--build-arg` flags to the docker build command (lines 117-126).

**2a. Insert after line 86** (after the `GIT_USER_NAME` echo block, before the registry auth section starting at line 88):

```bash
# Compute build provenance
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BUILD_BRANCH="${CURRENT_BRANCH:-unknown}"
BUILD_BUILDER=$(hostname 2>/dev/null || echo "unknown")

# Compute commit SHA with dirty check
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    BUILD_COMMIT=$(git rev-parse --short=7 HEAD)
    if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet HEAD 2>/dev/null; then
        BUILD_COMMIT="${BUILD_COMMIT}-dirty"
    fi
else
    BUILD_COMMIT="unknown"
fi

# Compute version from git tag
BUILD_VERSION=$(git describe --exact-match --tags 2>/dev/null || echo "dev")

echo "  Build commit: $BUILD_COMMIT"
echo "  Build date: $BUILD_DATE"
echo "  Build version: $BUILD_VERSION"
echo "  Build branch: $BUILD_BRANCH"
```

**Key detail about CURRENT_BRANCH**: The variable `CURRENT_BRANCH` is already computed on line 59 and is available here. If the script was invoked outside a git repo, it falls back to `"dev"` (see lines 63-66). We use `${CURRENT_BRANCH:-unknown}` for safety but it will always be set by the time we reach this point.

**2b. Add build-arg flags to the docker build command.** The current build command is on lines 117-126. Add 5 new `--build-arg` lines before the final `.` on line 126:

```bash
docker build \
    -f Dockerfile.base \
    "${BUILD_TAGS[@]}" \
    --build-arg NODE_VERSION="${NODE_VERSION:-22}" \
    --build-arg ZSH_IN_DOCKER_VERSION="${ZSH_IN_DOCKER_VERSION:-1.2.0}" \
    --build-arg GIT_USER_EMAIL="${GIT_USER_EMAIL:-}" \
    --build-arg GIT_USER_NAME="${GIT_USER_NAME:-}" \
    --build-arg GIT_GPG_SIGN="${GIT_GPG_SIGN:-false}" \
    --build-arg GIT_SIGNING_KEY="${GIT_SIGNING_KEY:-}" \
    --build-arg BUILD_COMMIT="${BUILD_COMMIT}" \
    --build-arg BUILD_DATE="${BUILD_DATE}" \
    --build-arg BUILD_VERSION="${BUILD_VERSION}" \
    --build-arg BUILD_BRANCH="${BUILD_BRANCH}" \
    --build-arg BUILD_BUILDER="${BUILD_BUILDER}" \
    .
```

**2c. Update verification echo at end of script.** After line 165 (the `git config --global --list` echo), add:

```bash
echo "  docker run --rm claudio-base:$PRIMARY_TAG cat /etc/claudio-release"
```

**Gotchas**:
- `CURRENT_BRANCH` is sanitized for Docker tags (line 59) -- slashes become dashes. This is fine for BUILD_BRANCH.
- The `git diff --quiet` check returns exit code 1 if there are changes, which is why we negate it with `!`.
- Both staged (`--cached`) and unstaged changes should trigger the `-dirty` suffix.
- `hostname` may not be available in all environments; the `|| echo "unknown"` fallback handles this.

**Verification**:
```bash
./build-base.sh --tags provenance-test 2>&1 | grep "Build commit:"
docker run --rm claudio-base:provenance-test cat /etc/claudio-release
```

---

### Step 3: Update GitHub Actions workflow to pass build-args

**File**: `/workspace/.github/workflows/build-push-image.yml`

**What to do**: Add a `build-args` section to the `docker/build-push-action` step (lines 59-70).

**Modify the build-and-push step** (the `with:` block starting at line 62) to add `build-args`:

```yaml
      - name: Build and push Docker image
        id: push
        uses: docker/build-push-action@v6
        with:
          context: .
          file: Dockerfile.base
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          build-args: |
            BUILD_COMMIT=${{ github.sha }}
            BUILD_DATE=${{ github.event.head_commit.timestamp }}
            BUILD_VERSION=${{ github.ref_type == 'tag' && github.ref_name || 'dev' }}
            BUILD_BRANCH=${{ github.ref_name }}
            BUILD_BUILDER=github-actions
          cache-from: type=gha
          cache-to: type=gha,mode=max
          provenance: false
```

**Key details**:
- `github.sha` provides the full 40-character SHA (not 7-char short). This is intentional for CI -- more precise provenance.
- `github.event.head_commit.timestamp` provides the commit timestamp in ISO 8601 format. This is preferable to the build start time since it is deterministic.
- `github.ref_type == 'tag' && github.ref_name || 'dev'` uses GitHub Actions expression syntax to set BUILD_VERSION to the tag name (e.g., `v1.2.3`) when pushing a tag, or `dev` otherwise.
- `github.ref_name` gives the branch or tag name (e.g., `main`, `develop`, `v1.2.3`).
- The `labels:` from metadata-action will OVERRIDE the Dockerfile LABEL instructions with the same keys. This is the correct OCI behavior -- external labels take precedence.

**Gotchas**:
- `build-args` must be placed within the `with:` block. Order within `with:` does not matter, but for readability place it after `labels:` and before `cache-from:`.
- The `${{ github.event.head_commit.timestamp }}` may be empty on `workflow_dispatch` events. The Dockerfile ARG default of `unknown` handles this gracefully.
- For tag pushes, `github.ref_name` will be the tag name (e.g., `v1.2.3`), not a branch. This is correct for BUILD_BRANCH in that context.

**Verification**: Push to a branch and check the Actions log for the build-args being passed. Then:
```bash
docker pull ghcr.io/ksizzle88/claudio:sha-<short>
docker run --rm ghcr.io/ksizzle88/claudio:sha-<short> cat /etc/claudio-release
```

---

### Step 4: Update pre-push hook to pass build-args

**File**: `/workspace/.devcontainer/hooks/pre-push`

**What to do**: Add `--build-arg` flags to the BUILD_CMD assembly block (lines 177-190).

**Insert after line 190** (after `BUILD_CMD="$BUILD_CMD -f Dockerfile.base ."` but rewritten to include build-args BEFORE the `-f` flag). Actually, the build args should be added after the cache flags and before the tag loop or after the tag loop, before the `-f` flag. The cleanest approach: add them after the tag loop (line 187) and before line 190.

**Insert between lines 187 and 190** (after the tag loop `done`, before `BUILD_CMD="$BUILD_CMD -f Dockerfile.base ."`):

```bash
# Add build provenance args
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BUILD_BUILDER=$(hostname 2>/dev/null || echo "unknown")
DIRTY_CHECK=""
if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet HEAD 2>/dev/null; then
    DIRTY_CHECK="-dirty"
fi
BUILD_CMD="$BUILD_CMD --build-arg BUILD_COMMIT=${COMMIT_SHA}${DIRTY_CHECK}"
BUILD_CMD="$BUILD_CMD --build-arg BUILD_DATE=${BUILD_DATE}"
BUILD_CMD="$BUILD_CMD --build-arg BUILD_VERSION=${GIT_TAG:-dev}"
BUILD_CMD="$BUILD_CMD --build-arg BUILD_BRANCH=${BRANCH}"
BUILD_CMD="$BUILD_CMD --build-arg BUILD_BUILDER=${BUILD_BUILDER}"
```

**Key details**:
- `COMMIT_SHA` is already computed on line 104 (7-char short SHA).
- `GIT_TAG` is already computed on line 107 (empty string if no exact tag match).
- `BRANCH` is already computed on line 83.
- The dirty check logic here mirrors what we added in build-base.sh.
- `${GIT_TAG:-dev}` uses the existing variable: if it's an empty string (no tag), defaults to `dev`.

**Gotchas**:
- The BUILD_CMD is assembled as a string and later evaluated with `eval` (line 193). Build arg values must not contain spaces or special characters that would break eval. Git SHAs, branch names (already sanitized), hostnames, and ISO dates are all safe.
- Do NOT add the `--build-arg` lines after the `-f Dockerfile.base .` line, as that terminates the command.

**Verification**: Push a feature branch and check the build output for the build-arg lines.

---

### Step 5: Update docker-compose.yml to pass build-args

**File**: `/workspace/docker-compose.yml`

**What to do**: Add provenance build args to the `args:` section under `services.claudio-standalone.build` (lines 13-23).

**Add after line 23** (after `GIT_SIGNING_KEY: ${GIT_SIGNING_KEY:-}`):

```yaml
        BUILD_COMMIT: ${BUILD_COMMIT:-unknown}
        BUILD_DATE: ${BUILD_DATE:-unknown}
        BUILD_VERSION: ${BUILD_VERSION:-dev}
        BUILD_BRANCH: ${BUILD_BRANCH:-unknown}
        BUILD_BUILDER: ${BUILD_BUILDER:-unknown}
```

**Key details**:
- Uses `${VAR:-default}` syntax so builds work without setting these env vars.
- Users building via docker-compose will get `unknown`/`dev` stamps unless they set the env vars.
- These could optionally be set in `.env` but that is not required for this task.

**Gotchas**:
- Indentation must be 8 spaces (to match the existing args on lines 14-23).
- The defaults match the ARG defaults in the Dockerfile.

**Verification**:
```bash
docker compose config 2>&1 | grep BUILD_
```

---

### Step 6: Update `claudio version` to display build provenance

**File**: `/workspace/cli/commands/version.sh`

**What to do**: Modify `show_version_info()` (lines 71-117) to read `/etc/claudio-release` and display build provenance when running inside a container.

**6a. Add a helper function** before `show_version_info()` (insert before line 71):

```bash
#######################################
# Read build provenance from /etc/claudio-release
# Outputs:
#   Sets BUILD_COMMIT, BUILD_DATE, BUILD_VERSION,
#   BUILD_BRANCH, BUILD_BUILDER variables
# Returns:
#   0 if file exists and was read, 1 otherwise
#######################################
read_build_provenance() {
    local release_file="/etc/claudio-release"
    if [[ -f "${release_file}" ]]; then
        # Source the file to get KEY=VALUE pairs
        # shellcheck source=/dev/null
        source "${release_file}"
        return 0
    fi
    return 1
}
```

**6b. Update the human-readable output section** in `show_version_info()`. After the "Claudio Platform:" section (after line 94 `echo ""`), insert:

```bash
        # Build provenance (only in containers with /etc/claudio-release)
        if read_build_provenance; then
            echo "Build Information:"
            print_table_row "  Commit" "${BUILD_COMMIT:-unknown}" ""
            print_table_row "  Date" "${BUILD_DATE:-unknown}" ""
            print_table_row "  Version" "${BUILD_VERSION:-dev}" ""
            print_table_row "  Branch" "${BUILD_BRANCH:-unknown}" ""
            print_table_row "  Builder" "${BUILD_BUILDER:-unknown}" ""
            echo ""
        fi
```

**6c. Update the JSON output section** (lines 72-87). Replace the JSON heredoc to include build provenance:

```bash
    if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
        # JSON output
        local json
        local build_json="{}"
        if read_build_provenance; then
            build_json=$(cat <<EOF
{
    "commit": "${BUILD_COMMIT:-unknown}",
    "date": "${BUILD_DATE:-unknown}",
    "version": "${BUILD_VERSION:-dev}",
    "branch": "${BUILD_BRANCH:-unknown}",
    "builder": "${BUILD_BUILDER:-unknown}"
  }
EOF
)
        fi
        json=$(cat <<EOF
{
  "claudio": "${CLAUDIO_VERSION}",
  "build": ${build_json},
  "claude": "$(get_version claude)",
  "node": "$(get_version node)",
  "python": "$(get_version python || get_version python3)",
  "gh": "$(get_version gh | awk '{print $3}')",
  "git": "$(get_version git | awk '{print $3}')",
  "docker": "$(get_version docker | awk '{print $3}')"
}
EOF
)
        print_json "${json}"
```

**Key details**:
- `read_build_provenance` sources the file, which sets `BUILD_COMMIT`, `BUILD_DATE`, etc. as shell variables.
- The `${BUILD_COMMIT:-unknown}` fallback handles the case where the file exists but a key is missing.
- The function returns 1 if the file does not exist (e.g., running outside a container), so the "Build Information:" section is conditionally displayed.
- The JSON output adds a `"build"` object. When outside a container (no `/etc/claudio-release`), it falls back to `{}`.

**Gotchas**:
- The `source` command in `read_build_provenance()` executes the file content. The `/etc/claudio-release` file only contains `KEY=VALUE` lines with no special characters, so this is safe.
- The variables `BUILD_COMMIT`, `BUILD_DATE`, etc. from `read_build_provenance()` could collide with variables if the same names were used elsewhere. They are not currently used in any other context within the version command.
- JSON heredocs with embedded command substitution (`$(...)`) require careful quoting. The existing pattern in the file (lines 75-86) already uses this approach.

**Verification**:
```bash
# Inside a container with /etc/claudio-release
claudio version
claudio version --json

# Outside a container (no /etc/claudio-release) -- should show no Build Information section
claudio version
```

---

## Testing and Verification

### Pre-flight checks

1. **Dockerfile syntax check**:
   ```bash
   docker build -f Dockerfile.base --check . 2>&1
   ```

2. **YAML syntax check** (GitHub Actions):
   ```bash
   python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-push-image.yml'))"
   ```

3. **docker-compose validation**:
   ```bash
   docker compose config --quiet
   ```

### Build and verify (local)

4. **Build with provenance** (clean commit):
   ```bash
   ./build-base.sh --tags provenance-test
   ```

5. **Verify /etc/claudio-release**:
   ```bash
   docker run --rm claudio-base:provenance-test cat /etc/claudio-release
   ```
   **Expected output** (example):
   ```
   BUILD_COMMIT=86a5795
   BUILD_DATE=2026-03-06T18:30:00Z
   BUILD_VERSION=dev
   BUILD_BRANCH=develop
   BUILD_BUILDER=my-hostname
   ```

6. **Verify OCI labels**:
   ```bash
   docker inspect claudio-base:provenance-test --format '{{json .Config.Labels}}' | jq .
   ```
   **Expected**: JSON object containing `org.opencontainers.image.revision`, `.created`, `.version`, `.source`, `.title`, `.description`.

7. **Verify claudio version command**:
   ```bash
   docker run --rm claudio-base:provenance-test claudio version
   docker run --rm claudio-base:provenance-test claudio version --json
   ```
   **Expected**: Human-readable output includes "Build Information:" section. JSON output includes `"build"` object.

8. **Verify dirty build detection** (make a local change, don't commit):
   ```bash
   echo "# test" >> /tmp/test-dirty
   cp /tmp/test-dirty /workspace/test-dirty
   ./build-base.sh --tags dirty-test 2>&1 | grep "Build commit:"
   # Expected: Build commit: 86a5795-dirty
   rm /workspace/test-dirty
   ```

9. **Verify docker-compose build**:
   ```bash
   BUILD_COMMIT=test123 BUILD_DATE=2026-01-01T00:00:00Z BUILD_VERSION=v1.0.0 BUILD_BRANCH=main BUILD_BUILDER=test docker compose config 2>&1 | grep -A5 BUILD_
   ```

### Edge case checks

10. **Build without git** (simulated):
    The Dockerfile ARG defaults (`unknown`/`dev`) ensure the build succeeds even if no build args are passed.

11. **Cache efficiency**: After two consecutive builds with the same code but different timestamps, only the final provenance layer should be rebuilt (not the entire image).

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Cache busting if ARGs placed too early in Dockerfile | High -- every build rebuilds from scratch | ARGs are placed immediately before the LABEL/RUN, as the last layer before ENTRYPOINT. All heavy layers (apt, node, npm, zsh) come before. |
| `eval $BUILD_CMD` in pre-push hook breaking on special characters in build-arg values | Medium -- pre-push hook fails silently | All values are sanitized: SHAs are hex, branches are already sanitized (line 83), dates use ISO format, hostnames are DNS-safe. |
| `source /etc/claudio-release` in version.sh executing malicious code | Low -- file is written during Docker build by us | The file is created by our own RUN instruction with controlled values. No user input reaches it. |
| `github.event.head_commit.timestamp` empty on workflow_dispatch | Low -- BUILD_DATE shows as empty string | Dockerfile ARG default is `unknown`, so it degrades gracefully. Could add a fallback step in the workflow if desired. |
| Multi-stage builds (install-claudio.sh) don't automatically get /etc/claudio-release | Low -- only affects consumers who use multi-stage pattern | Document that consumers should add `COPY --from=claudio /etc/claudio-release /etc/claudio-release` to their Dockerfiles. Not a blocker for this task. |

## Open Questions

1. **Should `BUILD_DATE` in GitHub Actions use the commit timestamp (`github.event.head_commit.timestamp`) or the build timestamp?** The plan uses commit timestamp for determinism (same commit = same date), but build timestamp might be more intuitive. The implementer should follow the plan unless directed otherwise.

2. **Should the `claudio version` command also show provenance when NOT inside a container?** Currently the plan only shows "Build Information:" when `/etc/claudio-release` exists (i.e., inside a container). If the CLI is installed standalone (outside Docker), there is no release file, so the section is hidden. This seems correct but worth confirming.

3. **Should `install-claudio.sh` be updated to copy `/etc/claudio-release` for multi-stage builds?** This is tangential to the core task. The plan does not include it, but it could be added as a follow-up task.

# Task 21: Add Build Provenance Stamps to Claudio Base Image

## Summary

Add OCI-standard labels and a `/etc/claudio-release` metadata file to every Claudio Docker image build so that any running container can report exactly what source code, commit, branch, and build timestamp produced it. This involves modifying `Dockerfile.base` to accept provenance build-args and write them as labels and a file, updating all three build paths (`build-base.sh`, GitHub Actions workflow, pre-push hook) to compute and inject the provenance data, updating `docker-compose.yml` to pass through the new build-args, and enhancing the `claudio version` command to display build provenance when running inside a container.

## Research Findings

### Dockerfile.base (`/workspace/Dockerfile.base`)
- **195 lines total**, no existing `LABEL` instructions anywhere.
- Existing build ARGs are on lines 14-30 (user config, tool versions, git config).
- The `.git` directory is excluded from the Docker build context via `.dockerignore` (line 1), confirming that all git metadata MUST be passed as build-args from the build scripts.
- The file ends with `WORKDIR`, `ENTRYPOINT`, and `HEALTHCHECK` (lines 189-194). New provenance layers should go AFTER the existing `HEALTHCHECK` or just before it to be the last cache-busting layers.
- Uses `DEV_USER=dev` as the default user ARG (line 15).

### build-base.sh (`/workspace/build-base.sh`)
- **166 lines total**. Parses `--tags`, `--push`, `--registry` flags.
- Already detects current branch on line 59 via `git rev-parse --abbrev-ref HEAD`.
- `docker build` command is on lines 117-126, passing build-args for `NODE_VERSION`, `ZSH_IN_DOCKER_VERSION`, `GIT_USER_EMAIL`, `GIT_USER_NAME`, `GIT_GPG_SIGN`, `GIT_SIGNING_KEY`.
- Loads `.env` on line 72-78 via `export $(grep -v '^#' .env ...)`.
- No existing provenance/commit/date args passed.

### GitHub Actions workflow (`/workspace/.github/workflows/build-push-image.yml`)
- **109 lines total**. Uses `docker/metadata-action@v5` for tag/label extraction (lines 43-57).
- `docker/build-push-action@v6` at lines 59-70 passes `labels: ${{ steps.meta.outputs.labels }}` but NO `build-args:` key at all.
- The `metadata-action` already generates OCI labels like `org.opencontainers.image.revision` and `org.opencontainers.image.created` externally. Our Dockerfile LABELs will serve as defaults that CI overrides via the metadata-action labels.
- GitHub Actions context provides `${{ github.sha }}` (full 40-char SHA), `${{ github.ref_name }}` (branch/tag), and the `${{ github.event.head_commit.timestamp }}` for build metadata.

### Pre-push hook (`/workspace/.devcontainer/hooks/pre-push`)
- **234 lines total**. Already computes:
  - `BRANCH` on line 83: `git rev-parse --abbrev-ref HEAD | sed 's/[^a-zA-Z0-9._-]/-/g'`
  - `COMMIT_SHA` on line 104: `git rev-parse --short=7 HEAD`
  - `GIT_TAG` on line 107: `git describe --exact-match --tags 2>/dev/null || echo ""`
- `BUILD_CMD` is assembled on lines 177-190 as a string, then `eval`'d on line 193.
- No existing `--build-arg` flags for provenance.

### docker-compose.yml (`/workspace/docker-compose.yml`)
- **138 lines total**. Build args section at lines 13-23 for `claudio-standalone` service.
- Only passes user, version, and git config args. No provenance args.
- Uses `${COMPOSE_PROJECT_NAME:-claudio}-base:${TAG:-develop}` for the image name (line 24).

### claudio version command (`/workspace/cli/commands/version.sh`)
- **162 lines total**. `show_version_info()` function at lines 71-117.
- Uses `CLAUDIO_VERSION` from `common.sh` (hardcoded "1.0.0" on line 6 of `/workspace/cli/lib/common.sh`).
- Has both human-readable and JSON output modes.
- Uses `print_table_row()` from `/workspace/cli/lib/output.sh` (line 220-226): `printf "  %-30s %-15s %s\n"`.
- Checks `in_container()` on line 107 to show container status.

### CLI architecture
- Entry point: `/workspace/cli/claudio` sources `lib/common.sh` and `lib/output.sh`, then routes commands.
- All commands have access to `CLAUDIO_VERSION`, `print_table_row`, `print_header`, `info`, `log`, `has_command`, `in_container`.

### Key patterns and conventions
- Shell scripts use `set -e` (or `set -euo pipefail` for CLI).
- Color codes: GREEN, YELLOW, RED, BLUE, NC defined in common.sh.
- Functions documented with `#######################################` block comments.
- Dockerfile layers are numbered and commented (`# Layer N: Description`).

## Files to Change

| File | Action | What Changes |
|------|--------|-------------|
| `/workspace/Dockerfile.base` | Modify | Add 5 provenance ARGs with defaults, add OCI LABEL instruction, add RUN to write `/etc/claudio-release` |
| `/workspace/build-base.sh` | Modify | Compute git SHA/dirty/branch/tag/date, pass as `--build-arg` flags to docker build |
| `/workspace/.github/workflows/build-push-image.yml` | Modify | Add `build-args:` block to `docker/build-push-action` step with GitHub Actions context vars |
| `/workspace/.devcontainer/hooks/pre-push` | Modify | Add provenance `--build-arg` flags to the BUILD_CMD assembly |
| `/workspace/docker-compose.yml` | Modify | Add provenance build args to the `claudio-standalone` service args section |
| `/workspace/cli/commands/version.sh` | Modify | Read `/etc/claudio-release` and display build provenance in both human and JSON output |

## Implementation Steps

### Step 1: Add provenance ARGs and LABEL/release-file to Dockerfile.base

**File:** `/workspace/Dockerfile.base`

**What to do:** Add new ARG declarations for provenance metadata, an OCI LABEL instruction, and a RUN command that writes `/etc/claudio-release`. Place these as the very last layers (after current line 194, the HEALTHCHECK) to avoid cache-busting earlier layers.

**Changes:**

1. After line 30 (after the git config ARGs block), add the provenance ARGs. These should go at the top with other ARGs so they are declared early, but since they are only consumed by LABEL and a RUN at the very end, they will not bust cache of intermediate layers. However, Docker re-evaluates all layers after an ARG that has changed -- so to minimize cache busting, declare the ARGs just before they are used. The best approach: declare the ARGs right before the LABEL/RUN block at the end of the file.

2. After the current last line (line 194, the HEALTHCHECK), append:

```dockerfile
# Build provenance (declared last to avoid cache busting)
ARG BUILD_COMMIT=unknown
ARG BUILD_DATE=unknown
ARG BUILD_BRANCH=unknown
ARG BUILD_TAG=dev
ARG BUILD_HOSTNAME=unknown

# OCI-standard labels for image metadata
LABEL org.opencontainers.image.revision="${BUILD_COMMIT}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${BUILD_TAG}" \
      org.opencontainers.image.source="https://github.com/ksizzle88/claudio" \
      org.opencontainers.image.title="Claudio" \
      org.opencontainers.image.description="Production-ready devcontainer for Claude Code development" \
      com.claudio.build.branch="${BUILD_BRANCH}" \
      com.claudio.build.hostname="${BUILD_HOSTNAME}"

# Write build provenance to /etc/claudio-release (shell-sourceable KEY=VALUE format)
RUN echo "BUILD_COMMIT=${BUILD_COMMIT}" > /etc/claudio-release \
    && echo "BUILD_DATE=${BUILD_DATE}" >> /etc/claudio-release \
    && echo "BUILD_BRANCH=${BUILD_BRANCH}" >> /etc/claudio-release \
    && echo "BUILD_TAG=${BUILD_TAG}" >> /etc/claudio-release \
    && echo "BUILD_HOSTNAME=${BUILD_HOSTNAME}" >> /etc/claudio-release
```

**Gotchas:**
- The ARGs must be declared AFTER the last `FROM` directive for them to be in scope. Since there is only one `FROM` (line 12), this is fine anywhere after it.
- Declaring the ARGs at the very end (just before LABEL/RUN) ensures that earlier cached layers are not invalidated when provenance values change between builds. Only the LABEL and RUN layers will be rebuilt.
- The `RUN echo ...` command runs as root (which is the current USER context at line 185 where `USER root` is set). This is correct since `/etc/` is root-owned.
- The LABEL instruction does not create a filesystem layer -- it only adds metadata. The RUN is the only layer that busts cache.
- The `HEALTHCHECK` instruction should remain where it is (before the provenance block is fine, or it can stay after). Since HEALTHCHECK does not create a layer, order relative to LABEL/RUN doesn't matter for caching. Keep HEALTHCHECK before provenance for clarity.

**Verification:**
```bash
docker build -f Dockerfile.base -t claudio-test:provenance . 2>&1 | tail -5
docker inspect claudio-test:provenance --format '{{index .Config.Labels "org.opencontainers.image.revision"}}'
docker run --rm claudio-test:provenance cat /etc/claudio-release
```

---

### Step 2: Update build-base.sh to compute and pass provenance build-args

**File:** `/workspace/build-base.sh`

**What to do:** After the tag computation (around line 67) and before the docker build command (line 117), add logic to compute provenance values from git state. Then add `--build-arg` flags to the docker build command.

**Changes:**

1. After line 67 (end of the tag default logic), add a new section to compute provenance:

```bash
# Compute build provenance
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BUILD_HOSTNAME=$(hostname -s 2>/dev/null || echo "unknown")

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BUILD_COMMIT=$(git rev-parse --short=7 HEAD 2>/dev/null || echo "unknown")
    BUILD_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

    # Append -dirty suffix if there are uncommitted changes
    if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet HEAD 2>/dev/null; then
        BUILD_COMMIT="${BUILD_COMMIT}-dirty"
    fi

    # Try to get a version tag
    BUILD_TAG=$(git describe --exact-match --tags 2>/dev/null || echo "dev")
else
    BUILD_COMMIT="unknown"
    BUILD_BRANCH="unknown"
    BUILD_TAG="dev"
fi

echo "  Build provenance:"
echo "    Commit: $BUILD_COMMIT"
echo "    Branch: $BUILD_BRANCH"
echo "    Tag:    $BUILD_TAG"
echo "    Date:   $BUILD_DATE"
echo "    Host:   $BUILD_HOSTNAME"
```

2. In the docker build command (lines 117-126), add 5 new `--build-arg` lines before the trailing `.`:

Add these lines after line 125 (`--build-arg GIT_SIGNING_KEY=...`) and before line 126 (`.`):

```bash
    --build-arg BUILD_COMMIT="${BUILD_COMMIT}" \
    --build-arg BUILD_DATE="${BUILD_DATE}" \
    --build-arg BUILD_BRANCH="${BUILD_BRANCH}" \
    --build-arg BUILD_TAG="${BUILD_TAG}" \
    --build-arg BUILD_HOSTNAME="${BUILD_HOSTNAME}" \
```

**Gotchas:**
- The `git diff --quiet` check returns exit code 1 if there are differences, which would trigger `set -e`. Use it in an `if` conditional so the exit code is consumed by the `if` statement, not by `set -e`.
- `hostname -s` may not be available everywhere; the `|| echo "unknown"` fallback handles that.
- The `git describe --exact-match --tags` will fail (exit 128) if there's no tag on the current commit. The `|| echo "dev"` fallback handles this, and the `if` conditional protects against `set -e`.

**Verification:**
```bash
./build-base.sh --tags provenance-test 2>&1 | grep -A5 "Build provenance"
docker inspect claudio-base:provenance-test --format '{{json .Config.Labels}}' | jq .
```

---

### Step 3: Update GitHub Actions workflow to pass provenance build-args

**File:** `/workspace/.github/workflows/build-push-image.yml`

**What to do:** Add a `build-args:` block to the `docker/build-push-action` step (lines 59-70) that passes GitHub Actions context variables as provenance build-args. These become Dockerfile defaults that the `docker/metadata-action` labels then override at the Docker label level.

**Changes:**

Add `build-args:` to the `docker/build-push-action` `with:` block, after the `provenance: false` line (line 70). The full step becomes:

```yaml
      - name: Build and push Docker image
        id: push
        uses: docker/build-push-action@v6
        with:
          context: .
          file: Dockerfile.base
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          provenance: false
          build-args: |
            BUILD_COMMIT=${{ github.sha }}
            BUILD_DATE=${{ github.event.head_commit.timestamp || github.event.repository.updated_at }}
            BUILD_BRANCH=${{ github.ref_name }}
            BUILD_TAG=${{ github.ref_type == 'tag' && github.ref_name || 'dev' }}
            BUILD_HOSTNAME=github-actions
```

**Gotchas:**
- `${{ github.sha }}` is the full 40-character SHA. This is intentional for CI builds (higher precision than local 7-char). The Dockerfile doesn't care about length.
- `${{ github.event.head_commit.timestamp }}` may be null for `workflow_dispatch` triggers. The fallback `|| github.event.repository.updated_at` handles that. If both are null, the Dockerfile ARG default of `unknown` applies.
- For the `BUILD_TAG`, we check `github.ref_type == 'tag'` -- if pushing a tag like `v1.0.0`, use it; otherwise default to `dev`.
- The `docker/metadata-action` labels will override the Dockerfile LABEL values for `org.opencontainers.image.revision`, `.created`, and `.version` since Docker applies labels in order (later wins). This is the correct coexistence behavior: Dockerfile provides defaults, CI provides authoritative values.
- The `build-args` value is a multi-line string (indicated by `|`), with each line being a `KEY=VALUE` pair.

**Verification:**
After pushing to a branch, check the GitHub Actions run log for the build step and verify build-args are listed. Then:
```bash
docker pull ghcr.io/ksizzle88/claudio:<branch>
docker run --rm ghcr.io/ksizzle88/claudio:<branch> cat /etc/claudio-release
```

---

### Step 4: Update pre-push hook to pass provenance build-args

**File:** `/workspace/.devcontainer/hooks/pre-push`

**What to do:** The hook already computes `COMMIT_SHA`, `BRANCH`, and `GIT_TAG`. Add provenance build-args to the `BUILD_CMD` assembly section.

**Changes:**

1. After line 107 (`GIT_TAG=$(git describe ...)`), add the additional provenance variables:

```bash
# Build provenance
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BUILD_HOSTNAME=$(hostname -s 2>/dev/null || echo "unknown")

# Check for dirty working tree
BUILD_COMMIT_FULL="${COMMIT_SHA}"
if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet HEAD 2>/dev/null; then
    BUILD_COMMIT_FULL="${COMMIT_SHA}-dirty"
fi

# Determine build tag
BUILD_TAG_VALUE="${GIT_TAG:-dev}"
```

2. In the BUILD_CMD assembly section (lines 177-190), after line 190 (`BUILD_CMD="$BUILD_CMD -f Dockerfile.base ."`), insert the build-args before the `-f` flag. Specifically, add these lines after line 187 (after the tag loop `done`) and before line 190:

```bash
# Provenance build args
BUILD_CMD="$BUILD_CMD --build-arg BUILD_COMMIT=${BUILD_COMMIT_FULL}"
BUILD_CMD="$BUILD_CMD --build-arg BUILD_DATE=${BUILD_DATE}"
BUILD_CMD="$BUILD_CMD --build-arg BUILD_BRANCH=${BRANCH}"
BUILD_CMD="$BUILD_CMD --build-arg BUILD_TAG=${BUILD_TAG_VALUE}"
BUILD_CMD="$BUILD_CMD --build-arg BUILD_HOSTNAME=${BUILD_HOSTNAME}"
```

**Gotchas:**
- The existing `COMMIT_SHA` variable (line 104) is already a 7-char short SHA. We create a new `BUILD_COMMIT_FULL` to potentially append `-dirty` without modifying the original (which is used for Docker tags on line 139).
- The `GIT_TAG` variable (line 107) is empty string when no tag exists. The `${GIT_TAG:-dev}` handles this correctly.
- The `git diff --quiet` check must be in a conditional to avoid triggering `set -e` on non-zero exit.

**Verification:**
```bash
# Enable registry and push to a feature branch to trigger the hook
# Check the build output for --build-arg BUILD_COMMIT=... lines
```

---

### Step 5: Update docker-compose.yml to pass provenance build-args

**File:** `/workspace/docker-compose.yml`

**What to do:** Add the provenance build-args to the `args` section of the `claudio-standalone` service build configuration. Use environment variable interpolation with sensible defaults so `docker compose build` works without extra setup.

**Changes:**

After line 23 (`GIT_SIGNING_KEY: ${GIT_SIGNING_KEY:-}`) in the `args:` block, add:

```yaml
        BUILD_COMMIT: ${BUILD_COMMIT:-unknown}
        BUILD_DATE: ${BUILD_DATE:-unknown}
        BUILD_BRANCH: ${BUILD_BRANCH:-unknown}
        BUILD_TAG: ${BUILD_TAG:-dev}
        BUILD_HOSTNAME: ${BUILD_HOSTNAME:-unknown}
```

**Gotchas:**
- Docker Compose substitutes environment variables from the host environment or `.env` file. The defaults (`unknown`, `dev`) ensure `docker compose build` works without any extra setup.
- Users who want provenance in compose builds can export the variables or add them to `.env`. This is a nice-to-have; the primary build paths (`build-base.sh` and CI) handle provenance automatically.
- The `devcontainer` and `devcontainer-test` services extend `claudio-standalone`, so they inherit these build args automatically.
- Be careful not to confuse the `BUILD_TAG` arg here with the existing `TAG` variable used on line 24 for the image tag (`${TAG:-develop}`). They serve different purposes.

**Verification:**
```bash
docker compose config | grep -A30 "build:"
```

---

### Step 6: Update claudio version command to display build provenance

**File:** `/workspace/cli/commands/version.sh`

**What to do:** Enhance `show_version_info()` to read `/etc/claudio-release` (if it exists) and display build provenance information in both human-readable and JSON output modes.

**Changes:**

1. Add a helper function before `show_version_info()` (before line 71):

```bash
#######################################
# Read build provenance from /etc/claudio-release
# Outputs:
#   Sets global variables: BUILD_COMMIT, BUILD_DATE, BUILD_BRANCH, BUILD_TAG, BUILD_HOSTNAME
#######################################
load_build_provenance() {
    BUILD_COMMIT="unknown"
    BUILD_DATE="unknown"
    BUILD_BRANCH="unknown"
    BUILD_TAG="dev"
    BUILD_HOSTNAME="unknown"

    if [[ -f /etc/claudio-release ]]; then
        # shellcheck source=/dev/null
        source /etc/claudio-release
    fi
}
```

2. In the `show_version_info()` function, modify the JSON output block (lines 72-87) to include provenance:

Replace the JSON block with:

```bash
    if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
        load_build_provenance
        local json
        json=$(cat <<EOF
{
  "claudio": "${CLAUDIO_VERSION}",
  "claude": "$(get_version claude)",
  "node": "$(get_version node)",
  "python": "$(get_version python || get_version python3)",
  "gh": "$(get_version gh | awk '{print $3}')",
  "git": "$(get_version git | awk '{print $3}')",
  "docker": "$(get_version docker | awk '{print $3}')",
  "build": {
    "commit": "${BUILD_COMMIT}",
    "date": "${BUILD_DATE}",
    "branch": "${BUILD_BRANCH}",
    "tag": "${BUILD_TAG}",
    "hostname": "${BUILD_HOSTNAME}"
  }
}
EOF
)
        print_json "${json}"
```

3. In the human-readable output block (lines 88-114), after the "Container Tools" section (after line 106) and before the `if in_container` check (line 107), add:

```bash
        # Build provenance (only shown inside containers where /etc/claudio-release exists)
        if [[ -f /etc/claudio-release ]]; then
            load_build_provenance
            echo ""
            echo "Build Provenance:"
            print_table_row "  Commit" "${BUILD_COMMIT}" ""
            print_table_row "  Branch" "${BUILD_BRANCH}" ""
            print_table_row "  Tag" "${BUILD_TAG}" ""
            print_table_row "  Date" "${BUILD_DATE}" ""
            print_table_row "  Host" "${BUILD_HOSTNAME}" ""
        fi
```

**Gotchas:**
- The `source /etc/claudio-release` approach works because the file uses `KEY=VALUE` format with no spaces in values (since we control the format in the Dockerfile).
- The `load_build_provenance` function sets defaults before sourcing, so missing keys in the file are handled gracefully.
- In JSON mode, provenance is always included (with defaults) since the JSON consumer might expect the `build` key. In human-readable mode, it's only shown when `/etc/claudio-release` exists (i.e., inside a container built with provenance).
- The `BUILD_TAG` variable name does not conflict with anything in `common.sh` or `output.sh` (verified by grep).

**Verification:**
```bash
# Build image with provenance, then test inside container:
docker run --rm claudio-base:provenance-test claudio version
docker run --rm claudio-base:provenance-test claudio version --json
# Outside container (no /etc/claudio-release):
claudio version  # Should NOT show build provenance section
```

---

## Testing and Verification

### Pre-flight Checks
1. Ensure Docker is available: `docker info >/dev/null 2>&1`
2. Ensure git is available with a commit: `git rev-parse HEAD`

### Build Verification (Local - build-base.sh)
```bash
# Clean build with provenance
./build-base.sh --tags provenance-test

# Verify labels
docker inspect claudio-base:provenance-test --format '{{json .Config.Labels}}' | jq .

# Verify /etc/claudio-release
docker run --rm claudio-base:provenance-test cat /etc/claudio-release

# Verify claudio version
docker run --rm claudio-base:provenance-test claudio version
docker run --rm claudio-base:provenance-test claudio version --json

# Verify dirty detection (make a change, build, check for -dirty suffix)
echo "# test" >> /tmp/test-file  # Make working tree dirty (if applicable)
# Rebuild and check BUILD_COMMIT ends with -dirty
```

### Build Verification (Docker Compose)
```bash
# Verify compose config includes new args
docker compose config | grep -A35 "args:"

# Build via compose
docker compose build claudio-standalone
```

### Build Verification (GitHub Actions)
- Push to a non-protected branch
- Check the Actions run log for `build-args` in the build step
- Pull the built image and verify: `docker run --rm <image> cat /etc/claudio-release`

### Edge Case Tests
```bash
# Test with no git repo (simulate by building from a tarball)
# The defaults (unknown/dev) should be used

# Test with a tagged commit
git tag v99.99.99-test
./build-base.sh --tags tag-test
docker run --rm claudio-base:tag-test cat /etc/claudio-release
# BUILD_TAG should be v99.99.99-test
git tag -d v99.99.99-test

# Test outside container (claudio version should not show provenance)
claudio version  # No "Build Provenance" section
```

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Cache busting: provenance ARGs change every build, invalidating cache for LABEL/RUN layers | Low | ARGs are declared at the very end of the Dockerfile, so only the LABEL metadata and the single `/etc/claudio-release` RUN layer are rebuilt. All heavy layers (apt, npm, zsh) remain cached. |
| GitHub Actions `github.event.head_commit.timestamp` is null on `workflow_dispatch` | Low | The expression falls back to `github.event.repository.updated_at`. If both are null, the Dockerfile ARG default `unknown` applies. |
| `source /etc/claudio-release` in version.sh could be a security concern if the file contains malicious content | Low | The file is written at image build time from controlled ARG values, not from user input. Only the image builder controls its contents. |
| `BUILD_TAG` variable name collision with docker-compose `TAG` env var | Low | They are in completely different scopes: `BUILD_TAG` is a Docker build ARG, `TAG` is a compose environment variable for the image tag. No collision. |
| Pre-push hook `eval` of BUILD_CMD with user-controlled values | Low | The provenance values come from `git` commands, not user input. The existing eval pattern is already in use for other args. |
| `set -e` interaction with `git diff --quiet` returning non-zero | Medium | All git commands that may return non-zero are wrapped in `if` conditionals or have `|| echo "fallback"` guards. Verified that this pattern is safe with `set -e`. |

## Open Questions

1. **Should `CLAUDIO_VERSION` in `common.sh` be updated?** The task description mentions provenance but not bumping the hardcoded `1.0.0` version. This is a separate concern but worth noting -- `BUILD_TAG` (from git tags) and `CLAUDIO_VERSION` (hardcoded) serve different purposes. No change needed for this task unless the coordinator wants to unify them.

2. **Should the `.env.example` be updated with `BUILD_*` variables?** For docker-compose users who want to set provenance manually, documenting the new variables in `.env.example` would be helpful. This is optional since the primary build paths compute values automatically. Recommendation: add a brief comment section to `.env.example` but mark it as optional/auto-computed.

3. **Should the `install-claudio.sh` script (used by external repos extending the base image) copy `/etc/claudio-release`?** Currently `install-claudio.sh` is used in multi-stage builds. If an external repo builds FROM claudio, the `/etc/claudio-release` from the Claudio base would be present. If they do a multi-stage COPY, they would need to explicitly copy it. This is an edge case and probably not worth addressing in this task.

NOT FOUND
