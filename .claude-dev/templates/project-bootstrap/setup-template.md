# {{PROJECT_NAME}} — Environment Setup

Steps taken to initialize the **{{PROJECT_NAME}}** project environment for working with Claude Code.

---

## 1. Auto-Memory Symlink (Required)

By default, Claude Code's auto-memory system writes to a long path under `~/.claude/projects/`. Symlink that to a project-local directory so memory files live inside the project.

```bash
# Create the project-local memory directory
mkdir -p {{PROJECT_ROOT}}/.claude/agent-memory

# Remove the default auto-memory directory and replace it with a symlink
# NOTE: Replace the path below with the actual auto-memory path for your project.
#       Claude Code derives it from the workspace path, replacing / with -
rmdir /home/{{USER}}/.claude/projects/{{AUTMEMORY_SLUG}}/memory
ln -s {{PROJECT_ROOT}}/.claude/agent-memory \
      /home/{{USER}}/.claude/projects/{{AUTMEMORY_SLUG}}/memory
```

**Finding your auto-memory slug:** Run `ls ~/.claude/projects/` after opening Claude Code in your project once. The directory name is your workspace path with `/` replaced by `-`.

**Note:** If the default `memory/` directory already has files in it, move them into `.claude/agent-memory/` first before removing it.

---

## 2. Create Personal Workflow Directory (Required)

Create a personal workflow directory for session management, scripts, and agent communication. This directory is for you and your agents — not documentation for the repo audience.

```
{{USER_DIR}}/
├── init.md                  # Session bootstrap instructions
├── setup.md                 # This file (environment setup record)
├── interactions.ipynb       # Ephemeral notebook for agent-to-user communication
├── skills/
│   └── interactions.md      # Skill: how agents use the notebook
└── scripts/
    └── artifacts/           # Script output (logs, JSON, data, reports)
```

**Customize:** Replace `{{USER_DIR}}` with your preferred directory name (e.g., `.dev`, `.claude-dev`, or a personal name like `.keith`).

---

## 3. Create Interactions Notebook + Skill (Optional)

If you want agents to communicate with you via a Jupyter notebook:

- **`{{USER_DIR}}/interactions.ipynb`** — Jupyter notebook where agents show work (code cells, markdown cells, bash cells). **Ephemeral** — gets wiped between sessions. Anything worth keeping must be moved to memory or code.
- **`{{USER_DIR}}/skills/interactions.md`** — Skill definition telling agents how to use the notebook and how to handle your comment prefix (e.g., `>>` comments).

**Customize:** Define your own comment convention for inline feedback in notebook cells.

---

## 4. Create CLAUDE.md (Required)

Project-level Claude instructions at the project root. Include:

- Project description and layout
- Reference to `{{USER_DIR}}/` directory and its files
- Agent team definition (names, types, codebase sections)
- Memory structure and rules (two-layer index system)
- Build/run/test commands
- Any project-specific conventions

**Template:** See `init-template.md` for the memory structure and agent team patterns to include.

---

## 5. Add Makefile Targets (Recommended)

```makefile
# Start a new named Claude session with init instructions piped in
# Usage: make init       -> session named "{{PROJECT_NAME}}-1"
#        make init N=2   -> session named "{{PROJECT_NAME}}-2"
N ?= 1
init:
	cat {{USER_DIR}}/init.md | claude -n "{{PROJECT_NAME}}-$(N)"

# Resume the most recent Claude session
resume:
	claude --resume
```

**Customize:** Adjust the session naming convention to match your workflow. The `N` variable supports multiple parallel sessions.

---

## 6. Add .gitignore Entries (Required)

Ignore ephemeral files that shouldn't be committed:

```gitignore
# Ephemeral agent communication notebook
{{USER_DIR}}/interactions.ipynb

# Script artifacts (logs, output, data)
{{USER_DIR}}/scripts/artifacts/
```

---

## 7. Make Workflow Directory a Git Submodule (Optional)

If you want independent version history for your workflow files without polluting the main repo:

```bash
# 1. Remove {{USER_DIR}} from main repo tracking (keeps files on disk)
git rm --cached -r {{USER_DIR}}/

# 2. Initialize {{USER_DIR}} as its own git repo
cd {{USER_DIR}}
git init
git add -A
git commit -m "init: {{USER_DIR}} workspace"
cd ..

# 3. Add it back as a local submodule
git submodule add ./{{USER_DIR}} {{USER_DIR}}
```

**Result:** `.gitmodules` created with local path reference. Main repo tracks `{{USER_DIR}}` as a submodule pointer (commit SHA), not its file contents.

**To commit changes inside the submodule:**
```bash
cd {{USER_DIR}}
git add -A && git commit -m "your message"
cd ..
# Then in main repo, commit the updated submodule pointer:
git add {{USER_DIR}} && git commit -m "chore: update {{USER_DIR}} ref"
```

**Why submodule?**
- `git push` on the main repo never pushes workflow file contents
- Independent commit history for tracking workflow changes
- Can add a remote later to back it up or share across projects

---

## Placeholder Reference

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{{PROJECT_NAME}}` | Short project identifier | `dms-dashboard` |
| `{{PROJECT_ROOT}}` | Absolute path to project root | `/workspace/my-project` |
| `{{USER}}` | OS username | `dev`, `vscode` |
| `{{USER_DIR}}` | Personal workflow directory name | `.dev`, `.keith`, `.claude-dev` |
| `{{AUTMEMORY_SLUG}}` | Auto-memory directory slug (see Step 1) | `-workspace-my-project` |
