# Security Models for Sandboxed Agent Execution

Research for GitHub Issue #59 — Agent Permissions Gateway

---

## 1. Container Sandboxing Technologies

### 1.1 gVisor — Application Kernel for Containers

**How it works**: gVisor interposes a user-space kernel (the "Sentry") between the application and the host kernel. No system call passes directly to the host — every supported call has an independent Go implementation in the Sentry. A separate "Gofer" process handles filesystem operations through a restricted protocol.

**Security model**: Dual-kernel isolation similar to VMs, but without the overhead of full hardware virtualization. The Sentry exposes a minimal system call surface to the host kernel. All components are written in memory-safe Go, eliminating buffer overflow / use-after-free classes of vulnerability.

**Relevance to our artifact runtime**: gVisor is the strongest container-based isolation for agent sandboxes without going to full VMs. If the agent container uses gVisor (runsc), even a fully compromised agent cannot directly exploit host kernel vulnerabilities. However, our design already assumes the container is untrusted and only communicates via filesystem artifacts — gVisor would be a defense-in-depth addition, not a core requirement.

**MVP recommendation**: Not needed for MVP. The artifact-based boundary already treats the container as untrusted. gVisor is a post-MVP hardening option for high-security deployments.

### 1.2 Firecracker — Lightweight MicroVMs

**How it works**: Firecracker is a virtual machine monitor (VMM) built on KVM that creates lightweight microVMs. Only 5 emulated devices, ~50,000 lines of code (96% less than QEMU). Boots in ~125ms with <5 MiB memory overhead per VM. Uses Jailer process for cgroup/namespace isolation and thread-specific seccomp filters.

**Security model**: Hardware-level isolation via KVM. Each workload gets a dedicated kernel completely separated from the host. Multiple isolation layers: KVM boundary, Jailer namespace/cgroup isolation, and seccomp filters.

**Relevance to our artifact runtime**: Firecracker provides the strongest possible isolation for agent workloads. The ~125ms boot time makes it viable for on-demand agent execution. However, it requires KVM support and adds operational complexity.

**MVP recommendation**: Out of scope for MVP. The artifact-based boundary already provides the critical security property (agent never gets credentials). Firecracker is relevant for enterprise/multi-tenant deployments where the agent itself might be adversarial.

### 1.3 Claude Code's Own Sandbox Model

**How it works**: Claude Code implements two-layer isolation:

1. **Filesystem isolation**: OS-level enforcement restricts file access. Default: read/write to CWD, read-only elsewhere, certain paths denied entirely. Uses Linux bubblewrap or macOS Seatbelt for kernel-level enforcement. All child processes inherit restrictions.

2. **Network isolation**: Proxy-based domain filtering. All network traffic routes through a proxy running outside the sandbox. Only explicitly allowed domains are reachable. New domain requests trigger permission prompts.

**Permission model**: Three-tier approach:
- `settings.json` allowlist: `Bash(git:*)`, `Bash(npm:*)`, etc. — pattern-matched tool permissions
- Sandbox boundaries: OS-level filesystem/network restrictions
- Human confirmation: Required for anything outside both tiers

**Key insight**: Internal testing showed sandboxing "safely reduces permission prompts by 84%." The philosophy is to define boundaries upfront rather than requiring per-action approval, then only interrupt when boundaries are tested.

**Relevance to our artifact runtime**: This is the closest existing model to what we're building, but inverted:
- Claude Code's sandbox restricts what the agent *can do directly*
- Our artifact runtime restricts what the agent *can request others to do*

The key lesson: **define clear boundaries, auto-approve within them, interrupt only at boundary crossings**. This maps directly to our approval model — low-risk actions could be auto-approved, while high-risk actions require human review.

**MVP recommendation**: Adopt the same philosophy. The artifact boundary is our "sandbox." Within it, the agent can freely read outputs and create request files. The approval step is analogous to Claude Code's permission prompt at the boundary.

### 1.4 Docker Rootless Mode and seccomp

**How it works**: Docker rootless mode runs the Docker daemon and containers without root privileges by using user namespaces. seccomp profiles restrict which system calls a container can make — Docker's default profile blocks ~44 of ~300+ syscalls.

**Relevance to our artifact runtime**: These are baseline hardening measures for any container deployment. The agent container should run rootless with a restrictive seccomp profile as defense-in-depth.

