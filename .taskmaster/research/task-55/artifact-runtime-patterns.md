# Artifact-Based Execution Runtimes & File-Based IPC Patterns

Research for GitHub Issue #59 — Agent Permissions Gateway

---

## 1. File-Based IPC Patterns

### 1.1 Filesystem as Message Queue

Multiple CI/CD systems prove that the filesystem is a viable communication channel for artifact-based workflows. The key insight is that **files are the universal IPC** — every process, container, and language can read and write files.

#### GitHub Actions Artifacts

GitHub Actions uses file-based artifacts to pass data between workflow jobs. Each job runs in an isolated runner environment; the only way to share data across jobs is via the `actions/upload-artifact` / `actions/download-artifact` actions. Within a single job, steps share a filesystem and pass data through files or environment variables.

**Key pattern**: Jobs are isolated. Artifacts are the explicit, auditable channel for inter-job data. This maps directly to our model where the agent (one "job") and the host runtime (another "job") communicate only through artifact files.

**What they got right**: Artifact immutability. Once uploaded, an artifact is a snapshot. Our system should similarly treat the *approved hash* as the immutable unit of execution.

#### Tekton Pipeline Results and Workspaces

Tekton uses two mechanisms for inter-task communication:

1. **Results** (small data, <4KB): A task writes to `/tekton/results/<name>`, and downstream tasks reference it via `$(tasks.<task>.results.<name>)`. This is metadata-level passing.

2. **Workspaces** (large data): A shared PVC is mounted into multiple tasks. Each task reads/writes files on the shared volume. This is the data-level passing.

**Relevance to our system**: The Permissions Gateway uses both patterns:
- **Metadata** (request.meta.json, receipt.json) → analogous to Tekton Results
- **Data artifacts** (request.sh, stdout.log, result.json) → analogous to Tekton Workspaces

The workspace pattern is especially relevant because Tekton tasks on a shared PVC face the same coordination challenges we do: knowing when a file is ready, avoiding partial reads, and handling concurrent access.

#### Concourse CI Resources

Concourse enforces strict isolation: within a job, tasks pass artifacts via shared filesystem directories (inputs/outputs). Between jobs, data **must** flow through external resources (S3, git, etc.).

**Key insight**: Concourse's strictness about inter-job boundaries is a security feature, not a limitation. Our system should similarly enforce that the *only* path between agent and host is through the `.agent-runtime/` shared workspace — no backdoor channels, no direct socket communication, no shared environment variables.

#### Apache Airflow XCom

XCom is Airflow's inter-task communication mechanism. Tasks push/pull small values through a metadata database. For large data, tasks push *pointers* (S3 paths, file paths) via XCom, not the data itself.

**Key pattern**: **Control plane = metadata (JSON), Data plane = files**. This is exactly the model the PRD specifies (Section 10): `receipt.json` for status and hashes, `stdout.log` for actual output. Airflow learned the hard way that mixing data into metadata (XCom has a 48KB limit) creates scaling problems.

**Recommendation**: The Permissions Gateway should keep strict separation:
- `request.meta.json`, `receipt.json`, `approval.sig` = control plane (small, structured, JSON)
- `request.sh`, `request.sql`, `stdout.log`, `stderr.log`, `result.json` = data plane (arbitrarily large, content-specific)

### 1.2 Request/Response over Files

The core protocol for the Permissions Gateway is: agent writes a request file → host reads it, executes, writes results. This section analyzes the synchronization challenges.

#### The "Fully Written" Problem

**Problem**: How does the host know a file is completely written? The agent might be writing `request.sh` line by line. If the host reads it mid-write, it gets a partial request.

**Solutions (ranked by recommendation)**:

1. **Atomic write-then-rename** (RECOMMENDED for MVP):
   - Agent writes to `.request.sh.tmp` (or `request.sh.writing`)
   - Agent renames to `request.sh` when complete
   - `rename()` / `mv` is atomic on the same filesystem (POSIX guarantee)
   - Host only watches for `request.sh`, ignoring temp files
   - This is the pattern used by virtually every production system (log rotation, config reload, package managers)

