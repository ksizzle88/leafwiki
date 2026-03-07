# Plan: Task #33 -- Fix mpulse zshrc bind mount failing on WSL Docker

## Summary

Remove two lines from `mpulse/.devcontainer/docker-compose.yml` that bind-mount the zshrc file at runtime. This mount fails on WSL Docker because Docker cannot resolve the relative single-file path `./zshrc` through the Windows-WSL-Docker path translation chain. The Dockerfile already COPYs the same file into the image at build time (lines 107-108), so the bind mount is redundant. Removing it fixes the startup failure with zero functionality loss.

## Research Findings

### docker-compose.yml (lines 40-41)

The offending lines in `/workspace/mpulse/.devcontainer/docker-compose.yml`:

- **Line 40**: `# Shell customizations (live-editable, no rebuild needed)` -- comment
- **Line 41**: `- ./zshrc:/etc/zsh/zshrc.mpulse:ro` -- the bind mount that fails on WSL

These are the only two lines to remove. The surrounding context:

- Line 39: `- mpulse-azure:/home/dev/.azure` (stays)
- Line 42: `# Persist container settings and configs` (stays)

### Dockerfile (lines 106-108)

Already correct, no changes needed:

```dockerfile
# Shell customizations (edit zshrc instead of echo chains)
COPY zshrc /etc/zsh/zshrc.mpulse
RUN echo 'source /etc/zsh/zshrc.mpulse' >> /etc/zsh/zshrc
```

### zshrc file

`/workspace/mpulse/.devcontainer/zshrc` (54 lines) -- line 2 already says "edit this file, rebuild container to apply", which is consistent with the COPY-only approach. No changes needed.

### No other references

A grep for `zshrc` across `/workspace/mpulse/.devcontainer/` confirms the only references are the three files listed above. No `devcontainer.json` or other config files reference zshrc.

## Files to Change

| File | Action | What Changes |
|------|--------|-------------|
| `mpulse/.devcontainer/docker-compose.yml` | Modify | Delete lines 40-41 (comment + bind mount) |

## Implementation Steps

### Step 1: Remove the bind mount and its comment from docker-compose.yml

- **What to do**: Delete lines 40 and 41 from `/workspace/mpulse/.devcontainer/docker-compose.yml`
  - Line 40: `      # Shell customizations (live-editable, no rebuild needed)`
  - Line 41: `      - ./zshrc:/etc/zsh/zshrc.mpulse:ro`
- **Which file**: `/workspace/mpulse/.devcontainer/docker-compose.yml`
- **Key details**: After deletion, line 39 (`- mpulse-azure:/home/dev/.azure`) should be immediately followed by the comment `# Persist container settings and configs` (formerly line 42). No blank line between them is needed since the existing file has no blank line between volume groups.
- **Gotchas**: YAML is whitespace-sensitive. Do not alter indentation of surrounding lines. The lines to remove use 6-space indentation for the comment and 6-space + `- ` for the mount entry, matching the rest of the volumes block.
- **Verification**: Run `python3 -c "import yaml; yaml.safe_load(open('/workspace/mpulse/.devcontainer/docker-compose.yml'))"` to validate YAML syntax. Also visually confirm the bind mount line is gone: `grep -n 'zshrc' /workspace/mpulse/.devcontainer/docker-compose.yml` should return no results.

## Testing and Verification

1. **YAML syntax check**:
   ```bash
   python3 -c "import yaml; yaml.safe_load(open('/workspace/mpulse/.devcontainer/docker-compose.yml'))"
   ```
   Expected: No output (success). Any error means the YAML is broken.

2. **Confirm bind mount is removed**:
   ```bash
   grep -n 'zshrc' /workspace/mpulse/.devcontainer/docker-compose.yml
   ```
   Expected: No output (no matches).

3. **Confirm Dockerfile still has the COPY**:
   ```bash
   grep -n 'zshrc' /workspace/mpulse/.devcontainer/Dockerfile
   ```
   Expected: Lines 106-108 showing the COPY and RUN commands, unchanged.

4. **Confirm docker-compose.yml still has all other volume mounts** (sanity check):
   ```bash
   grep -c '^\s*-' /workspace/mpulse/.devcontainer/docker-compose.yml
   ```
   Expected: The count should be exactly one less than before (the removed bind mount line).

5. **Full container rebuild test** (manual, if WSL Docker is available):
   ```bash
   cd /workspace/mpulse/.devcontainer && docker compose build
   ```
   Then start the container and verify `zsh` sources `/etc/zsh/zshrc.mpulse` correctly.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|-------------|
| Accidental removal of wrong lines | Medium | Verify by checking that `grep zshrc docker-compose.yml` returns empty after edit |
| YAML indentation breakage | Medium | Validate with Python yaml.safe_load after edit |
| Loss of live-edit capability | Low | Already broken on WSL; zshrc changes are rare; rebuild is fast due to Docker layer caching |

## Open Questions

None. The task spec from the researcher is thorough and complete. This is a straightforward 2-line deletion with no ambiguity.
