#!/bin/bash
set -e

echo "=== Committing Claudio changes ==="
cd /workspace
git add -A

# Only commit if there are changes
if git diff --cached --quiet; then
    echo "No changes to commit in Claudio repo"
else
    git commit -m "feat: Complete devcontainer template with workspace pattern

- Fixed README and CLAUDE.md documentation (bind mount strategy)
- Created comprehensive Template Usage Guide
- Simplified Trainer2 integration using workspace pattern
- Trainer2 runs as regular project in Claudio container
- No duplicate devcontainer setup needed

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
fi

# Only push if there are unpushed commits
if git log @{u}.. --oneline 2>/dev/null | grep -q .; then
    echo "Pushing Claudio changes..."
    git push
else
    echo "Claudio repo is up to date with remote"
fi

echo ""
echo "✅ Done! Claudio changes synced."