**MVP recommendation**: Use Docker rootless mode if available. Apply a restrictive seccomp profile to the agent container (default Docker profile is a good start). These are low-effort hardening steps.

---

## 2. Approval and Policy Engines

### 2.1 OPA (Open Policy Agent) — Policy as Code

**How it works**: OPA is a general-purpose policy engine. Applications send structured data (JSON) to OPA, which evaluates policies written in Rego (a declarative language) and returns allow/deny decisions. OPA decouples policy decision-making from enforcement.

**Architecture**: `Application → JSON query → OPA → Rego policy evaluation → JSON result`

**Key properties**:
- Policies are versioned code, not configuration
- Decisions are logged and auditable
- Policies can express complex conditions (time-based, content-based, role-based)
- CNCF graduated project — production-proven at scale

**Relevance to our artifact runtime**: OPA could serve as the policy engine for auto-approval decisions in post-MVP. Example policies:
- "Auto-approve SELECT queries on staging schemas"
- "Require manual approval for any shell command containing `rm`, `drop`, or `alter`"
- "Auto-approve terraform plan but require approval for terraform apply"
- "Reject any request larger than 1000 lines"

**MVP recommendation**: Not needed for MVP (all actions require manual approval). Design the approval interface so that an OPA integration point is natural for post-MVP. The `request.meta.json` should contain enough structured data for policy evaluation.

### 2.2 HashiCorp Sentinel — Policy Enforcement

**How it works**: Sentinel is HashiCorp's policy-as-code framework embedded in Terraform Cloud/Enterprise, Vault, Consul, and Nomad. Policies are written in the Sentinel language and evaluated at specific checkpoints (e.g., between `terraform plan` and `terraform apply`).

**Key properties**:
- Enforcement levels: advisory (warn), soft-mandatory (override with approval), hard-mandatory (no override)
- Built-in for HashiCorp products
- Proprietary (not open source like OPA)

**Relevance to our artifact runtime**: The three enforcement levels map well to our approval model:
- **Advisory**: Log the concern but auto-approve
- **Soft-mandatory**: Require human approval (default for MVP)
- **Hard-mandatory**: Block the request entirely (e.g., credential exfiltration patterns)

**MVP recommendation**: Adopt the enforcement level concept in our design, even without Sentinel itself. The `request.meta.json` or a policy config could specify enforcement level per runner or action.

### 2.3 Kyverno — Kubernetes Policy Engine

**How it works**: Kyverno operates as a Kubernetes admission controller via Dynamic Admission Webhooks. When resources are submitted to the K8s API server, Kyverno intercepts them and applies validate/mutate/generate policies written in YAML.

**Architecture flow**: `API request → MutatingWebhook (Kyverno mutates) → ValidatingWebhook (Kyverno validates) → allow/deny`

**Relevance to our artifact runtime**: Kyverno's admission controller pattern is directly analogous to our file watcher + approval flow:
- File watcher detects request change (admission)
- Runtime evaluates the request against policies (validation)
- Human approves or rejects (admission decision)
- Runner executes (resource creation)

**MVP recommendation**: Use as a conceptual model for how our file watcher processes incoming requests. The "validate then act" pattern is the right one.

### 2.4 HashiCorp Boundary — Identity-Aware Proxy

**How it works**: Boundary is an identity-based access management system for dynamic infrastructure. Users authenticate via identity providers, then connect to targets (servers, databases) through Boundary's proxy — never directly. Credentials can be injected by Vault at connection time.

**Architecture**: Controllers handle auth/authz/session management. Workers handle actual traffic proxying. Users never see raw credentials.

**Key principle**: "Credentials never leave the boundary" — users connect through the proxy, which injects credentials on their behalf.

**Relevance to our artifact runtime**: Boundary's architecture is a close analog to our design:
- Our agent = Boundary's user (no direct credential access)
- Our host runtime = Boundary's controller + worker (injects credentials at execution time)
- Our filesystem artifacts = Boundary's session request/response

The critical shared principle: **credentials stay on the trusted side of the boundary; the untrusted side only sees request/response artifacts.**

**MVP recommendation**: This validates our core architecture. The design pattern of "proxy that injects credentials" is proven at scale by Boundary.

### 2.5 AWS IAM Permission Boundaries

**How it works**: Permission boundaries set the maximum permissions an IAM entity can have. Even if a role has broad permissions, the boundary restricts what's actually usable.

