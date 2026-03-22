# Hash-Chained Ledger & Audit Trail Implementation Patterns

**Research Date**: 2026-03-13
**Context**: Agent Permissions Gateway (Issue #59, Epic #55)
**Stack Context**: FastAPI (Python 3.12) recommended as backend framework per web-framework-comparison.md

---

## 1. Executive Summary

The Agent Permissions Gateway needs an append-only, hash-chained ledger to track the full lifecycle of every action: from request through approval to execution and result recording. This research evaluates design patterns and recommends a JSONL-based, SHA-256 hash-chained ledger with canonical JSON serialization, file-level locking, and a two-tier verification system (chain integrity + artifact integrity).

The recommended approach prioritizes simplicity, correctness, and filesystem-only operation — no external databases, no distributed consensus, no blockchain. The ledger is a single JSONL file with hash chaining, a separate index file for fast lookups, and rotation support via checkpoint entries.

---

## 2. Hash Chain Design Patterns

### 2.1 Linear Hash Chain (Recommended for MVP)

The simplest and most appropriate pattern. Each entry's hash incorporates the previous entry's hash, creating a sequential chain.

**How it works:**
```
Entry 0: hash_0 = SHA256(GENESIS || canonical(entry_0_data))
Entry 1: hash_1 = SHA256(hash_0  || canonical(entry_1_data))
Entry N: hash_n = SHA256(hash_n-1 || canonical(entry_n_data))
```

**Properties:**
- Tamper-evident: changing any entry invalidates all subsequent hashes
- Deletion-evident: removing an entry breaks the chain
- Reorder-evident: swapping entries invalidates hash linkage
- O(n) verification: must walk entire chain to verify integrity
- O(1) append: only need the last hash to add a new entry

**Why this over Merkle trees:** Merkle trees enable logarithmic inclusion proofs (useful for Certificate Transparency where third parties verify specific entries). The agent runtime is single-machine, single-user — the full chain is always local. Linear chains are simpler, sufficient, and easier to debug.

**Reference:** This is essentially how Git commit chains work — each commit contains the hash of its parent, forming a linear (or branching) hash chain. Git uses SHA-1 (now transitioning to SHA-256), and the commit hash covers tree hash + parent hash + author + committer + message.

### 2.2 Merkle Tree (Post-MVP Enhancement)

For future scaling, entries can be grouped into blocks (e.g., per-day or per-1000 entries) and organized into Merkle trees. This enables:
- Logarithmic inclusion proofs (prove entry X exists without revealing entire log)
- Efficient batch verification
- Selective disclosure for audit scenarios

**When to add:** Only if the ledger grows beyond ~100k entries or if external audit verification by third parties becomes a requirement.

### 2.3 Event Sourcing Mapping

The ledger is naturally an event-sourced system. The action lifecycle maps cleanly:

| Event Type | What Happened | Key Data |
|---|---|---|
| `REQUEST_OBSERVED` | Agent wrote/updated a request artifact | action_id, content_hash, file_path |
| `APPROVAL_GRANTED` | Human approved specific content hash | action_id, content_hash, approver, approval_method |
| `APPROVAL_REJECTED` | Human rejected the request | action_id, content_hash, rejector, reason |
| `EXECUTION_STARTED` | Runner began executing | action_id, content_hash, runner_type, execution_id |
| `EXECUTION_FINISHED` | Runner completed | action_id, execution_id, exit_code, duration_ms |
| `RESULT_RECORDED` | Output artifacts written and hashed | action_id, execution_id, output_hashes |

**Current state** is derived by projecting events: the latest event for each action_id determines its status. This eliminates the need for a separate state store — the ledger IS the source of truth.

---

## 3. Recommended Ledger Entry Schema

### 3.1 Entry Structure

```json
{
  "version": 1,
  "sequence": 42,
  "timestamp": "2026-03-13T14:30:00.000Z",
  "timestamp_ms": 1773598200000,
  "event_type": "APPROVAL_GRANTED",
  "action_id": "snowflake-validate-member-counts",
  "execution_id": null,
  "actor": "user:kscherer",
  "content_hash": "sha256:a1b2c3d4e5f6...",
  "data": {
    "approval_method": "cli",
    "approved_file": "request.sql",
    "diff_reviewed": true
  },
  "prev_hash": "sha256:9f8e7d6c5b4a...",
  "entry_hash": "sha256:1a2b3c4d5e6f..."
}
```

### 3.2 Field Definitions

| Field | Type | Description |
|---|---|---|
| `version` | integer | Schema version (start at 1, increment on breaking changes) |
| `sequence` | integer | Monotonically increasing sequence number (0-indexed) |
| `timestamp` | string | ISO 8601 UTC timestamp (human-readable) |
| `timestamp_ms` | integer | Unix epoch milliseconds (machine-sortable, no parsing ambiguity) |
| `event_type` | string | One of the lifecycle event types |
| `action_id` | string | The stable action name (directory name under `.agent-runtime/actions/`) |
| `execution_id` | string | UUID for linking EXECUTION_STARTED → EXECUTION_FINISHED → RESULT_RECORDED |
| `actor` | string | Who triggered this event (format: `type:identity`, e.g. `user:kscherer`, `system:watcher`, `agent:claude`) |
| `content_hash` | string | Hash of the relevant artifact content (prefixed with algorithm, e.g. `sha256:...`) |
| `data` | object | Event-type-specific payload (varies per event_type) |
| `prev_hash` | string | Hash of the previous ledger entry (or `GENESIS` for entry 0) |
| `entry_hash` | string | SHA-256 hash of this entry (computed over all other fields) |

### 3.3 Event-Specific Data Fields

**REQUEST_OBSERVED:**
```json
{
  "file_path": "request.sql",
  "file_size_bytes": 1234,
  "runner_type": "snowflake_sql",
  "previous_content_hash": "sha256:... or null"
}
```

**APPROVAL_GRANTED:**
```json
{
  "approval_method": "cli|web",
  "approved_file": "request.sql",
  "diff_reviewed": true,
  "expires_at": "2026-03-13T15:30:00.000Z or null"
}
```

**EXECUTION_STARTED:**
```json
{
  "runner_type": "snowflake_sql",
  "runner_version": "1.0.0",
  "approval_entry_sequence": 41
}
```

**EXECUTION_FINISHED:**
```json
{
  "exit_code": 0,
  "duration_ms": 4523,
  "stdout_hash": "sha256:...",
  "stderr_hash": "sha256:...",
  "stdout_size_bytes": 8192,
  "stderr_size_bytes": 0
}
```

**RESULT_RECORDED:**
```json
{
  "output_files": {
    "stdout.log": "sha256:...",
    "stderr.log": "sha256:...",
    "result.json": "sha256:...",
    "receipt.json": "sha256:..."
  },
  "receipt_written": true
}
```

### 3.4 Genesis Entry

The first entry in a new ledger uses a special genesis marker:

```json
{
  "version": 1,
  "sequence": 0,
  "timestamp": "2026-03-13T14:00:00.000Z",
  "timestamp_ms": 1773596400000,
  "event_type": "LEDGER_INITIALIZED",
  "action_id": "_system",
  "execution_id": null,
  "actor": "system:runtime",
  "content_hash": null,
  "data": {
    "runtime_version": "0.1.0",
    "workspace_path": "/path/to/.agent-runtime"
  },
  "prev_hash": "GENESIS",
  "entry_hash": "sha256:..."
}
```

---

## 4. Hash Computation Algorithm

### 4.1 Canonical Serialization

**Critical requirement:** Hashing JSON requires deterministic serialization. Two semantically identical JSON objects can produce different byte representations due to key ordering, whitespace, or number formatting.

**Recommended approach: RFC 8785 (JSON Canonicalization Scheme)**

RFC 8785 defines a deterministic JSON serialization:
- Keys sorted lexicographically at every nesting level
- No whitespace
- Numbers serialized using ECMAScript rules
- Deterministic across implementations

**Python implementation:** Use the `rfc8785` PyPI package (pure Python, zero dependencies, by Trail of Bits):
```python
import rfc8785
canonical_bytes = rfc8785.dumps(entry_data)
```

**Fallback (simpler but less rigorous):** `json.dumps(data, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode('utf-8')`. This handles key sorting and whitespace but does not cover all RFC 8785 edge cases (e.g., number serialization). Acceptable for MVP since all our data is strings, integers, and booleans — no floating point edge cases.

### 4.2 Hash Computation Steps

```python
import hashlib
import json

def compute_entry_hash(entry: dict) -> str:
    """Compute the hash of a ledger entry.
    
    The entry_hash field is excluded from the hash computation.
    All other fields (including prev_hash) are included.
    """
    # 1. Create a copy without entry_hash
    hashable = {k: v for k, v in entry.items() if k != 'entry_hash'}
    
    # 2. Canonical serialization (deterministic)
    canonical = json.dumps(hashable, sort_keys=True, separators=(',', ':'), ensure_ascii=True)
    
    # 3. SHA-256 hash
    digest = hashlib.sha256(canonical.encode('utf-8')).hexdigest()
    
    return f"sha256:{digest}"

def compute_content_hash(file_path: str) -> str:
    """Compute SHA-256 hash of an artifact file."""
    h = hashlib.sha256()
    with open(file_path, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            h.update(chunk)
    return f"sha256:{h.hexdigest()}"
```

### 4.3 Hash Chain Construction

```python
def append_entry(ledger_path: str, entry_data: dict, prev_hash: str) -> dict:
    """Construct and append a new ledger entry."""
    entry = {
        **entry_data,
        'prev_hash': prev_hash,
    }
    entry['entry_hash'] = compute_entry_hash(entry)
    
    # Serialize as single JSONL line
    line = json.dumps(entry, separators=(',', ':'), ensure_ascii=True) + '\n'
    
    # Atomic append (see Section 5)
    with open(ledger_path, 'a') as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX)
        try:
            f.write(line)
            f.flush()
            os.fsync(f.fileno())
        finally:
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    
    return entry
```

---

## 5. File-Based Implementation

### 5.1 Storage: Single Global Ledger File

**Recommendation: Single `global-ledger.jsonl` file.**

```
.agent-runtime/
  ledger/
    global-ledger.jsonl      # The hash-chained append-only ledger
    ledger-index.jsonl        # Action-keyed index for fast lookups
    ledger.meta.json          # Metadata: last sequence, last hash, entry count
```

**Why single file over per-action files:**
- Hash chain requires a global ordering — per-action files would need their own chains, and cross-action events (e.g., "concurrent approval conflicts") would be invisible
- Simpler to verify: one chain to walk
- Simpler to implement: one file handle, one lock
- Simpler to archive: copy one file
- The expected volume is modest: even aggressive agent use produces ~50-200 events/day, or ~5-20KB/day. A year of heavy use is ~5-7MB. File size is not a concern for MVP.

### 5.2 Index File

The index file enables O(1) lookups by action_id without scanning the entire ledger:

```json
{"action_id": "snowflake-validate-member-counts", "sequences": [5, 8, 12, 15, 18], "current_state": "EXECUTION_FINISHED", "last_updated": "2026-03-13T14:30:00.000Z"}
{"action_id": "terraform-plan-infra-prod", "sequences": [6, 9, 13], "current_state": "APPROVAL_GRANTED", "last_updated": "2026-03-13T14:25:00.000Z"}
```

The index is **derived** from the ledger and can be rebuilt at any time by scanning the ledger. It is a performance optimization, not a source of truth.

### 5.3 Metadata File

```json
{
  "last_sequence": 42,
  "last_hash": "sha256:1a2b3c4d5e6f...",
  "entry_count": 43,
  "created_at": "2026-03-13T14:00:00.000Z",
  "last_modified": "2026-03-13T14:30:00.000Z",
  "version": 1
}
```

This avoids reading the entire ledger file just to get the last hash for appending. Updated atomically after each append.

### 5.4 Concurrent Write Handling

The runtime is a single-process host-side service, so true concurrent writes are unlikely. However, race conditions can occur if the CLI and watcher both attempt to write simultaneously.

**Recommended approach: `fcntl.flock()` with exclusive lock**

```python
import fcntl
import os

def atomic_append(ledger_path: str, line: str):
    """Append a single line to the ledger with file locking."""
    with open(ledger_path, 'a') as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX)
        try:
            f.write(line)
            f.flush()
            os.fsync(f.fileno())  # Ensure written to disk
        finally:
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)
```

**Why fcntl.flock over alternatives:**
- `fcntl.flock()` is advisory but sufficient since all writers are our own code
- POSIX `O_APPEND` guarantees atomic positioning (kernel moves file pointer to end before write), but does NOT guarantee atomic multi-byte writes on all filesystems
- `fcntl.flock()` + `O_APPEND` + `fsync` provides the strongest local-filesystem guarantees
- No external dependency (part of Python stdlib and POSIX)

**fsync is important:** Without fsync, a crash can lose buffered writes. Since the ledger is the source of truth for security-critical operations, every append must be durable.

### 5.5 Corruption Recovery

**Partial write detection:**
JSONL makes corruption detection easy — each line must be valid JSON. A partial write results in a truncated final line that fails JSON parsing.

**Recovery algorithm:**
```python
def recover_ledger(ledger_path: str) -> tuple[list[dict], int]:
    """Read ledger, handling truncated final line.
    
    Returns (valid_entries, num_corrupted_lines).
    """
    entries = []
    corrupted = 0
    
    with open(ledger_path, 'r') as f:
        for line_num, line in enumerate(f):
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                entries.append(entry)
            except json.JSONDecodeError:
                corrupted += 1
                # Only the last line should ever be corrupt (partial write)
                # If corruption is mid-file, this is evidence of tampering
                if line_num < count_lines(ledger_path) - 1:
                    raise LedgerTamperError(
                        f"Corruption at line {line_num} (not last line) — "
                        f"possible tampering"
                    )
    
    return entries, corrupted
```

**Gap handling:** If the process crashes between writing a `REQUEST_OBSERVED` and an `APPROVAL_GRANTED`, the chain still has valid entries — it just shows the action stalled. The verify command should flag actions in unexpected states (e.g., `EXECUTION_STARTED` with no subsequent `EXECUTION_FINISHED`) as warnings, not errors.

### 5.6 Rotation and Archival

**For MVP:** No rotation needed. At ~5-20KB/day, the ledger file stays small for years.

**For scale (post-MVP):** Use checkpoint entries to enable rotation:

1. Write a `CHECKPOINT` entry containing the Merkle root of all entries up to that point
2. Archive entries before the checkpoint to a dated archive file
3. New ledger file starts with the checkpoint entry as its genesis

```
.agent-runtime/
  ledger/
    global-ledger.jsonl                    # Active ledger (since last checkpoint)
    archive/
      ledger-2026-01-01-to-2026-06-30.jsonl  # Archived segment
      ledger-2026-01-01-to-2026-06-30.meta.json  # Segment metadata + checkpoint hash
```

The checkpoint hash links the archived segment to the active ledger, maintaining the full chain of trust.

---

## 6. Signing & Verification Tiers

### 6.1 Tier 1: SHA-256 Chain Integrity (MVP)

No keys, no signatures. Pure hash chaining.

**What it provides:**
- Tamper evidence: any modification breaks the chain
- Ordering proof: entries are in a deterministic sequence
- Content binding: each entry's hash covers all its fields

**What it does NOT provide:**
- Attribution: cannot prove WHO wrote an entry (just that it wasn't modified after)
- Non-repudiation: an insider with file access could rewrite the entire chain

**Sufficient for MVP** because: the runtime is single-machine, the human operator is the approver, and the primary threat model is the sandboxed agent — not sophisticated insider attacks.

### 6.2 Tier 2: HMAC with Local Key (Recommended Near-Term Enhancement)

Add an HMAC signature to each entry using a key stored outside the shared workspace:

```python
import hmac

def compute_hmac(entry_hash: str, key: bytes) -> str:
    return hmac.new(key, entry_hash.encode(), hashlib.sha256).hexdigest()
```

**Key storage:** `~/.agent-runtime-key` (host-only, not in shared workspace, not accessible to agent container).

**What it adds:** Proof that entries were written by the host runtime (which holds the key), not by the agent.

### 6.3 Tier 3: GPG Signing (Post-MVP)

Claudio already supports GPG for git commits. Extend this to ledger entries:

```python
def gpg_sign_entry(entry_hash: str) -> str:
    """Create a detached GPG signature of the entry hash."""
    result = subprocess.run(
        ['gpg', '--detach-sign', '--armor', '--output', '-'],
        input=entry_hash.encode(),
        capture_output=True
    )
    return result.stdout.decode()
```

**What it adds:** Non-repudiation tied to the approver's GPG identity. This is the same trust model as signed git commits.

### 6.4 Tier 4: Sigstore Keyless Signing (Future)

Sigstore provides keyless signing via OIDC identity (GitHub, Google, Microsoft). The signer authenticates with their identity provider, gets a short-lived certificate from Fulcio, signs the entry, and discards the key. The signature is logged in Rekor (a transparency log).

**When to consider:** When the system needs to provide externally verifiable audit trails (e.g., for compliance or multi-team scenarios). Requires network access, so not suitable for fully offline operation.

---

## 7. Verification Commands

### 7.1 `verify` — Full Chain Integrity Check

```
agent-runtime verify [--verbose]
```

**Algorithm:**
```python
def verify_chain(ledger_path: str) -> VerifyResult:
    entries = read_all_entries(ledger_path)
    expected_prev = "GENESIS"
    
    for i, entry in enumerate(entries):
        # 1. Check sequence is monotonic
        if entry['sequence'] != i:
            return VerifyResult(valid=False, error=f"Sequence gap at position {i}")
        
        # 2. Check prev_hash links correctly
        if entry['prev_hash'] != expected_prev:
            return VerifyResult(valid=False, error=f"Chain break at sequence {i}: "
                f"expected prev_hash={expected_prev}, got {entry['prev_hash']}")
        
        # 3. Recompute entry_hash and compare
        computed = compute_entry_hash(entry)
        if computed != entry['entry_hash']:
            return VerifyResult(valid=False, error=f"Hash mismatch at sequence {i}: "
                f"computed={computed}, stored={entry['entry_hash']}")
        
        expected_prev = entry['entry_hash']
    
    return VerifyResult(valid=True, entries_checked=len(entries))
```

**Output:**
```
Ledger integrity: VALID
  Entries checked: 42
  Chain unbroken: sequence 0 → 41
  First entry: 2026-03-13T14:00:00.000Z (LEDGER_INITIALIZED)
  Last entry: 2026-03-13T14:30:00.000Z (RESULT_RECORDED)
```

### 7.2 `audit <action>` — Action Lifecycle Trace

```
agent-runtime audit snowflake-validate-member-counts [--format json|table]
```

**Algorithm:** Filter ledger entries by `action_id`, display in sequence order.

**Output:**
```
Action: snowflake-validate-member-counts
Status: EXECUTION_FINISHED (exit code 0)
Events: 5

  #5  REQUEST_OBSERVED     2026-03-13T14:10:00Z  actor=agent:claude
      content_hash: sha256:a1b2c3...
  #8  APPROVAL_GRANTED     2026-03-13T14:15:00Z  actor=user:kscherer
      approved content: sha256:a1b2c3... (matches request)
  #12 EXECUTION_STARTED    2026-03-13T14:15:05Z  actor=system:runtime
      runner: snowflake_sql, execution_id: abc-123
  #15 EXECUTION_FINISHED   2026-03-13T14:15:09Z  actor=system:runtime
      exit_code: 0, duration: 4523ms
  #18 RESULT_RECORDED      2026-03-13T14:15:10Z  actor=system:runtime
      outputs: stdout.log (sha256:d4e5f6...), result.json (sha256:7a8b9c...)
```

### 7.3 `integrity` — Artifact Integrity Check

```
agent-runtime integrity [--action <name>] [--fix-index]
```

**Algorithm:**
1. Walk the ledger
2. For every content_hash and output_hash reference, verify the corresponding file exists and its current hash matches the recorded hash
3. Report any mismatches (file modified since recorded) or missing files

**Output:**
```
Artifact integrity check:
  Actions checked: 3
  Files verified: 12
  
  PASS: snowflake-validate-member-counts/request.sql matches sha256:a1b2c3...
  PASS: snowflake-validate-member-counts/stdout.log matches sha256:d4e5f6...
  WARN: terraform-plan-infra-prod/stdout.log MISSING (recorded in sequence #30)
  FAIL: terraform-plan-infra-prod/request.sh MODIFIED
        Recorded: sha256:1a2b3c...
        Current:  sha256:9f8e7d...
        (File was modified after execution — possible unauthorized change)
```

### 7.4 Gap Detection

Events should follow valid state transitions. The verify command checks for:

| Current State | Valid Next States |
|---|---|
| `REQUEST_OBSERVED` | `APPROVAL_GRANTED`, `APPROVAL_REJECTED`, `REQUEST_OBSERVED` (re-edit) |
| `APPROVAL_GRANTED` | `EXECUTION_STARTED` |
| `APPROVAL_REJECTED` | `REQUEST_OBSERVED` (re-edit) |
| `EXECUTION_STARTED` | `EXECUTION_FINISHED` |
| `EXECUTION_FINISHED` | `RESULT_RECORDED` |
| `RESULT_RECORDED` | `REQUEST_OBSERVED` (next iteration) |

Entries outside this state machine are flagged as warnings (crash recovery) or errors (possible tampering).

---

## 8. Implementation Approach

### 8.1 Module Structure (Python/FastAPI)

```
agent_runtime/
  ledger/
    __init__.py
    schema.py          # Pydantic models for entry types
    writer.py          # Append entries with locking + hashing
    reader.py          # Read, filter, project state from entries
    verifier.py        # Chain verification + artifact integrity
    index.py           # Index maintenance and rebuild
    canonical.py       # Canonical JSON serialization
```

### 8.2 Key Classes

```python
# schema.py
from enum import Enum
from pydantic import BaseModel

class EventType(str, Enum):
    LEDGER_INITIALIZED = "LEDGER_INITIALIZED"
    REQUEST_OBSERVED = "REQUEST_OBSERVED"
    APPROVAL_GRANTED = "APPROVAL_GRANTED"
    APPROVAL_REJECTED = "APPROVAL_REJECTED"
    EXECUTION_STARTED = "EXECUTION_STARTED"
    EXECUTION_FINISHED = "EXECUTION_FINISHED"
    RESULT_RECORDED = "RESULT_RECORDED"

class LedgerEntry(BaseModel):
    version: int = 1
    sequence: int
    timestamp: str
    timestamp_ms: int
    event_type: EventType
    action_id: str
    execution_id: str | None = None
    actor: str
    content_hash: str | None = None
    data: dict
    prev_hash: str
    entry_hash: str
```

### 8.3 Dependencies

**Standard library only for MVP:**
- `hashlib` — SHA-256 hashing
- `json` — JSON serialization (with `sort_keys=True` for canonical form)
- `fcntl` — File locking (POSIX only, but this runs on Linux)
- `os` — fsync

**Optional (recommended):**
- `rfc8785` — RFC 8785 canonical JSON (pip package by Trail of Bits, pure Python, zero deps)
- `pydantic` — Already available via FastAPI, used for entry schema validation

No external database, no message queue, no distributed system dependencies.

---

## 9. Reference Implementations & Inspiration

### 9.1 Git Object Model
Git's commit chain is the closest analogy. Each commit contains parent hash + tree hash + metadata, creating a hash-chained DAG. Our ledger is a linear variant (no branching). Git's design proves this pattern works at massive scale with pure filesystem storage.

### 9.2 Certificate Transparency (RFC 6962)
Uses append-only Merkle trees with signed tree heads. Relevant for the post-MVP Merkle tree enhancement, but overkill for single-machine use.

### 9.3 Trillian (transparency.dev)
Google's open-source verifiable data store. Implements append-only logs with Merkle trees. Written in Go. Too heavyweight to use directly, but its design documents are excellent reference material for the Merkle tree layer if/when needed.

### 9.4 janos/hashchain (Go library)
Compact append-only log with fixed-size records: [timestamp | message | hash]. Each hash is `H(prev_hash || timestamp || message)`. Zero-hash genesis. Simple sequential verification. Good conceptual reference but Go-only and fixed record size doesn't suit our variable JSON entries.

### 9.5 AuditableLLM (2025 paper)
Academic framework for auditing LLM operations using hash-chain-backed JSONL. Very close to our use case. Uses SHA-256, canonical JSON, and append-only JSONL manifest. Confirms our approach is aligned with current research.

---

## 10. Key Design Decisions for the Planner

### 10.1 Single file vs per-action ledgers

**Recommendation: Single global file.** Per-action files fragment the hash chain and make cross-action verification impossible. A global chain provides a total ordering of all events, which is essential for auditing temporal relationships ("was this approval granted before or after that other request was modified?").

### 10.2 Hash algorithm

**Recommendation: SHA-256.** It's the standard, it's fast enough, it's available in Python stdlib, and it's what Git is migrating to. SHA-512 offers no practical benefit for this use case. BLAKE3 is faster but less widely recognized.

### 10.3 Canonical serialization

**Recommendation: `json.dumps(sort_keys=True, separators=(',',':'))` for MVP.** Upgrade to RFC 8785 (`rfc8785` package) if/when floating point numbers enter the schema. The simpler approach is correct for our current schema (strings, integers, booleans only).

### 10.4 Content hash prefix

**Recommendation: Always prefix hashes with algorithm, e.g., `sha256:a1b2c3...`.** This is forward-compatible — if we ever migrate to a different hash algorithm, old entries remain self-describing.

### 10.5 Timestamp format

**Recommendation: Store both ISO 8601 string AND Unix epoch milliseconds.** ISO for human readability in CLI output and diffs. Epoch ms for machine sorting and comparison without date parsing.

### 10.6 GENESIS constant

**Recommendation: Use the string literal `"GENESIS"` (not zero bytes, not null).** It's human-readable in the JSONL file, unambiguous, and trivially checkable. The janos/hashchain approach of zero bytes works for binary formats but is less clear in JSON.

### 10.7 Index rebuild vs incremental

**Recommendation: Incremental index updates after each append, with a full rebuild command for recovery.** The index is a derived data structure. If it gets corrupted, `agent-runtime verify --fix-index` rebuilds it from the ledger.

### 10.8 What if the ledger file doesn't exist?

Auto-initialize with a `LEDGER_INITIALIZED` genesis entry on first access. The runtime should never fail because the ledger file is missing — it should create it.

---

## 11. Security Considerations

### 11.1 Threat model for MVP

The primary threat is the **sandboxed agent** attempting to:
- Forge approval entries
- Modify request artifacts after approval
- Delete or modify ledger entries to hide activity

**Mitigation:** The ledger file lives in `.agent-runtime/ledger/` which is in the shared workspace. For MVP, the agent CAN read the ledger (for transparency) but should NOT be able to write to it. This is enforced by:
1. File permissions: ledger owned by host user, not the container user
2. Mount configuration: mount the ledger directory as read-only for the agent container, or use a separate mount point

### 11.2 Insider threat (post-MVP)

A malicious host-side operator could rewrite the entire ledger. HMAC signing (Tier 2) prevents this unless the key is also compromised. GPG signing (Tier 3) provides stronger non-repudiation tied to individual identity.

### 11.3 Clock manipulation

Timestamps are recorded by the host runtime. If the host clock is manipulated, timestamps are unreliable. Mitigation: the sequence number provides tamper-evident ordering independent of timestamps. For strong guarantees, integrate with an external timestamping authority (post-MVP).

---

## 12. Performance Characteristics

| Operation | Complexity | Expected Latency |
|---|---|---|
| Append entry | O(1) | <1ms (plus ~1-5ms for fsync) |
| Read last hash | O(1) via meta file | <1ms |
| Verify full chain | O(n) | ~10ms per 1000 entries |
| Audit single action | O(n) scan or O(1) via index | <1ms with index |
| Integrity check | O(n × files) | ~10ms per file |
| Rebuild index | O(n) | ~50ms per 1000 entries |

At expected volumes (~50-200 entries/day), all operations are effectively instant.

---

## Sources

- [Building a Tamper-Evident Audit Log with SHA-256 Hash Chains](https://dev.to/veritaschain/building-a-tamper-evident-audit-log-with-sha-256-hash-chains-zero-dependencies-h0b)
- [Building Tamper-Evident Audit Trails: Cryptographic Logging for AI Systems](https://dev.to/veritaschain/building-tamper-evident-audit-trails-a-developers-guide-to-cryptographic-logging-for-ai-systems-4o64)
- [How to Design Tamper-Evident Audit Logs](https://www.designgurus.io/answers/detail/how-do-you-design-tamperevident-audit-logs-merkle-trees-hashing)
- [RFC 8785: JSON Canonicalization Scheme](https://www.rfc-editor.org/rfc/rfc8785)
- [rfc8785.py — Trail of Bits Python implementation](https://github.com/trailofbits/rfc8785.py)
- [json-canonicalize npm package](https://www.npmjs.com/package/json-canonicalize)
- [Trillian — Open-source append-only ledger](https://transparency.dev/)
- [janos/hashchain — Go hash chain library](https://github.com/janos/hashchain)
- [Git Internals: The Git Object Model](https://dev.to/calebsander/git-internals-part-1-the-git-object-model-474m)
- [Git Objects — Official Documentation](https://git-scm.com/book/en/v2/Git-Internals-Git-Objects)
- [AuditableLLM: Hash-Chain-Backed Auditable Framework](https://www.mdpi.com/2079-9292/15/1/56)
- [Appending to a Log: Linux Dark Arts](https://pvk.ca/Blog/2021/01/22/appending-to-a-log-an-introduction-to-the-linux-dark-arts/)
- [Event Sourcing Pattern — Microsoft Azure](https://learn.microsoft.com/en-us/azure/architecture/patterns/event-sourcing)
- [Sigstore Overview](https://docs.sigstore.dev/cosign/signing/overview/)
- [Cossack Labs: Audit Logs Security](https://www.cossacklabs.com/blog/audit-logs-security/)
- [JSONL Format Specification](https://jsonlines.org/)
- [Python hashlib Documentation](https://docs.python.org/3/library/hashlib.html)