2. **Sentinel file marker**:
   - Agent writes `request.sh`, then creates `request.sh.ready` (or `.ready` in the action directory)
   - Host watches for the sentinel file, not the request file
   - Slightly more complex but useful when the request involves multiple files
   - Can be combined with approach #1 for belt-and-suspenders

3. **Content hash verification**:
   - Agent writes `request.sh` and also writes expected hash to `request.meta.json`
   - Host reads `request.sh`, computes hash, compares to metadata
   - If mismatch, waits and retries
   - More complex but provides integrity verification for free
   - This is effectively what the PRD already specifies (hash comparison for approval)

4. **File locking (flock)**:
   - Agent acquires exclusive lock, writes, releases lock
   - Host tries shared lock to read
   - Works well for same-machine IPC but adds complexity in container scenarios
   - Lock files may not work reliably across Docker bind mount boundaries

**MVP Recommendation**: Use atomic write-then-rename as the primary mechanism. The host watches for the final filename. The metadata envelope (`request.meta.json`) contains the expected content hash, which serves as both integrity verification and the approval target. This gives us approaches #1 and #3 together.

#### Race Conditions and Coordination

**Scenario**: Agent writes request → Host detects → Host reads → Agent modifies request simultaneously.

**Prevention strategy**:
- The **state machine** in `request.meta.json` prevents races. Once the host observes a request and transitions the action to `pending_approval`, further writes by the agent are either:
  - Ignored until current execution completes (MVP: simple, safe)
  - Queued as a new version (post-MVP: more complex)
- The host should **snapshot** the request content hash at detection time. If the file changes between detection and approval, the hash won't match and execution should be refused.

**Key principle from Terraform**: Approval is tied to a specific content hash. If the content changes after approval, the approval is void. This is exactly how `terraform plan -out=tfplan` works — the plan captures the exact changes, and apply executes exactly those changes.

#### Timeout Handling

**Problem**: What if the host starts execution but it hangs?

**Patterns from CI/CD systems**:
- GitHub Actions: Per-step `timeout-minutes`
- Tekton: `timeout` field on Tasks
- Airflow: `execution_timeout` on operators

**Recommendation for Permissions Gateway**:
- Each runner has a configurable default timeout (e.g., shell: 300s, snowflake_sql: 600s)
- Action metadata can override with `max_execution_seconds`
- Host writes `EXECUTION_STARTED` ledger entry with timeout deadline
- If execution exceeds timeout, host kills the process, writes `EXECUTION_FINISHED` with `status: "timeout"`, and records in receipt
- Agent sees `receipt.json` with timeout status and can decide to retry with a different approach

### 1.3 Notification: How the Agent Knows

**The fundamental question**: How does the agent know its request was received and results are ready?

**Option A: Polling** (RECOMMENDED for MVP)
- Agent periodically reads `receipt.json` or `request.meta.json` for state changes
- Simple, reliable, works across all environments
- Polling interval can be short (1-2 seconds) since it's local filesystem
- No special kernel features or libraries required
- This is how most CI/CD agents work (GitHub Actions runner polls for workflow dispatch)

**Option B: inotify / File Watching**
- Agent uses `inotifywait` or similar to watch for file changes
- Zero-latency notification when results are written
- Requires inotify support (not available on NFS, some Docker storage drivers)
- **Critical limitation**: inotify does NOT work reliably across Docker bind mounts on all platforms. macOS Docker Desktop uses gRPC-fuse or VirtioFS, neither of which supports inotify from the guest side watching host writes. Linux bind mounts DO support inotify.
- Risk: different behavior on different developer machines