**Relevance**: This maps to our runner concept — each runner type defines what the agent *can* request, and the approval layer defines what actually executes. The runner registry acts as a permission boundary.

---

## 3. Artifact-Based Execution Models

### 3.1 Terraform Plan/Apply — The Canonical Model

**How it works**: `terraform plan` produces a saved plan file — an immutable artifact describing exact changes. `terraform apply` consumes that exact plan file. The plan is the "request," the human review is the "approval," and apply is the "execution."

**Key properties**:
- Plan file captures exact state at plan time
- Apply executes exactly those changes — no drift between review and execution
- The saved plan file IS the approval artifact — running `apply` on the plan is equivalent to approving its contents
- Pipeline stages: Validate → Plan (save artifact) → Manual Approval Gate → Apply (consume artifact)

**Security model**: The plan/apply split achieves:
1. Separation of "what will happen" from "make it happen"
2. Human review of exact changes before execution
3. Immutable artifact ensures what was reviewed = what executes
4. Audit trail of who approved which plan

**Relevance to our artifact runtime**: This is the most directly applicable model. Our system IS essentially "terraform plan/apply for arbitrary agent-requested actions":
- Agent writes `request.sql` / `request.sh` = terraform generates plan
- Host runtime detects change and hashes it = plan artifact creation
- Human reviews diff and approves = manual approval gate
- Host executes with credentials = terraform apply
- Output artifacts = apply output

**MVP recommendation**: Model the entire workflow after Terraform's plan/apply pattern. Key implementation detail: **the approved hash must match the executed content** — this is the core integrity guarantee.

### 3.2 Atlantis — PR-Based Plan/Apply

**How it works**: Atlantis listens for VCS webhooks. On PR creation/update, it automatically runs `terraform plan` and posts results as PR comments. `atlantis apply` is triggered via PR comment after approval. State locking prevents concurrent execution.

**Key properties**:
- Fully automated plan execution on PR events
- Human review happens in the PR comment thread
- Apply requires both VCS approval and explicit `atlantis apply` command
- `apply_requirements` config: `approved`, `mergeable`, etc.
- State locking prevents race conditions

**Relevance to our artifact runtime**: Atlantis adds a layer we should consider:
- **Auto-trigger on change detection** (our file watcher does this)
- **Post results for review** (our pending action status does this)
- **Dual approval**: VCS approval + explicit apply command = separate "I've reviewed it" and "go ahead and run it"
- **Locking**: Prevent concurrent execution of the same action

**MVP recommendation**: Implement state locking per action (only one pending/executing request at a time). Consider the Atlantis pattern of auto-running `plan` (equivalent to our hash computation + diff generation) but requiring explicit `approve` + `run` commands.

### 3.3 ArgoCD — GitOps with Sync Approval

**How it works**: ArgoCD watches a Git repository for Kubernetes manifest changes. When it detects drift between Git state and cluster state, it can auto-sync (for dev) or wait for manual sync approval (for staging/prod). Sync phases and waves control execution order.

**Key properties**:
- Git as the source of truth (declarative desired state)
- Auto-sync vs. manual sync per environment
- Sync status: Synced, OutOfSync, Unknown
- Health status of deployed resources

**Relevance**: The auto-sync vs manual sync per environment maps to our tiered approval model:
- Dev/staging actions: auto-approve (post-MVP)
- Production actions: manual approval (always)

### 3.4 Concourse CI — Resource-Based Pipeline Model

**How it works**: Concourse uses a unique resource model where inputs and outputs are typed versioned artifacts. Resources have `check` (detect new versions), `get` (fetch), and `put` (push) operations. Pipelines are directed acyclic graphs of resources and tasks.

**Key properties**:
- Every artifact is versioned and tracked
- Tasks receive inputs and produce outputs through well-defined interfaces
- Resource types are pluggable
- Credentials managed via CredHub/Vault integration — never stored in pipeline code

**Relevance to our artifact runtime**: Concourse's resource model maps cleanly:
- Our action directories = Concourse resources
- `request.sh` change = new resource version (detected by `check`)
- Host runtime = task runner (receives inputs, produces outputs)
- CredHub/Vault integration = our "host credentials" pattern

**MVP recommendation**: Adopt the principle that credentials are injected at execution time from a separate secrets store, never stored in the artifact workspace.

### 3.5 Tekton — Kubernetes-Native CI/CD

