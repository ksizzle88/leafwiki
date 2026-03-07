# Security Setup Checklist for Claudio

Follow these steps in order. Takes ~15 minutes total.

## Step 1: Setup Signed Commits (5 minutes)

### Check if you have an SSH key
```bash
ls -la ~/.ssh/id_*.pub
```

**If you see a file** (like `id_ed25519.pub` or `id_rsa.pub`):
```bash
# Use your existing key
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub  # or id_rsa.pub
git config --global commit.gpgsign true

# Show your public key (copy this)
cat ~/.ssh/id_ed25519.pub
```

**If you DON'T have an SSH key**:
```bash
# Generate a new one
ssh-keygen -t ed25519 -C "your.email@example.com"
# Press Enter 3 times (accept defaults, no passphrase for simplicity)

# Configure Git to use it
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true

# Show your public key (copy this)
cat ~/.ssh/id_ed25519.pub
```

### Add SSH signing key to GitHub
1. Copy your public key from the command above
2. Go to: https://github.com/settings/keys
3. Click **New SSH key**
4. Title: `Claudio Signing Key`
5. Key type: **Signing Key** (important!)
6. Paste your public key
7. Click **Add SSH key**

### Test it works
```bash
# Make a test commit
echo "test" >> .gitignore
git add .gitignore
git commit -m "test: signed commit"

# Verify it's signed
git log --show-signature -1
# Should show "Good signature" or similar
```

✅ **Done!** All future commits will be signed automatically.

---

## Step 2: Configure Branch Protection (10 minutes)

### For MAIN/MASTER branch

1. Go to: https://github.com/YOUR_USERNAME/claudio/settings/branches
2. Click **Add branch protection rule**
3. Branch name pattern: `main` (or `master` if that's your default)

4. **Enable these settings**:

   #### Pull Request Requirements
   ```
   [✓] Require a pull request before merging
       [✓] Require approvals: 1
       [✓] Dismiss stale pull request approvals when new commits are pushed
   ```

   #### Status Check Requirements
   ```
   [✓] Require status checks to pass before merging
       [✓] Require branches to be up to date before merging

       Search for status checks to require:
       - Type: "build" and select "build-and-push"
       - Type: "Test" and select "Test container"
   ```

   #### Additional Settings
   ```
   [✓] Require signed commits
   [✓] Require conversation resolution before merging
   [✓] Do not allow bypassing the above settings
   [✓] Block force pushes
   [✓] Restrict deletions
   ```

5. Click **Create** (at the bottom)

### For DEVELOP branch

1. Click **Add branch protection rule** again
2. Branch name pattern: `develop`
3. **Copy same settings as main/master** (steps 4 above)
4. Click **Create**

### For STAGE branch

1. Click **Add branch protection rule** again
2. Branch name pattern: `stage`
3. **Copy same settings as main/master** (steps 4 above)
4. Click **Create**

✅ **Done!** Protected branches are now secure.

---

## Step 3: Test Branch Protection (2 minutes)

```bash
# Try to push directly to main (this should FAIL - good!)
git checkout main
echo "test" >> README.md
git add README.md
git commit -m "test: direct push"
git push

# You should see an error like:
# "refusing to allow a GitHub App to create or update workflow"
# OR "protected branch hook declined"

# This is CORRECT - you can't push directly anymore!

# Instead, use feature branches:
git checkout -b feature/test-protection
git push -u origin feature/test-protection

# Then create a PR on GitHub
```

✅ **Done!** Branch protection is working.

---

## What You've Accomplished

- ✅ All commits are now cryptographically signed
- ✅ Main/master/develop/stage branches require:
  - Pull request reviews
  - Passing CI tests
  - Signed commits
  - No force pushes
- ✅ Accidental direct pushes are blocked
- ✅ Code quality is enforced automatically

## Workflow Going Forward

```bash
# 1. Create feature branch
git checkout -b feature/my-feature

# 2. Make changes and commit (auto-signed!)
git add .
git commit -m "feat: my new feature"

# 3. Push to GitHub
git push -u origin feature/my-feature

# 4. Create Pull Request on GitHub
# 5. Wait for CI tests to pass
# 6. Get 1 approval
# 7. Merge via GitHub UI
```

---

## Troubleshooting

### "gpg failed to sign the data"
```bash
# Make sure SSH agent is running
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Re-configure signing
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
```

### "Required status check 'build-and-push' is expected"
- You need to push to a protected branch at least once for status checks to appear
- Or push this commit first, THEN add status check requirements

### Can't find status checks in GitHub UI
- Make sure you've run the workflow at least once
- Go to Actions tab → Click a workflow run
- Status check names appear in the UI after first run

---

## Next Steps (Optional)

Once comfortable with this workflow:
1. Add CODEOWNERS file for automatic reviewer assignment
2. Enable Dependabot alerts (Settings → Security)
3. Set up linear history requirement (cleaner git log)

---

**Questions?** Check `.claude/reference/github-cicd-best-practices.md` for details.
# Security Setup Complete