**Option C: Named Pipes (FIFO)**
- Create a FIFO at `.agent-runtime/actions/<name>/notify`
- Host writes a byte when results are ready; agent blocks on read
- Very low latency, kernel-backed synchronization
- **Problem**: FIFOs are unidirectional and have blocking semantics that are awkward for this use case. If the agent isn't listening, the host's write blocks. If both sides need to coordinate, you need two FIFOs.
- **Problem**: FIFOs don't persist data. If the agent crashes and restarts, it can't recover the notification.

**Option D: Unix Domain Socket**
- Full bidirectional communication
- Very fast (shared kernel buffers)
- But this fundamentally changes the architecture from artifact-based to socket-based
- Loses the "files are the audit trail" property
- Over-engineering for the MVP

**MVP Recommendation**: Polling with a convention. The agent polls `request.meta.json` for a `status` field transition (e.g., `pending_approval` → `approved` → `executing` → `completed`). The receipt file appearing is the completion signal. Polling interval of 1-2 seconds is effectively instant for human-in-the-loop workflows where approval itself takes minutes.

**Post-MVP Enhancement**: Add optional inotify-based watching on Linux, with fallback to polling. This can be an internal implementation detail of an agent-side client library.

### 1.4 Concurrent Requests

**Question**: Can an agent have multiple pending requests?

**Answer**: Yes, by design. Each action is an independent directory. The agent can write to `terraform-plan-prod/request.sh` and `snowflake-validate/request.sql` simultaneously. The host runtime processes each action independently.

**Important constraint**: Within a single action, only one request should be pending at a time. The state machine prevents this:
- Action states: `idle` → `pending_approval` → `approved` → `executing` → `completed` → `idle`
- Writing a new request while in `executing` state should either be rejected or queued (MVP: rejected with clear error in meta)

**Locking pattern from Atlantis**: Atlantis locks per project+workspace. Our system should lock per action. Multiple actions can proceed in parallel, but a single action is serialized.

---

## 2. Shared Workspace Patterns

### 2.1 Docker Volumes for Host-Container File Sharing

The Permissions Gateway requires a shared filesystem between the host (trusted) and agent container (untrusted). Claudio already has extensive experience with this pattern.

#### Bind Mounts vs Named Volumes

| Feature | Bind Mount | Named Volume |
|---------|-----------|-------------|
| Host access | Direct — host sees real files at known path | Indirect — files in Docker-managed directory |
| Agent access | Direct — container sees host files | Direct — container sees volume files |
| UID/GID | Must match between host and container | Container UID owns the data |
| Performance | OS-dependent (macOS: slow, Linux: native) | Consistent, Docker-optimized |
| Host file watching | Native inotify on Linux | Requires Docker volume path knowledge |
| Use case | Development (live editing) | Persistent data (databases, caches) |

**For the Permissions Gateway**: Bind mount is the right choice because:
1. The host runtime needs direct, performant access to watch and read request files
2. The host writes output files that the agent reads
3. File watching (inotify) works natively on bind mounts on Linux
4. The path is predictable and stable (e.g., `~/projects/myproject/.agent-runtime/`)
5. The audit trail (ledger, receipts) lives alongside the project

This is consistent with Claudio's existing pattern: `.:/workspace:cached` is already a bind mount of the project root.

#### Claudio's Existing Volume Architecture

Claudio's current volume system (from `docker-compose.yml` and `init-claude-settings.sh`) provides a template:

```
claudio-shared (named volume) → /home/dev/.claudio-shared    # Cross-container shared state
.:/workspace:cached (bind mount)                               # Project root
```

The `.agent-runtime/` directory should live **inside the bind-mounted workspace** (i.e., at `/workspace/.agent-runtime/` in the container and `./.agent-runtime/` on the host). This means:
- No additional volume mounts needed
- Host runtime watches `<project-dir>/.agent-runtime/actions/`
- Agent reads/writes at `/workspace/.agent-runtime/actions/`
- Same files, same filesystem, same inotify domain