**How it works**: Tekton defines CI/CD pipelines as Kubernetes custom resources (Tasks, Pipelines, PipelineRuns). Tekton Chains extends this with artifact signing and SLSA provenance attestation.

**Relevance**: Tekton Chains' approach to artifact signing and provenance is relevant to our receipt/ledger model. Each execution produces signed attestations about what was built and how.

---

## 4. Audit/Ledger Systems

### 4.1 Hash-Chained Append-Only Ledger

**Core implementation pattern**:
```
entry_hash = SHA-256(entry_data + previous_entry_hash)
```

Each entry references the hash of the previous entry, creating a chain where modification of any entry invalidates all subsequent hashes.

**Implementation approaches**:
1. **JSONL file with hash chaining**: Each line is a JSON object containing data, timestamp, and previous hash. Simple, portable, works with `tail -f`.
2. **Chronicle microservice**: Self-hostable append-only ledger with HTTP API and hash chain verification.
3. **SQL Server Ledger**: Database-level immutable tables with automatic hash chaining.
4. **AuditableLLM framework**: Hash-chained logs specifically designed for LLM audit trails.

**Verification**: Recompute all hashes from the first entry. If any computed hash doesn't match the stored hash, tampering is detected at that point.

**Relevance to our artifact runtime**: This is exactly what our `global-ledger.jsonl` needs.

**MVP recommendation**: Implement as a JSONL file with hash chaining:
```json
{"seq": 1, "type": "REQUEST_OBSERVED", "action": "terraform-plan-infra-prod", "timestamp": "2026-03-13T10:00:00Z", "content_hash": "sha256:abc...", "prev_hash": "sha256:000...", "actor": "agent"}
{"seq": 2, "type": "APPROVAL_GRANTED", "action": "terraform-plan-infra-prod", "timestamp": "2026-03-13T10:05:00Z", "content_hash": "sha256:abc...", "prev_hash": "sha256:<hash-of-entry-1>", "actor": "human:kyle"}
```

The `agent-runtime verify` command recomputes the chain and reports any breaks.

### 4.2 AWS CloudTrail — Audit Logging Model

**How it works**: CloudTrail records every API call as a JSON event. Log files are delivered to S3. Digest files are created hourly, containing hashes of all log files from that hour plus the hash of the previous digest — forming a hash chain. Digest files are RSA-signed by AWS.

**Key properties**:
- Separate digest chain from log files
- Hourly batching of digest entries
- RSA signing of digest files
- Public key distribution for verification
- Can validate integrity of any time range

**Relevance to our artifact runtime**: CloudTrail's two-level approach (log files + separate digest chain) is worth considering:
- Our ledger entries = CloudTrail log events
- A separate digest mechanism could periodically "seal" the ledger

**MVP recommendation**: Start with inline hash chaining in the JSONL ledger (simpler). Post-MVP, consider periodic digest/sealing for additional tamper evidence.

### 4.3 Git as a Hash-Chained Ledger

**How it works**: Every Git commit contains the hash of its parent commit(s), the hash of the tree (file state), author, timestamp, and message. The chain of commits forms an append-only ledger with built-in tamper detection.

**Key properties**:
- Content-addressed storage (SHA-1/SHA-256)
- Hash chain via parent references
- Signed commits for non-repudiation
- Widely understood and tooled

**Relevance to our artifact runtime**: Git's model is conceptually close to what we need. The ledger could even be stored as a Git repository for built-in tooling support.

**MVP recommendation**: Don't use Git as the ledger (too heavy for real-time append operations). But borrow the data model: content-addressed hashing, parent chaining, actor attribution.

### 4.4 Sigstore/Cosign — Artifact Signing and Verification

**How it works**: Sigstore provides "keyless" signing where:
1. Developer authenticates via OIDC (identity provider)
2. Fulcio issues a short-lived certificate tied to that identity
3. Artifact is signed with an ephemeral key
4. Signature + certificate are recorded in Rekor (transparency log)
5. Verification checks: signature validity, certificate chain, Rekor inclusion

**Key properties**:
- No long-lived signing keys to manage
- Identity-based signing (tied to who you are, not what key you have)
- Public transparency log for auditability
- Short-lived certificates reduce key compromise risk

**Relevance to our artifact runtime**: Sigstore's model addresses our signing needs elegantly:
- The human approver's identity (from OIDC/local auth) is the signing identity
- Approval signatures don't require managing GPG keys
- The transparency log concept maps to our ledger

