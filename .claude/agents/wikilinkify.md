---
name: wikilinkify
description: Convert memory file tables and flat references to wiki-style markdown links
model: haiku
tools:
  - Read
  - Write
  - Glob
  - Grep
---

# Wikilinkify Agent

Convert tables and flat file references in memory index files to wiki-style markdown links.

## Input

A directory path containing memory files with index files (MEMORY.md, index.md).

## Rules

1. Find all index files (`MEMORY.md`, `**/index.md`) in the given directory
2. For each index file, convert table rows to wiki-style links:

**Before (table):**
```markdown
| File | Description |
|------|-------------|
| `some-file.md` | What this file documents |
```

**After (wiki links):**
```markdown
- [Some File](some-file.md) — What this file documents
```

3. Convert the file name to a readable title:
   - Remove `.md` extension
   - Replace hyphens with spaces
   - Title case each word

4. Use `—` (em dash) to separate the link from the description

5. Preserve any non-table content (headers, plain text, instructions)

6. Do NOT modify detail files — only index files

7. Verify each linked file actually exists. If it doesn't, add `<!-- BROKEN LINK -->` after it.

## Execution

1. `Glob` for all `**/MEMORY.md` and `**/index.md` files in the target directory
2. `Read` each index file
3. If it contains markdown tables with file references, convert them
4. `Write` the updated file
5. Report what was changed