#### UID/GID Mapping

**Current Claudio setup** (from `Dockerfile.base`):
```
ARG DEV_UID=1000
ARG DEV_GID=1000
```

**Host process** typically runs as the user's UID (also usually 1000 on single-user Linux).

**Potential issue**: If the host runtime runs as a different UID than the container user, file permissions could block reads/writes.

**Recommendation**:
- The `.agent-runtime/` directory should be created with `chmod 775` (group-writable)
- Files within should be world-readable (`chmod 644`) for outputs and receipts
- Request files written by agent: owned by container UID (1000), readable by host
- Output files written by host: owned by host UID, readable by container
- If UIDs match (common case), no issues. If they don't, use a shared group.
- The `create-volumes.sh` script already handles this pattern: `chown -R 1000:1000 /shared`

### 2.2 Workspace Layout Analysis

The PRD specifies this layout:

```
.agent-runtime/
  actions/
    terraform-plan-infra-prod/
      PURPOSE.md          # Human/agent readable description of this action
      request.sh          # The request payload (data plane)
      request.meta.json   # Metadata envelope (control plane)
      approval.sig        # Approval proof
      stdout.log          # Execution output
      stderr.log          # Execution errors
      receipt.json        # Execution receipt
    snowflake-validate-member-counts/
      ...
  ledger/
    global-ledger.jsonl   # Append-only hash-chained log
  tools/
    registry.json         # Available runners and conventions
  AGENT_INSTRUCTIONS.md   # Auto-generated agent documentation
```

**Analysis of this layout**:

**Strengths**:
- Self-contained per action — each action directory has everything needed
- Clear separation of concerns (request vs output vs control)
- The ledger is separate from action directories (global view)
- `AGENT_INSTRUCTIONS.md` makes the system self-documenting for agents

**Potential improvements**:
- **Version history**: Current layout overwrites `stdout.log` on each execution. Consider `runs/` subdirectory with timestamped or sequence-numbered execution records (post-MVP).
- **State file**: Add `state` field to `request.meta.json` instead of inferring state from which files exist. Explicit state machine is more reliable.
- **Lock files**: Consider `.lock` files during execution to signal "do not modify" to the agent.

---

## 3. Similar Systems: Patterns and Lessons

### 3.1 Terraform Plan/Apply

Terraform's plan/apply workflow is the closest analog to the Permissions Gateway's request/approval/execution model.

**The pattern**:
```
terraform plan -out=tfplan     # Creates deterministic execution artifact
# Human reviews plan output
terraform apply tfplan          # Executes exactly what was planned
```

**Critical properties**:
1. **Deterministic execution**: The saved plan captures the *exact* set of changes. Apply executes precisely those changes — no more, no less.
2. **Staleness detection**: If infrastructure changes between plan and apply, Terraform refuses to apply (state drift detection).
3. **Artifact-bound approval**: Approving a plan means approving specific content, not a general intent.

**Mapping to our system**:
| Terraform | Permissions Gateway |
|-----------|-------------------|
| `terraform plan -out=tfplan` | Agent writes `request.sh` |
| Plan output (human-readable) | `agent-runtime diff <action>` |
| Human reviews plan | Human reviews via CLI/web |
| `terraform apply tfplan` | Host executes approved request hash |
| State drift detection | Hash mismatch → re-approval required |

**Key lesson**: The reason `terraform plan -out=tfplan` is important is that **between the time you run plan and apply, the real-world state could change**. Similarly, between the time an agent writes a request and the human approves it, the agent could modify the request. The hash-bound approval prevents this.

### 3.2 Atlantis (Terraform PR Automation)

Atlantis automates Terraform in PR workflows, adding locking and approval on top of plan/apply.

**Key mechanisms**:

1. **PR-triggered plan**: When a PR is opened/updated, Atlantis automatically runs `terraform plan` and posts the output as a PR comment.