**MVP recommendation**: For MVP, use HMAC-based approval signatures (simpler, no external dependencies):
```
approval_signature = HMAC-SHA256(secret_key, action_name + content_hash + timestamp + approver_id)
```

Post-MVP, consider Sigstore integration for stronger non-repudiation and identity binding.

### 4.5 SLSA Framework — Supply Chain Security Levels

**How it works**: SLSA defines four levels of supply chain security:
- **Level 0**: No provenance
- **Level 1**: Provenance exists (who, what, where, when)
- **Level 2**: Signed provenance from the build system
- **Level 3**: Provenance from hardened, dedicated build infrastructure

**Key concept**: Provenance attestation — a signed document asserting metadata about how an artifact was produced.

**Relevance to our artifact runtime**: Our receipt.json IS a provenance attestation. It should contain:
- What was executed (content hash of request)
- Who approved it (approver identity)
- When it ran (timestamps)
- What it produced (output hashes)
- How it was produced (runner type, host identity)

**MVP recommendation**: Structure `receipt.json` to be SLSA-compatible at Level 1 (provenance exists). This sets us up for Level 2 (signed provenance) post-MVP.

---

## 5. Existing Agent Permission Systems

### 5.1 Claude Code's Permission Model

**Implementation** (from `/workspace/.claude/settings.json`):
```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(npm:*)",
      "Bash(docker:*)",
      "Bash(gh:*)"
    ]
  }
}
```

**How it works**: Pattern-matched allowlist. Each tool invocation is checked against the allow patterns. Matches auto-approve; non-matches prompt the user.

**Key properties**:
- Granular per-tool control with glob patterns
- Settings hierarchy: managed → enterprise → user → project
- Hooks system for pre/post tool execution
- Sandbox for OS-level filesystem/network enforcement
- Two modes: "accept edits" (auto-approve within sandbox) and "regular" (always prompt)

**Relevance**: This is the permission model our agents live under. Our artifact runtime extends it for *external* tool access that Claude Code's sandbox can't cover (database queries, cloud CLI, etc.).

### 5.2 LangChain/LangGraph Human-in-the-Loop

**Implementation patterns**:
1. **Interrupt & Resume**: `interrupt()` pauses graph execution, collects human input, resumes based on response. Requires persistent checkpointer.
2. **Human-as-a-Tool**: Agent can "call" a human tool for guidance when uncertain.
3. **Fallback Escalation**: Automatic escalation on failure/uncertainty.
4. **Policy-driven access**: Declarative policies evaluated per-action.

**Configuration model**:
```python
# Per-tool approval config
approval_config = {
    "safe_tool": False,         # auto-approve
    "dangerous_tool": True,     # always interrupt
    "medium_tool": InterruptOnConfig(...)  # conditional
}
```

**Relevance**: The `interrupt()` pattern maps to our approval flow — the agent pauses execution until the human approves the request artifact. The conditional approval config maps to our tiered enforcement levels.

**MVP recommendation**: Our filesystem-based polling (agent checks receipt.json) is simpler than LangGraph's graph-based interrupt, but achieves the same effect. The agent naturally "pauses" by waiting for output artifacts.

### 5.3 AutoGPT / AutoGen Approval Modes

**Pattern**: Most autonomous agent frameworks offer:
- **Full auto**: No human oversight (dangerous)
- **Approval per step**: Human approves each action (high friction)
- **Budget-limited**: Auto-approve up to a cost/time budget
- **Category-based**: Auto-approve reads, approve writes

**Relevance**: Our system naturally supports all these modes:
- Full auto: auto-approve all requests (post-MVP, never for credentials)
- Approval per step: current MVP behavior
- Budget-limited: auto-approve until N requests or total cost threshold
- Category-based: auto-approve `SELECT` queries, approve `ALTER`/`DROP`

---

## 6. Key Design Questions — Analysis and Recommendations

### 6.1 How to verify request artifact integrity (hash before execution)?

**Recommendation**: SHA-256 hash of the request file content, computed by the host runtime at detection time and stored in `request.meta.json`. Before execution, the host re-computes the hash and compares it to the approved hash. If they differ, execution is blocked and a TAMPER_DETECTED ledger entry is written.

```
detection_hash = SHA-256(read("request.sh"))
approved_hash = approval.content_hash
execution_hash = SHA-256(read("request.sh"))  # re-read at execution time
assert execution_hash == approved_hash  # fail if tampered between approval and execution
```

