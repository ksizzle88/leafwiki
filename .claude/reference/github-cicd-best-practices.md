# GitHub CI/CD Best Practices for Claudio

This document outlines recommended GitHub repository configurations and CI/CD practices for the Claudio project.

## Branch Protection Rules

Enable branch protection for critical branches to maintain code quality and prevent accidental changes.

### Branches to Protect
- `main` / `master` (production)
- `develop` (integration)
- `stage` (staging/pre-production)

### Recommended Rules

#### 1. Require Pull Request Reviews
- **Minimum reviewers**: 1 (adjust based on team size)
- **Dismiss stale reviews**: Enable (when new commits are pushed)
- **Require review from code owners**: Enable (if using CODEOWNERS file)
- **Restrict who can dismiss reviews**: Repository administrators only

#### 2. Require Status Checks
Before merging, require these checks to pass:
- `build-and-push` (from build-push-image.yml workflow)
- Container test validation
- Security scanning (Trivy)

**Settings**:
- ✓ Require branches to be up to date before merging
- ✓ Require status checks to pass
- ✓ Include administrators (enforce rules for everyone)

#### 3. Require Signed Commits
- ✓ Require signed commits (GPG/SSH)
- Prevents commit spoofing
- Ensures commit authenticity

**Setup for developers**:
```bash
# Configure Git signing
git config --global user.signingkey <your-gpg-key-id>
git config --global commit.gpgsign true

# Or use SSH signing (recommended)
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
```

#### 4. Additional Protections
- ✓ Do not allow bypassing the above settings
- ✓ Restrict force pushes (block completely)
- ✓ Restrict deletions
- ✓ Require linear history (optional - prevents merge commits)
- ✓ Require conversation resolution before merging
- ✓ Lock branch (for archived/legacy branches)

### Configuration Steps

1. Navigate to: **Settings → Branches → Add rule**
2. Branch name pattern: `main` (repeat for `develop`, `stage`)
3. Enable the following:
   ```
   [✓] Require a pull request before merging
       [✓] Require approvals: 1
       [✓] Dismiss stale pull request approvals when new commits are pushed

   [✓] Require status checks to pass before merging
       [✓] Require branches to be up to date before merging
       Status checks:
         - build-and-push
         - Test container
         - Run Trivy vulnerability scanner

   [✓] Require signed commits
   [✓] Require linear history (optional)
   [✓] Require conversation resolution before merging
   [✓] Do not allow bypassing the above settings

   [✓] Restrict who can push to matching branches
       - Restrict pushes that create matching branches (optional)

   [✓] Block force pushes
   [✓] Restrict deletions
   ```
4. Click **Create** or **Save changes**

## Secrets Management

Proper secrets management is critical for security. Never commit secrets to version control.

### Development Environment (.env)

**Local development only** - never commit `.env` files:

```bash
# .env (gitignored)
GIT_USER_EMAIL=your.email@example.com
GIT_USER_NAME=Your Name
REGISTRY_ENABLED=true
REGISTRY_URL=ghcr.io
REGISTRY_USERNAME=your-github-username
GITHUB_PACKAGE_PAT=ghp_your_token_here
```

**Setup**:
1. Copy `.env.example` to `.env`
2. Fill in your credentials
3. Verify `.env` is in `.gitignore`

### GitHub Actions Secrets

**Already configured** ✓:
- `GITHUB_TOKEN` - Automatically provided by GitHub Actions
  - Used for: Registry authentication, attestations

**To add additional secrets**:
1. Navigate to: **Settings → Secrets and variables → Actions**
2. Click **New repository secret**
3. Add secrets as needed (AWS credentials, API keys, etc.)

**Usage in workflows**:
```yaml
- name: Deploy to AWS
  env:
    AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  run: ./deploy.sh
```

### Production Secrets Management

For production environments, use dedicated secrets management services:

#### AWS Secrets Manager / Parameter Store
```bash
# Store secret
aws secretsmanager create-secret \
  --name claudio/production/db-password \
  --secret-string "your-secret-value"

# Retrieve in application
aws secretsmanager get-secret-value \
  --secret-id claudio/production/db-password \
  --query SecretString --output text
```

#### HashiCorp Vault
```bash
# Store secret
vault kv put secret/claudio/production db_password="your-secret"

# Retrieve secret
vault kv get -field=db_password secret/claudio/production
```

#### 1Password / Bitwarden (Team Development)
- Use 1Password CLI or Bitwarden CLI for team secret sharing
- Integrate with CI/CD pipelines using service accounts
- Rotate secrets regularly

### Best Practices

1. **Never commit secrets**
   - Use `.env` files (gitignored) for local development
   - Use environment variables in production
   - Scan commits for secrets (use git-secrets or similar tools)

2. **Rotate secrets regularly**
   - GitHub PATs: Every 90 days
   - AWS credentials: Every 90 days
   - Database passwords: Every 180 days

3. **Use least privilege**
   - Grant minimum required permissions
   - GitHub PAT scopes: Only `write:packages` for registry
   - AWS IAM: Specific resource permissions only

4. **Audit access**
   - Review who has access to secrets
   - Monitor secret usage logs
   - Revoke access when team members leave