2. **Comment-based approval**: An authorized reviewer types `atlantis apply` in a PR comment to approve execution.

3. **Workspace locking**: Atlantis locks the Terraform state for a project+workspace when a plan is active. Other PRs for the same project must wait. Lock is released when the PR is merged/closed.

4. **Apply requirements**: Configurable gates: PR must be approved, PR must be mergeable, custom server-side checks.

**Relevance to our system**:

- **Locking per action** → Our system should lock per action directory during execution. If action `terraform-plan-prod` is executing, the agent should not be able to overwrite `request.sh`.
- **Automatic detection** → Atlantis watches for PR events; our host runtime watches for file changes. Same event-driven pattern.
- **Approval tied to content** → Atlantis approves a specific plan output. We approve a specific request hash.
- **Auto-unlock on completion** → Atlantis unlocks when PR merges. We unlock when execution completes and receipt is written.

### 3.3 Rundeck

Rundeck provides job definitions with approval workflows, ACL-based authorization, and comprehensive audit logging.

**Key patterns**:

1. **Job definitions**: Declarative specification of what a job does, what parameters it accepts, and what credentials it needs. Our `request.meta.json` + `PURPOSE.md` serve a similar role.

2. **ACL policies**: Fine-grained access control — who can create, read, update, delete, run, and kill jobs per project. Our system has simpler authorization (human approval = full authority) but could adopt ACL concepts post-MVP for auto-approval policies.

3. **Audit trail**: Every authorization decision is logged with detailed context (user, project, action, decision). This maps directly to our append-only ledger.

4. **Approval workflows**: Rundeck Enterprise supports approval gates where authorized users must approve before jobs execute. This is essentially our approval flow.

**Key lesson**: Rundeck's audit log records both AUTHORIZED and REJECTED decisions. Our ledger should similarly record `APPROVAL_REJECTED` events, not just grants. A complete audit trail includes denials.

### 3.4 Apache Airflow

Airflow's XCom and task execution model provide lessons for inter-task communication and failure handling.

**Relevant patterns**:

1. **XCom for small data, external storage for large data**: Our system correctly separates metadata (JSON control plane) from data (file data plane).