### 6.2 What signing mechanism is lightweight enough for local use?

**Recommendation for MVP**: HMAC-SHA256 with a host-local secret key:
```
signature = HMAC-SHA256(host_secret, canonical_approval_data)
```

Where `canonical_approval_data` = `action_name|content_hash|approver_id|timestamp`

The host secret is generated once on first run and stored in a host-only location (not in the shared workspace). This provides:
- Verification that approvals were made by the host runtime (not forged by the agent)
- No external dependencies
- Fast computation

**Post-MVP**: Sigstore/Cosign for identity-bound signatures, or GPG/age for stronger non-repudiation.

### 6.3 How to implement hash-chained append-only ledger in a file?

**Recommendation**: JSONL format with inline hash chaining:

```jsonl
{"seq":1,"type":"REQUEST_OBSERVED","action":"tf-plan","ts":"2026-03-13T10:00:00Z","content_hash":"sha256:abc123","prev_hash":"sha256:0000000000000000000000000000000000000000000000000000000000000000","actor":"agent","entry_hash":"sha256:def456"}
```

Where `entry_hash = SHA-256(JSON.stringify(entry_without_entry_hash) + prev_hash)`.

Implementation:
1. Read last line of ledger to get `prev_hash`
2. Construct entry with all fields except `entry_hash`
3. Compute `entry_hash = SHA-256(canonical_json(entry) + prev_hash)`
4. Add `entry_hash` to entry
5. Append to file with advisory file lock (flock)

Verification (`agent-runtime verify`):
1. Read all entries
2. For each entry, recompute `entry_hash` and compare
3. Verify each entry's `prev_hash` matches previous entry's `entry_hash`
4. Report any chain breaks with line numbers

### 6.4 What's the right granularity for approval (per-action? per-content-hash? per-tool?)

**Recommendation**: Per-content-hash per-action.

Rationale:
- **Per-tool** is too coarse: "approve all shell commands" defeats the purpose
- **Per-action** is dangerous: approving `terraform-plan-infra-prod` once shouldn't auto-approve future content changes
- **Per-content-hash per-action** is right: "I approve running THIS EXACT content for THIS action"

If the content changes by even one byte, a new approval is required. This is the Terraform model — each plan requires its own approval.

### 6.5 How to handle timeout/expiry of approvals?

**Recommendation for MVP**: Approvals do not expire automatically. The content hash guarantee ensures stale approvals are safe — if the content hasn't changed, the approval is still valid for that exact content.

**Post-MVP considerations**:
- Add optional TTL to approvals (e.g., "this approval expires in 1 hour")
- Invalidate approval if any action dependency changes
- Require re-approval after N hours even for same content (for time-sensitive operations)

### 6.6 Can we support auto-approval for low-risk operations?

**Yes, post-MVP.** The architecture naturally supports this via a policy engine:

1. File watcher detects request change
2. Host runtime evaluates request against policy rules
3. If policy says "auto-approve": skip human review, write APPROVAL_GRANTED (actor: "policy:rule-name"), execute
4. If policy says "manual": queue for human review (current MVP flow)
5. If policy says "deny": write APPROVAL_DENIED, block execution

Example policy rules:
- `SELECT` queries on non-production schemas → auto-approve
- `terraform plan` (read-only) → auto-approve
- `terraform apply` → always manual
- Shell commands containing destructive patterns → always manual
- Shell commands that are pure reads (`cat`, `ls`, `grep`) → auto-approve

**MVP recommendation**: All actions require manual approval. Design the data model so that the approval actor field can be "policy:rule-name" instead of "human:username" for future auto-approval support.

---

## 7. Summary and MVP Security Architecture Recommendations

### Core Security Properties to Maintain

1. **Credential isolation**: Agent never receives credentials. Host injects them at execution time. (Validated by Boundary, Concourse, and Claude Code patterns.)

2. **Content-hash binding**: Approval is tied to exact content hash. Execution verifies hash match. (Validated by Terraform plan/apply, Sigstore, and SLSA patterns.)

3. **Append-only audit trail**: Hash-chained JSONL ledger records all state transitions. (Validated by CloudTrail, Git, and blockchain-inspired patterns.)

4. **Human-in-the-loop**: MVP requires human approval for all privileged actions. (Validated by Atlantis, LangGraph, and Claude Code permission patterns.)