5. **Separate environments**
   - Different secrets for dev/staging/production
   - Never use production secrets in development
   - Use different AWS accounts/regions

## Container Registry Security

### Authentication
- ✓ GitHub Actions uses `GITHUB_TOKEN` (automatic, short-lived)
- ✓ Local development uses Personal Access Token (PAT)
- Rotate PATs every 90 days

### Image Signing & Attestations
- ✓ Implemented: Build provenance attestations
- Consider: Cosign for image signing

```yaml
- name: Sign container image
  uses: sigstore/cosign-installer@main

- name: Sign the images
  run: cosign sign ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.push.outputs.digest }}
```

### Vulnerability Scanning
- ✓ Implemented: Trivy scanning on every build
- Results uploaded to GitHub Security tab
- Scan on schedule (weekly) for base image updates

### Access Control
- GitHub Container Registry permissions:
  - Public: Anyone can pull
  - Private: Require authentication
  - Internal: Organization members only

**Configure visibility**:
1. Navigate to package settings on GitHub
2. Choose: Public / Private / Internal
3. Manage team access permissions

## Testing Strategy

### Container Testing in CI/CD

**Already implemented** ✓:
```yaml
- name: Test container
  run: |
    docker run --rm ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.push.outputs.digest }} /bin/sh -c "
      echo '=== Testing container components ===' &&
      claude --version &&
      python --version &&
      node --version &&
      git --version &&
      gh --version &&
      echo '=== All tests passed ✓ ==='
    "
```

### Additional Testing Strategies

#### Integration Tests
```yaml
- name: Run integration tests
  run: |
    docker run --rm \
      -v ${{ github.workspace }}/tests:/tests \
      ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.push.outputs.digest }} \
      pytest /tests/integration
```

#### Security Tests
```yaml
- name: Test for sensitive data
  run: |
    # Ensure no secrets in image
    docker run --rm ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.push.outputs.digest }} \
      /bin/sh -c "! grep -r 'password\|secret\|token' /app 2>/dev/null"
```

#### Performance Tests
```yaml
- name: Test container startup time
  run: |
    time docker run --rm ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.push.outputs.digest }} \
      echo "Container ready"
```

## Workflow Optimization

### Build Caching
**Already implemented** ✓:
```yaml
cache-from: type=gha
cache-to: type=gha,mode=max
```

### Multi-arch Builds (Optional)
```yaml
- name: Set up QEMU
  uses: docker/setup-qemu-action@v3

- name: Build multi-arch
  uses: docker/build-push-action@v6
  with:
    platforms: linux/amd64,linux/arm64
```

### Dependency Caching
```yaml
- name: Cache dependencies
  uses: actions/cache@v3
  with:
    path: |
      ~/.npm
      ~/.cache/pip
    key: ${{ runner.os }}-deps-${{ hashFiles('**/package-lock.json', '**/requirements.txt') }}
```

## Monitoring & Alerts

### GitHub Actions
- Enable email notifications for workflow failures
- Settings → Notifications → Actions

### Security Alerts
- Enable Dependabot alerts
- Settings → Security → Dependabot
  - ✓ Dependabot alerts
  - ✓ Dependabot security updates
  - ✓ Dependabot version updates

### Container Registry
- Monitor registry storage usage
- Set up alerts for:
  - Image size increases (>500MB)
  - High vulnerability counts (>5 CRITICAL)
  - Failed builds

## Compliance & Audit

### Audit Logs
- Review GitHub audit log regularly
- Settings → Audit log
- Look for:
  - Secret access
  - Branch protection changes
  - Repository setting changes

### Compliance Requirements
- GDPR: Data retention policies (image cleanup)
- SOC2: Access controls (branch protection)
- PCI-DSS: Secret rotation (90-day PAT rotation)

### Image Provenance
- ✓ Implemented: SLSA attestations
- Track: Who built, when, from what code
- Verify: `gh attestation verify`

## Rollback Strategy

### Image Tagging for Rollback
```bash
# Current deployment
docker pull ghcr.io/user/claudio:main

# Rollback to previous version
docker pull ghcr.io/user/claudio:abc1234  # specific commit SHA

# Rollback to previous release
docker pull ghcr.io/user/claudio:v1.2.3
```

### Workflow Rollback
```yaml
# Re-run previous successful workflow
gh workflow run build-push-image.yml --ref <previous-commit-sha>
```

## Troubleshooting

### Common Issues

**Build failures**:
1. Check workflow logs in Actions tab
2. Verify Dockerfile syntax
3. Test build locally: `docker build -f Dockerfile.base .`

**Authentication failures**:
1. Verify GITHUB_TOKEN permissions
2. Check PAT expiration
3. Confirm registry URL matches

**Test failures**:
1. Pull image locally: `docker pull <image>@<digest>`
2. Run tests manually: `docker run --rm <image> claude --version`
3. Check for missing dependencies

**Security scan failures**:
1. Review Trivy output in Security tab
2. Update base image for patches
3. Add exceptions for false positives (with justification)

## Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Docker Build Best Practices](https://docs.docker.com/build/building/best-practices/)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Trivy Documentation](https://aquasecurity.github.io/trivy/)
- [SLSA Framework](https://slsa.dev/)