2. **Task retries with configurable backoff**: When execution fails, Airflow can retry with exponential backoff. Our system should support re-execution of the same approved request without requiring re-approval (the hash hasn't changed).

3. **Task status tracking**: Airflow tracks task states: `queued` → `running` → `success` / `failed` / `up_for_retry`. Our action states should be similarly explicit in `request.meta.json`.

4. **Execution timeout**: Airflow's `execution_timeout` per operator maps to our per-runner timeout configuration.

---

## 4. Synchronization and Timing Strategies

### 4.1 File Watch Technologies

| Technology | Platform | Latency | Docker Bind Mount Support | Complexity |
|-----------|----------|---------|--------------------------|-----------|
| inotify (inotifywait) | Linux only | ~0ms | Yes (Linux host) | Low |
| fswatch | Cross-platform | ~0ms native, 5s polling fallback | Varies | Low |
| chokidar (Node.js) | Cross-platform | ~0ms native | Varies | Medium |
| watchman (Facebook) | Cross-platform | ~0ms | Yes (Linux) | Medium |
| Polling (stat/mtime) | Universal | Configurable (1-5s) | Yes, always | Lowest |

**MVP Recommendation**: The host runtime should use **inotify** (via a library like chokidar or Python's watchdog) as the primary detection mechanism, with **polling fallback** for environments where inotify doesn't work (macOS Docker, NFS mounts).

The agent side should use **polling only** — the agent polls for completion by checking `receipt.json` existence or `request.meta.json` status field. The agent doesn't need sub-second latency because it's waiting for human-in-the-loop approval anyway.

### 4.2 The Atomic Write Protocol

Recommended protocol for all file writes in the `.agent-runtime/` workspace:

**Agent writing a request**:
```
1. Write content to .agent-runtime/actions/<name>/request.sh.tmp
2. Compute SHA-256 hash of request.sh.tmp
3. Write/update request.meta.json with new content_hash, status: "pending"
4. Rename request.sh.tmp → request.sh (atomic on same filesystem)
```

**Host writing outputs**:
```
1. Write stdout.log.tmp, stderr.log.tmp during execution
2. On completion, rename to stdout.log, stderr.log (atomic)
3. Compute hashes of all output files
4. Write receipt.json with output hashes, exit code, timing
5. Update request.meta.json status: "completed"
6. Append EXECUTION_FINISHED entry to global ledger
```

**Why this ordering matters**:
- The agent watches for `receipt.json` or status change in meta
- The output files (stdout.log, stderr.log) are guaranteed complete before receipt is written
- The receipt references output file hashes, so outputs must exist first
- The ledger entry comes last as the final record of truth

### 4.3 State Machine for Action Lifecycle

```
                   Agent writes request
                          │
                          ▼
                    ┌──────────┐
                    │  idle     │ ◄──────────────────────┐
                    └────┬─────┘                         │
                         │ Host detects change           │
                         ▼                               │
                ┌──────────────────┐                     │
                │ pending_approval │                     │
                └────┬─────┬──────┘                     │
                     │     │                             │
          Approved   │     │  Rejected                   │
                     ▼     ▼                             │
              ┌──────────┐ ┌──────────┐                  │
              │ approved │ │ rejected │──────────────────┘
              └────┬─────┘ └──────────┘
                   │
                   │ Host starts execution
                   ▼
              ┌───────────┐
              │ executing  │
              └────┬──┬───┘
                   │  │
         Success   │  │  Failure/Timeout
                   ▼  ▼
            ┌───────────────┐
            │   completed   │ (success, failed, or timeout)
            └───────┬───────┘
                    │
                    │ Agent reads results; can write new request
                    ▼
              ┌──────────┐
              │  idle     │
              └──────────┘
```

**State transitions and who triggers them**:
| Transition | Triggered by | File change |
|-----------|-------------|-------------|
| idle → pending_approval | Host (detects request change) | request.meta.json status update |
| pending_approval → approved | Human (via CLI/web) | request.meta.json + approval.sig |
| pending_approval → rejected | Human (via CLI/web) | request.meta.json status update |
| approved → executing | Host (auto after approval) | request.meta.json + ledger entry |
| executing → completed | Host (execution finishes) | receipt.json + stdout/stderr + ledger |
| completed → idle | Implicit (agent can write new request) | request.meta.json reset |
| rejected → idle | Implicit | request.meta.json reset |

### 4.4 Error Reporting Contract

**Standard error reporting files per action**:

```json
// receipt.json — written by host after execution
{
  "execution_id": "exec-20240315-143022-a1b2c3",
  "action": "terraform-plan-infra-prod",
  "status": "success" | "failed" | "timeout" | "rejected",
  "exit_code": 0,
  "started_at": "2024-03-15T14:30:22Z",
  "finished_at": "2024-03-15T14:30:45Z",
  "duration_seconds": 23,
  "runner": "shell",
  "request_hash": "sha256:abcdef...",
  "approval_ref": "approval-20240315-142900",
  "outputs": {
    "stdout.log": { "hash": "sha256:...", "size_bytes": 4521 },
    "stderr.log": { "hash": "sha256:...", "size_bytes": 0 },
    "result.json": { "hash": "sha256:...", "size_bytes": 1203 }
  },
  "error": null | {
    "type": "timeout" | "execution_error" | "permission_denied" | "runner_error",
    "message": "Process exceeded 300s timeout",
    "detail": "Signal SIGKILL sent at 2024-03-15T14:35:22Z"
  }
}
```

**Why this structure**:
- `status` gives the agent a quick check without parsing details
- `exit_code` is the universal process result
- `outputs` with hashes let the agent verify integrity
- `error` is null on success, structured on failure
- `execution_id` links to ledger entries for traceability
- `request_hash` confirms which request version was executed

### 4.5 Progress Reporting for Long-Running Executions

**Problem**: Some executions (Terraform apply, large SQL queries) take minutes. How does the agent know execution is progressing?

**Options**:

1. **Streaming stdout/stderr** (RECOMMENDED):
   - Host writes stdout.log and stderr.log in real-time during execution
   - Agent can tail these files to see progress
   - No special protocol needed — just file I/O
   - On completion, files are finalized and hashes computed

2. **Progress file**:
   - Host writes `progress.json` with percentage, phase, timestamp
   - More structured but requires runner-specific knowledge

3. **Heartbeat in meta**:
   - Host periodically touches `request.meta.json` with `last_heartbeat` timestamp
   - Agent can distinguish "still running" from "hung" by checking heartbeat freshness

**MVP Recommendation**: Stream stdout/stderr in real-time. Add a `last_heartbeat` timestamp to `request.meta.json` that the host updates every 10 seconds during execution. This lets the agent distinguish "running" from "hung" without complex protocols.

---

## 5. Recommendations for the Permissions Gateway

### 5.1 Artifact Protocol Summary

Based on all research, the recommended MVP artifact protocol is:

1. **Write mechanism**: Atomic write-then-rename for all file writes
2. **Detection mechanism**: Host uses inotify (with polling fallback) to detect request changes
3. **Notification mechanism**: Agent polls `request.meta.json` status field (1-2s interval)
4. **Coordination**: Explicit state machine in `request.meta.json`, one pending request per action
5. **Integrity**: SHA-256 content hashes for all artifacts, verified at approval and execution time
6. **Error reporting**: Structured `receipt.json` with status, exit code, output hashes, and error details
7. **Progress**: Real-time stdout/stderr streaming + heartbeat timestamp in metadata
8. **Timeout**: Per-runner configurable timeouts with SIGKILL after grace period
9. **Locking**: Per-action locking during execution (agent cannot overwrite request while executing)
10. **Concurrency**: Multiple actions can execute in parallel; single action is serialized

### 5.2 Technology Choices

| Component | Recommended Technology | Rationale |
|-----------|----------------------|-----------|
| Host file watcher | Python watchdog or Node.js chokidar | Cross-platform, well-maintained, inotify + polling fallback |
| Hashing | SHA-256 (hashlib/crypto) | Industry standard, fast, collision-resistant |
| Ledger format | JSONL (newline-delimited JSON) | Append-only friendly, easy to parse, grep-able |
| Metadata format | JSON | Universal, human-readable, schema-validatable |
| Atomic writes | Write to .tmp + rename | POSIX standard, zero-dependency |
| Agent polling | Simple file stat + JSON parse | No dependencies, works everywhere |

### 5.3 Critical Design Decisions for the Planner

1. **Bind mount, not named volume**: The `.agent-runtime/` directory must be a bind mount so the host has direct filesystem access. This is already the case since it lives inside the project workspace.

2. **Hash-bound approval**: Every approval authorizes a specific SHA-256 hash. If the request changes after approval, re-approval is required. This is the core security property.

3. **State machine is the source of truth**: `request.meta.json`'s `status` field is the canonical action state. All other signals (file existence, ledger entries) are derived from or consistent with this state.

4. **Files are the audit trail**: Every write to `.agent-runtime/` is meaningful. The ledger is the complete record but the individual files in each action directory tell the per-action story.

5. **No cross-boundary trust**: The host never trusts the agent's metadata. The host computes its own hashes, manages its own state machine, and treats all agent-written files as untrusted input.

### 5.4 Risks and Open Questions

1. **macOS Docker performance**: Bind mount performance on macOS (even with VirtioFS) is slower than Linux. File watching may have higher latency. Mitigation: polling fallback with configurable interval.

2. **UID mismatch**: If the host user's UID differs from the container's UID (1000), file permissions could block access. Mitigation: use group-writable permissions, or document UID matching requirement.

3. **Ledger corruption**: If the host crashes mid-write to the ledger, the JSONL file could be corrupted (partial last line). Mitigation: write complete JSON line + newline atomically (write to temp, rename to append position, or use `O_APPEND` which is atomic for writes ≤ PIPE_BUF on Linux).

4. **Agent impersonation**: The filesystem-based protocol means any process with write access to `.agent-runtime/` could impersonate the agent. Mitigation: this is acceptable for MVP (the container IS the agent). Post-MVP: consider signed requests.

5. **Multiple agents**: The current design assumes one agent per `.agent-runtime/` workspace. If multiple agents share a workspace, action naming conflicts could occur. Mitigation: namespace actions with agent ID prefix (post-MVP).

---

## 6. Comparison with Claudio's Existing Patterns

The Permissions Gateway can build on patterns already proven in Claudio:

| Claudio Pattern | How It Maps to Permissions Gateway |
|----------------|-----------------------------------|
| Bind mount (`.:/workspace:cached`) | `.agent-runtime/` lives in the same bind mount |
| Shared volume for auth sync | Not needed — artifacts are per-project, not cross-container |
| `init-claude-settings.sh` bidirectional sync | Similar concept: host and agent both read/write to shared directory |
| Timestamp-based newer-wins for credentials | Similar: hash-based content comparison for request versioning |
| Per-container isolation | Per-action isolation within `.agent-runtime/actions/` |
| `create-volumes.sh` directory initialization | `agent-runtime init` should create the `.agent-runtime/` directory structure |
| `claudio verify` health check | `agent-runtime verify` should check ledger integrity and action states |

**Key difference**: Claudio's existing patterns are for *cooperative* sync between trusted components (container init script, VS Code, etc.). The Permissions Gateway is for *adversarial* or *semi-trusted* communication where the host must verify everything the agent writes. This changes the trust model from "newer wins" to "hash-verified approval required."

---

## Sources

- [GitHub Actions Artifacts Documentation](https://docs.github.com/actions/using-workflows/storing-workflow-data-as-artifacts)
- [Tekton Pipeline Tasks and Workspaces](https://tekton.dev/docs/pipelines/tasks/)
- [Tekton Trusted Artifacts in Workspaces](https://hackmd.io/@jerop/Bkr2wSMah)
- [Concourse CI Task Inputs/Outputs](https://concourse-ci.org/docs/how-to/pipeline-guides/task-inputs-outputs/)
- [Apache Airflow XCom Documentation](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/xcoms.html)
- [Terraform Core Workflow](https://developer.hashicorp.com/terraform/intro/core-workflow)
- [Terraform Plan Command Reference](https://developer.hashicorp.com/terraform/cli/commands/plan)
- [Atlantis Locking Documentation](https://www.runatlantis.io/docs/locking)
- [Atlantis Usage Documentation](https://www.runatlantis.io/docs/using-atlantis)
- [Rundeck Access Control Policy](https://docs.rundeck.com/docs/administration/security/authorization.html)
- [inotify(7) Linux Manual Page](https://man7.org/linux/man-pages/man7/inotify.7.html)
- [Chokidar — Cross-platform File Watcher](https://github.com/paulmillr/chokidar)
- [fswatch — Cross-platform File Change Monitor](https://github.com/emcrisostomo/fswatch)
- [Things UNIX Can Do Atomically](https://rcrowley.org/2010/01/06/things-unix-can-do-atomically.html)
- [Docker Bind Mounts Documentation](https://docs.docker.com/engine/storage/bind-mounts/)
- [IPC Performance Comparison (Baeldung)](https://www.baeldung.com/linux/ipc-performance-comparison)
- [Python atomicwrites Library](https://python-atomicwrites.readthedocs.io/)