5. **Tamper detection**: Host runtime can detect if request artifacts are modified between approval and execution. (Double-hash verification pattern.)

### MVP Implementation Checklist

| Component | Approach | Complexity |
|-----------|----------|------------|
| Agent isolation | Docker container with no credential mounts | Low |
| Request integrity | SHA-256 hash of request file content | Low |
| Approval signing | HMAC-SHA256 with host-local secret | Low |
| Ledger | JSONL with hash chaining, flock for concurrency | Medium |
| Approval granularity | Per-content-hash per-action | Low |
| Approval timeout | None (hash binding is sufficient for MVP) | None |
| Auto-approval | Not in MVP; design data model to support it later | Low |
| Verification CLI | Recompute ledger chain + validate hashes | Medium |
| State locking | Per-action lock file during execution | Low |

### Post-MVP Security Roadmap

1. **Policy engine integration** (OPA/Rego): Auto-approve low-risk operations
2. **Stronger signing** (Sigstore or GPG/age): Non-repudiation for approvals
3. **Periodic ledger sealing** (CloudTrail-style digests): Additional tamper evidence
4. **gVisor/Firecracker option**: Hardened agent isolation for multi-tenant deployments
5. **SLSA Level 2 compliance**: Signed provenance attestations for all executions
6. **Tiered enforcement levels**: Advisory, soft-mandatory, hard-mandatory (Sentinel pattern)

---

## Sources

### Container Sandboxing
- [gVisor Security Model](https://gvisor.dev/docs/architecture_guide/security/)
- [gVisor Introduction](https://gvisor.dev/docs/architecture_guide/intro/)
- [Firecracker GitHub](https://github.com/firecracker-microvm/firecracker)
- [How to Sandbox AI Agents in 2026 (Northflank)](https://northflank.com/blog/how-to-sandbox-ai-agents)
- [Claude Code Sandboxing Docs](https://code.claude.com/docs/en/sandboxing)
- [Anthropic Engineering: Claude Code Sandboxing](https://www.anthropic.com/engineering/claude-code-sandboxing)

### Approval/Policy Engines
- [Open Policy Agent](https://www.openpolicyagent.org/)
- [OPA Documentation](https://www.openpolicyagent.org/docs/latest/)
- [HashiCorp Boundary](https://developer.hashicorp.com/boundary/docs/what-is-boundary)
- [Boundary Zero Trust](https://developer.hashicorp.com/boundary/docs/overview/zero-trust)
- [Kyverno Introduction](https://kyverno.io/docs/introduction/)
- [How Kyverno Works](https://kyverno.io/docs/introduction/how-kyverno-works/)

### Artifact-Based Execution Models
- [Terraform Core Workflow](https://developer.hashicorp.com/terraform/intro/core-workflow)
- [Atlantis Documentation](https://www.runatlantis.io/docs/using-atlantis)
- [ArgoCD Auto Sync Policy](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/)
- [Concourse CI](https://concourse-ci.org/)
- [CNCF: Secure CI/CD with Tekton and Kyverno](https://www.cncf.io/blog/2022/09/14/protect-the-pipe-secure-ci-cd-pipelines-with-a-policy-based-approach-using-tekton-and-kyverno/)

### Audit/Ledger Systems
- [AWS CloudTrail Log File Integrity Validation](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-log-file-validation-intro.html)
- [CloudTrail Digest File Structure](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-log-file-validation-digest-file-structure.html)
- [Sigstore Overview](https://docs.sigstore.dev/about/overview/)
- [Sigstore Cosign Verification](https://docs.sigstore.dev/cosign/verifying/verify/)
- [SLSA Specification](https://slsa.dev/spec/v1.2/)
- [SLSA Security Levels](https://slsa.dev/spec/v1.0/levels)
- [Trillian — Open Source Append-Only Ledger](https://transparency.dev/)
- [Chronicle — Append-Only Ledger Microservice](https://github.com/paragonie/chronicle)

### Agent Permission Systems
- [LangChain Human-in-the-Loop](https://docs.langchain.com/oss/python/langchain/human-in-the-loop)
- [Human-in-the-Loop for AI Agents (Permit.io)](https://www.permit.io/blog/human-in-the-loop-for-ai-agents-best-practices-frameworks-use-cases-and-demo)
- [Human-in-the-Loop Middleware (FlowHunt)](https://www.flowhunt.io/blog/human-in-the-loop-middleware-python-safe-ai-agents/)
