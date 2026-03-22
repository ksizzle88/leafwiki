# Diff Viewer Components & Approval Workflow UI

**Research for**: Agent Permissions Gateway (Issue #59, Epic #55)
**Date**: 2026-03-13
**Context**: The Permissions Gateway needs a diff view for reviewing agent request artifacts before approval, and an approval workflow dashboard integrated into the Dev Toolkit (React + Vite + shadcn/ui frontend, FastAPI backend).

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Diff Viewer Component Comparison](#2-diff-viewer-component-comparison)
3. [Diff Algorithm Libraries](#3-diff-algorithm-libraries)
4. [Approval Workflow UI Patterns](#4-approval-workflow-ui-patterns)
5. [Real-Time Update Strategy](#5-real-time-update-strategy)
6. [Dashboard Component Architecture](#6-dashboard-component-architecture)
7. [Multi-Language Diff Handling](#7-multi-language-diff-handling)
8. [Recommended Architecture](#8-recommended-architecture)

---

## 1. Executive Summary

**Recommendation: `react-diff-viewer-continued` as the primary diff component, with `jsdiff` as the underlying diff engine, inside a shadcn/ui-based approval dashboard. Real-time updates via Server-Sent Events (SSE) from FastAPI.**

This combination offers:
- Lightweight bundle (~50KB total for diff viewer + jsdiff)
- Split and unified diff views with syntax highlighting
- Virtualization for large diffs (request.sh or request.sql can be long)
- Simple API that takes two strings (old value, new value) — matches the "last approved version vs current version" workflow exactly
- No dependency on git unified diff format — the system generates diffs from raw text, not from git
- SSE provides simpler, more reliable real-time updates than WebSocket for a unidirectional notification pattern

**Why not Monaco DiffEditor**: At ~5MB, it is far too heavy for an approval dashboard that shows diffs of shell scripts and SQL queries. Monaco is the right choice for a full code editor, but this is a review-only view.

**Why not CodeMirror merge view**: Better than Monaco in size (~50KB), but it is designed for editable merge conflicts, not read-only review. Adds unnecessary complexity for a non-editable approval diff.

**Why not @git-diff-view/react**: Good library (15KB core, GitHub-style), but it requires input in unified diff format, which means we would need to generate git-style unified diffs from our raw text files. Since the permissions gateway compares raw text (last approved content vs current content), a library that takes two strings directly is simpler.

---

## 2. Diff Viewer Component Comparison

### 2.1 react-diff-viewer-continued (RECOMMENDED)

**Package**: `react-diff-viewer-continued`
**Latest version**: 4.2.0 (published March 2026 — actively maintained)
**Bundle size**: ~45KB gzipped (with jsdiff dependency)
**License**: MIT

**Key Features:**
- Split view (side-by-side) and unified view
- Word-level diff highlighting within changed lines
- Line numbers with expand/collapse for unchanged sections
- Virtualization with infinite loading for large files (thousands of lines)
- Optimized structural comparison for JSON/YAML files
- Custom syntax highlighting via render prop: `renderContent(content: string) => JSX.Element`
- Customizable styles via `styles` prop (override with Object.assign)
- Column titles for split view sections

**API (simplified):**
```tsx
import ReactDiffViewer from 'react-diff-viewer-continued';

<ReactDiffViewer
  oldValue={lastApprovedContent}    // string
  newValue={currentRequestContent}  // string
  splitView={true}                  // true = side-by-side, false = unified
  showDiffOnly={false}              // show full file or only changed sections
  useDarkTheme={true}               // theme support
  leftTitle="Last Approved"
  rightTitle="Current Request"
  renderContent={(str) => (         // syntax highlighting hook
    <SyntaxHighlighter language={lang}>{str}</SyntaxHighlighter>
  )}
/>
```

**Why it fits the Permissions Gateway:**
- Takes two raw strings — exactly what we have (last approved content hash → content, current request file content)
- No need to generate unified diffs or git-format patches
- Lightweight enough for a dashboard panel
- Split view lets reviewer see old vs new side-by-side
- JSON/YAML optimization is valuable for `request.meta.json` diffs

**Forks/History:**
The original `react-diff-viewer` by praneshr is unmaintained (last publish 2021). There are multiple forks:
- `react-diff-viewer-continued` by Aeolun — most active, v4.x with virtualization
- `react-diff-viewer-continued` by amplication — corporate fork, also active
- `react-diff-viewer-continued` by SiebeVE — less active

The Aeolun fork is the canonical continuation and the one published to npm.

### 2.2 @git-diff-view/react

**Package**: `@git-diff-view/react`
**Latest version**: Recent (2025-2026)
**Bundle size**: ~15KB core, ~40KB with syntax highlighting
**License**: MIT

**Key Features:**
- GitHub-exact UI styling (closest visual match to GitHub's diff view)
- Split and unified views
- Syntax highlighting via HAST AST (lowlight or shiki backends)
- Virtual scrolling for large diffs
- SSR and React Server Components support
- Web worker support for off-main-thread diffing
- Light and dark themes
- 60fps scroll performance

**Strengths:**
- Most visually polished GitHub-style diff
- Best performance numbers (280ms initial render, 28MB memory)
- Framework-agnostic (React, Vue, Solid, Svelte packages)

**Weaknesses:**
- **Requires unified diff format as input** — would need to convert raw text pairs to unified diff format before passing to the component, adding a conversion step
- More complex API (parse diff → pass to component)
- Younger library with smaller community

**When to choose:** If the system later needs to display actual git diffs (e.g., showing code changes in agent-modified files), this would be the better choice. For the approval flow's "old text vs new text" use case, it adds unnecessary complexity.

### 2.3 Monaco DiffEditor

**Package**: `@monaco-editor/react` (exports `DiffEditor` component)
**Bundle size**: ~5MB (the full Monaco editor)
**License**: MIT

**Key Features:**
- Identical to VS Code's diff view
- Full language support (100+ languages with IntelliSense)
- Side-by-side and inline diff modes
- Character-level diff highlighting
- Minimap in diff view
- Folding, bracket matching, search in diff

**API:**
```tsx
import { DiffEditor } from '@monaco-editor/react';

<DiffEditor
  original={lastApprovedContent}
  modified={currentRequestContent}
  language="sql"
  theme="vs-dark"
  options={{ readOnly: true, renderSideBySide: true }}
/>
```

**Strengths:**
- Most feature-complete diff viewer available
- Perfect syntax highlighting for every language
- Already needed if the toolkit includes a code editor tool

**Weaknesses:**
- ~5MB bundle is extreme for a review-only diff panel
- Loads asynchronously (web worker for language services)
- Heavy DOM footprint — multiple instances on one page degrade performance
- Overkill for reviewing 20-line SQL queries or shell scripts

**When to choose:** Only if the Dev Toolkit is already loading Monaco for another tool (e.g., Markdown Editor). In that case, the marginal cost of using DiffEditor is zero since Monaco is already loaded. But for the Permissions Gateway as a standalone plugin, it is too heavy.

### 2.4 CodeMirror 6 Merge View

**Package**: `@codemirror/merge` + `react-codemirror-merge` (React wrapper)
**Latest version**: 6.12.0 (March 2026 — actively maintained)
**Bundle size**: ~50KB gzipped (CodeMirror core + merge extension)
**License**: MIT

**Key Features:**
- Unified merge view (shows changes inline in a single editor)
- Split merge view via MergeView class
- Editable diffs — user can modify content before accepting
- Full CodeMirror 6 extension ecosystem (syntax highlighting, search, etc.)
- Designed for merge conflict resolution

**API (React wrapper):**
```tsx
import CodeMirrorMerge from 'react-codemirror-merge';
const { Original, Modified } = CodeMirrorMerge;

<CodeMirrorMerge>
  <Original value={lastApprovedContent} />
  <Modified value={currentRequestContent} />
</CodeMirrorMerge>
```

**Strengths:**
- Lighter than Monaco (~50KB vs ~5MB)
- Editable diffs could be useful if we later want "approve with modifications"
- Good syntax highlighting via CodeMirror language packages
- Modular architecture — load only what you need

**Weaknesses:**
- Designed for merge/editing, not read-only review
- More setup complexity than react-diff-viewer-continued
- The unified merge view extension (`unifiedMergeView`) is less intuitive for review than a true split diff
- No built-in word-level diff highlighting
- Smaller community for the merge-specific package (64 downstream dependents)

**When to choose:** If the system later needs "approve with modifications" (reviewer edits the request before approving), CodeMirror merge view becomes the right choice. For read-only review in MVP, it is over-engineered.

### 2.5 diff2html

**Package**: `diff2html` + `react-gh-like-diff` (React wrapper)
**Bundle size**: ~35KB gzipped
**License**: MIT

**Key Features:**
- Converts unified diff format to styled HTML
- Side-by-side and line-by-line views
- Syntax highlighting support
- Framework-agnostic (HTML output, wrap in React)
- Used by many Git web UIs

**Strengths:**
- Battle-tested (used by GitLab, Bitbucket, and many Git UIs)
- Good visual output
- Supports file-level diff headers and stats (+/- lines)

**Weaknesses:**
- **Requires unified diff format as input** — same issue as @git-diff-view/react
- React wrapper (`react-gh-like-diff`) is not actively maintained
- Need to generate unified diffs from raw text (adds `jsdiff` dependency anyway)
- Framework-agnostic means no React-optimized rendering (dangerouslySetInnerHTML)

**When to choose:** If you are already working with git-format unified diffs. Not ideal for raw text comparison.

### Comparison Matrix

| Criterion | react-diff-viewer-continued | @git-diff-view/react | Monaco DiffEditor | CodeMirror Merge | diff2html |
|---|---|---|---|---|---|
| **Bundle size** | ~45KB gz | ~15-40KB gz | ~5MB | ~50KB gz | ~35KB gz |
| **Input format** | Two strings | Unified diff | Two strings | Two strings | Unified diff |
| **Split view** | Yes | Yes | Yes | Yes (MergeView) | Yes |
| **Unified view** | Yes | Yes | Yes (inline) | Yes (extension) | Yes |
| **Word-level diff** | Yes (built-in) | Yes | Yes | No | Yes |
| **Virtualization** | Yes (v4+) | Yes | Yes (Monaco) | No | No |
| **Syntax highlight** | Via render prop | Via HAST/shiki | Built-in (100+ langs) | Via CM lang packages | Via highlight.js |
| **Editable** | No (read-only) | No (read-only) | Optional | Yes (default) | No |
| **JSON/YAML optimized** | Yes | No | No | No | No |
| **React integration** | Native React | Native React | Native React | Via wrapper | Via wrapper (stale) |
| **Active maintenance** | Yes (v4.2.0, Mar 2026) | Yes (2025-2026) | Yes (Microsoft) | Yes (v6.12.0) | Yes (core) |
| **Community size** | Large (continuation of popular lib) | Growing | Massive | Medium | Large |

---

## 3. Diff Algorithm Libraries

### 3.1 jsdiff (RECOMMENDED as underlying engine)

**Package**: `diff` (npm name)
**Latest version**: 8.x (ships with TypeScript types)
**Bundle size**: ~15KB gzipped
**License**: BSD-3-Clause

**Algorithm**: Myers' O(ND) Difference Algorithm with optimizations for diagonal tracking.

**Key Methods:**
| Method | Granularity | Use Case |
|--------|------------|----------|
| `diffChars(old, new)` | Character | Highlight exact character changes in SQL/shell |
| `diffWords(old, new)` | Word | Word-level changes (good for prose in PURPOSE.md) |
| `diffWordsWithSpace(old, new)` | Word + whitespace | Whitespace-significant comparisons |
| `diffLines(old, new)` | Line | Standard line diff (shell scripts) |
| `diffTrimmedLines(old, new)` | Line (trimmed) | Ignore leading/trailing whitespace |
| `createPatch(filename, old, new)` | Unified patch | Generate unified diff format for git-style display |
| `structuredPatch(oldFile, newFile, old, new)` | Structured | Programmatic access to hunks |

**Advanced Features:**
- Async mode via callback option (for large diffs without blocking UI)
- Abortable mode via `timeout` or `maxEditLength` properties
- `oneChangePerToken` option for granular change tracking

**Why it fits:** react-diff-viewer-continued uses jsdiff internally. Having jsdiff as an explicit dependency also lets us:
- Pre-compute diffs on the server (FastAPI can call a Python diff library, or the API returns raw content and the frontend diffs with jsdiff)
- Generate unified patches if we later need to feed them to @git-diff-view or diff2html
- Provide character-level highlighting within changed lines

### 3.2 diff-match-patch (Google)

**Package**: `diff-match-patch`
**Bundle size**: ~50KB
**Algorithm**: Myers + Semantic cleanup + Efficiency cleanup

Overkill for this use case. Designed for collaborative editing (Google Docs-style operational transforms). The semantic cleanup phase rewrites diffs to be more "human readable" but at significant computational cost. Not needed for reviewing shell scripts and SQL.

### 3.3 fast-diff

**Package**: `fast-diff`
**Bundle size**: ~3KB
**Algorithm**: Myers (optimized for speed)

Very fast but only operates at character level. No line-level or word-level diffing. Too low-level for our needs.

---

## 4. Approval Workflow UI Patterns

### 4.1 Terraform Cloud / HCP Terraform

**Pattern**: Plan → Review → Approve → Apply

**UI Elements:**
- **Plan output panel**: Shows resources to create, modify, and destroy with color coding (green/yellow/red)
- **Resource summary**: "+2 to add, ~1 to change, -1 to destroy" at the top
- **Expandable resource details**: Each resource change can be expanded to see attribute-level diffs
- **Cost estimation panel**: Estimated cost change alongside the plan (post-MVP for us)
- **Policy check results**: Sentinel policy pass/fail indicators before approval is allowed
- **Approve/Discard buttons**: Clear binary action with optional comment
- **Run queue**: Shows pending, planning, applying, applied, errored states

**Applicable to Permissions Gateway:**
- **Resource summary → Action summary**: Show what runner will execute, what changed
- **Expandable details → Diff panel**: Expand to see full diff of request artifact
- **Policy checks → Hash verification**: Show content hash verification status
- **Approve/Discard → Approve/Reject**: Same pattern with comment support

### 4.2 GitHub Pull Request Review

**Pattern**: Files Changed → Review → Approve/Request Changes

**UI Elements:**
- **File tree sidebar**: List of changed files with addition/deletion indicators
- **Per-file diff panels**: Expandable diff view for each file
- **Line-level comments**: Click a line to add a review comment
- **Review summary**: Approve, Request Changes, or Comment with summary text
- **Status checks**: CI/CD pass/fail badges before merge allowed
- **Conversation thread**: Timeline of review events

**Applicable to Permissions Gateway:**
- **File list → Action list**: Dashboard listing all pending actions
- **Per-file diff → Per-action diff**: Each action's request artifact diff
- **Status checks → Ledger verification**: Chain integrity status
- **Conversation → Action history**: Timeline of request, approval, execution events

### 4.3 ArgoCD Sync

**Pattern**: Detect Drift → Show Diff → Sync (Apply)

**UI Elements:**
- **Application card**: Health status (Healthy/Degraded/Missing) and sync status (Synced/OutOfSync)
- **App Diff button**: Shows what differs between desired state (Git) and live state (cluster)
- **Resource tree**: Hierarchical view of Kubernetes resources with status indicators
- **Sync dialog**: Select resources to sync, choose sync options (prune, force, dry-run)
- **Timeline**: Event history for the application

**Applicable to Permissions Gateway:**
- **Health/Sync status → Action status**: pending, approved, running, completed, failed
- **App Diff → Request Diff**: Compare last approved vs current request
- **Sync dialog → Run dialog**: Confirm execution with options
- **Resource tree → Action tree**: Hierarchical view if actions have sub-actions (post-MVP)

### 4.4 Atlantis (Terraform in PRs)

**Pattern**: Plan as PR Comment → Approve via Comment → Apply

**UI Elements:**
- **PR comment with plan output**: Full terraform plan embedded in PR comment
- **`atlantis apply` command**: Comment-based approval (type a command to approve)
- **Lock indicator**: Shows who currently has a lock on the workspace
- **Plan status badges**: Pass/fail indicators in PR status checks

**Applicable to Permissions Gateway (CLI mode):**
- Atlantis's approach maps well to the CLI approval workflow: `agent-runtime approve <action>`
- Lock concept maps to "only one pending request per action slot"

### 4.5 Rundeck Job Execution

**Pattern**: Define Job → Execute → View Output

**UI Elements:**
- **Job list with status**: Grid of jobs with last run status and timing
- **Execution log viewer**: Real-time streaming output with ANSI color support
- **Node status**: Which nodes executed successfully/failed
- **Approval gate**: Require approval before job proceeds to next step

**Applicable to Permissions Gateway:**
- **Execution log → stdout/stderr viewer**: Stream execution output in real-time
- **Node status → Runner status**: Show which runner is executing
- **Job history → Action history**: Execution timeline per action

### 4.6 Synthesized Pattern for Permissions Gateway

Based on the patterns above, the Permissions Gateway approval UI should follow a **three-panel layout**:

```
┌─────────────────────────────────────────────────────────────────┐
│ Action List (left sidebar)          │ Action Detail (main panel) │
│                                     │                            │
│ ┌─────────────────────────────┐    │ ┌────────────────────────┐ │
│ │ ● terraform-plan-infra-prod │    │ │ Action: snowflake-...  │ │
│ │   RUNNING                   │    │ │ Runner: snowflake_sql  │ │
│ │                             │    │ │ Status: PENDING_REVIEW │ │
│ │ ◉ snowflake-validate-...   │    │ │ Hash: abc123...        │ │
│ │   PENDING_REVIEW ← selected│    │ ├────────────────────────┤ │
│ │                             │    │ │                        │ │
│ │ ✓ dbt-compile-apd          │    │ │   Diff Viewer Panel    │ │
│ │   COMPLETED                 │    │ │  (split or unified)    │ │
│ │                             │    │ │                        │ │
│ │ ✗ shell-cleanup-tmp         │    │ │ Last Approved │Current │ │
│ │   FAILED                    │    │ │   SELECT ...  │SELECT  │ │
│ └─────────────────────────────┘    │ │   FROM tbl   │FROM tbl│ │
│                                     │ │   WHERE x=1  │WHERE.. │ │
│ Filter: [All ▼] [Search...]       │ │               │        │ │
│                                     │ ├────────────────────────┤ │
│                                     │ │ [Approve] [Reject]     │ │
│                                     │ │ Comment: [___________] │ │
│                                     │ ├────────────────────────┤ │
│                                     │ │ Timeline / History     │ │
│                                     │ │ 10:23 REQUEST_OBSERVED │ │
│                                     │ │ 10:20 EXECUTION_DONE   │ │
│                                     │ │ 10:18 APPROVAL_GRANTED │ │
│                                     │ └────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. Real-Time Update Strategy

### 5.1 SSE vs WebSocket for the Permissions Gateway

The Permissions Gateway needs real-time updates for:
1. New request artifacts detected by the file watcher
2. Status changes (pending → approved → running → completed/failed)
3. Execution output streaming (stdout/stderr during execution)

| Criterion | SSE | WebSocket |
|-----------|-----|-----------|
| **Direction** | Server → Client only | Bidirectional |
| **Protocol** | HTTP/1.1 (built on standard HTTP) | Upgrade from HTTP |
| **Auto-reconnect** | Built-in (browser handles) | Manual implementation required |
| **FastAPI support** | Native (StreamingResponse) | Native (WebSocket endpoint) |
| **Proxy/CDN friendly** | Yes (standard HTTP) | Often requires special config |
| **Data format** | Text (event stream) | Text or binary |
| **Connections per domain** | 6 (HTTP/1.1) or unlimited (HTTP/2) | Unlimited |
| **Complexity** | Low | Medium |
| **Performance** | Identical for this use case | Identical for this use case |

**Recommendation: SSE for status updates, WebSocket only for execution output streaming.**

**Rationale:**
- Status updates (new request, approval granted, etc.) are server-to-client only — SSE is perfect
- File watcher events are naturally server-to-client — SSE
- Execution output streaming is server-to-client — SSE works, but WebSocket provides lower latency for high-throughput log streaming
- Client actions (approve, reject) are standard REST POST requests — no need for bidirectional WebSocket

**FastAPI SSE implementation pattern:**
```python
from sse_starlette.sse import EventSourceResponse

@app.get("/api/actions/events")
async def action_events(request: Request):
    async def event_generator():
        while True:
            if await request.is_disconnected():
                break
            event = await action_event_queue.get()
            yield {
                "event": event.type,  # "request_observed", "status_changed", etc.
                "data": event.json(),
                "id": event.id,
            }
    return EventSourceResponse(event_generator())
```

**React client pattern:**
```tsx
useEffect(() => {
  const source = new EventSource('/api/actions/events');
  source.addEventListener('request_observed', (e) => {
    const action = JSON.parse(e.data);
    dispatch({ type: 'ADD_PENDING', payload: action });
  });
  source.addEventListener('status_changed', (e) => {
    const update = JSON.parse(e.data);
    dispatch({ type: 'UPDATE_STATUS', payload: update });
  });
  return () => source.close();
}, []);
```

### 5.2 Alternative: Polling

For MVP simplicity, polling every 1-2 seconds is viable:
- `GET /api/actions` returns all actions with current status
- Frontend diffs the list against its local state
- Simple, no event infrastructure needed
- Works behind any proxy/firewall

**Trade-off:** 1-2 second delay vs real-time. For a human-in-the-loop approval workflow, this delay is imperceptible. SSE is the better long-term choice, but polling is a valid MVP strategy.

---

## 6. Dashboard Component Architecture

### 6.1 shadcn/ui Components for the Approval Dashboard

The following shadcn/ui primitives map directly to Permissions Gateway UI needs:

| UI Need | shadcn/ui Component | Notes |
|---------|---------------------|-------|
| Action list sidebar | `Table` or custom list | Filterable, sortable |
| Status badges | `Badge` | Variants: pending (yellow), approved (blue), running (purple), completed (green), failed (red) |
| Action detail card | `Card` + `CardHeader` + `CardContent` | Title, status, hash, runner info |
| Approve/Reject buttons | `Button` (variant: default/destructive) | Primary approve, destructive reject |
| Comment input | `Textarea` | Optional comment on approve/reject |
| Confirmation dialog | `AlertDialog` | "Are you sure you want to approve execution of hash abc123?" |
| Diff view toggle | `Tabs` ("Split" / "Unified") | Switch diff display mode |
| Timeline | `Timeline` (custom) or vertical list | Ledger events in chronological order |
| Filter/search | `Input` + `Select` | Filter by status, runner type, search by name |
| Hash display | `Badge` (monospace) or `code` element | Truncated with copy button |
| Output viewer | `ScrollArea` with `pre` | stdout/stderr with ANSI color rendering |
| Receipt viewer | `Accordion` or `Collapsible` | Expandable receipt JSON |
| Toast notifications | `Toast` / `Sonner` | "New request detected", "Execution complete" |
| Loading states | `Skeleton` | While fetching action details |

### 6.2 Custom Components to Build

These are not available in shadcn/ui and need to be built:

1. **DiffPanel**: Wrapper around react-diff-viewer-continued with language detection, theme integration, and view mode toggle
2. **ActionStatusIndicator**: Animated status icon (spinner for running, checkmark for complete, X for failed)
3. **HashBadge**: Truncated hash with tooltip showing full hash and copy-to-clipboard
4. **LedgerTimeline**: Vertical timeline rendering ledger entries with icons per event type
5. **OutputStreamer**: Real-time log viewer with ANSI color support (consider `ansi-to-react` package)
6. **ReceiptCard**: Structured display of receipt.json with hash verification indicators

### 6.3 Page Layout

```tsx
// Suggested component hierarchy
<PermissionsGatewayPlugin>
  <ResizablePanelGroup direction="horizontal">
    <ResizablePanel defaultSize={25}>
      <ActionListSidebar
        actions={actions}
        selectedAction={selectedAction}
        onSelect={setSelectedAction}
        filter={filter}
      />
    </ResizablePanel>
    <ResizableHandle />
    <ResizablePanel defaultSize={75}>
      <ActionDetailPanel action={selectedAction}>
        <ActionHeader action={selectedAction} />
        <Tabs defaultValue="diff">
          <TabsList>
            <TabsTrigger value="diff">Diff</TabsTrigger>
            <TabsTrigger value="output">Output</TabsTrigger>
            <TabsTrigger value="receipt">Receipt</TabsTrigger>
            <TabsTrigger value="history">History</TabsTrigger>
          </TabsList>
          <TabsContent value="diff">
            <DiffPanel
              oldValue={lastApprovedContent}
              newValue={currentRequestContent}
              language={action.runner}
            />
            <ApprovalControls action={selectedAction} />
          </TabsContent>
          <TabsContent value="output">
            <OutputViewer stdout={stdout} stderr={stderr} />
          </TabsContent>
          <TabsContent value="receipt">
            <ReceiptCard receipt={receipt} />
          </TabsContent>
          <TabsContent value="history">
            <LedgerTimeline entries={ledgerEntries} />
          </TabsContent>
        </Tabs>
      </ActionDetailPanel>
    </ResizablePanel>
  </ResizablePanelGroup>
</PermissionsGatewayPlugin>
```

---

## 7. Multi-Language Diff Handling

The Permissions Gateway handles multiple artifact types:

| Artifact | Runner | File | Language for Syntax Highlighting |
|----------|--------|------|----------------------------------|
| Shell scripts | `shell` | `request.sh` | `bash` / `shell` |
| SQL queries | `snowflake_sql` | `request.sql` | `sql` |
| Terraform args | `shell` (terraform) | `request.tfargs` | `hcl` or plain text |
| dbt commands | `dbt` | `request.sh` or `request.yml` | `bash` or `yaml` |
| Python scripts | `python` | `request.py` | `python` |
| JSON config | various | `request.json` | `json` |
| Metadata | runtime | `request.meta.json` | `json` |

### Syntax Highlighting Strategy

Use `react-syntax-highlighter` (already commonly paired with react-diff-viewer-continued) with Prism or highlight.js backend:

```tsx
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter';
import { oneDark } from 'react-syntax-highlighter/dist/esm/styles/prism';

function renderContent(language: string) {
  return (content: string) => (
    <SyntaxHighlighter language={language} style={oneDark} PreTag="span">
      {content}
    </SyntaxHighlighter>
  );
}

// Usage in DiffPanel
<ReactDiffViewer
  oldValue={oldContent}
  newValue={newContent}
  renderContent={renderContent(detectLanguage(action.entrypoint))}
/>
```

**Language detection** can be based on file extension:
```typescript
function detectLanguage(filename: string): string {
  const ext = filename.split('.').pop();
  const map: Record<string, string> = {
    sh: 'bash', sql: 'sql', py: 'python',
    json: 'json', yml: 'yaml', yaml: 'yaml',
    tf: 'hcl', tfargs: 'hcl',
  };
  return map[ext ?? ''] ?? 'text';
}
```

---

## 8. Recommended Architecture

### 8.1 Package Dependencies

**Required npm packages:**

| Package | Purpose | Size |
|---------|---------|------|
| `react-diff-viewer-continued` | Diff viewer component | ~45KB gz |
| `react-syntax-highlighter` | Syntax highlighting in diffs | ~30KB gz (with one style) |
| `sonner` | Toast notifications | ~5KB gz |
| `ansi-to-react` | ANSI color rendering for stdout/stderr | ~8KB gz |

**Already provided by the Dev Toolkit core (shadcn/ui):**
- `@radix-ui/*` primitives (Dialog, Tabs, Badge, etc.)
- `tailwindcss` + `class-variance-authority`
- `lucide-react` icons

**Optional (consider for post-MVP):**
- `@git-diff-view/react` — if we need git-format diff display later
- `@monaco-editor/react` — if we add an "edit before approve" feature
- `sse-z` or native `EventSource` — for real-time updates

### 8.2 API Endpoints (FastAPI)

The approval dashboard needs these API endpoints:

```
GET  /api/actions                      — List all actions with current status
GET  /api/actions/{name}               — Get action detail (metadata, status, hashes)
GET  /api/actions/{name}/diff          — Get old content + new content for diffing
GET  /api/actions/{name}/output        — Get stdout, stderr, result
GET  /api/actions/{name}/receipt       — Get execution receipt
GET  /api/actions/{name}/history       — Get ledger entries for this action
POST /api/actions/{name}/approve       — Approve current request hash
POST /api/actions/{name}/reject        — Reject with comment
POST /api/actions/{name}/run           — Execute approved request
GET  /api/actions/events               — SSE stream for real-time updates
GET  /api/ledger/verify                — Verify ledger chain integrity
```

### 8.3 State Management

For a relatively small dashboard, React Context + useReducer is sufficient:

```typescript
interface GatewayState {
  actions: Action[];
  selectedAction: string | null;
  filter: ActionFilter;
  diffCache: Map<string, { old: string; new: string }>;
}

type GatewayAction =
  | { type: 'SET_ACTIONS'; payload: Action[] }
  | { type: 'UPDATE_ACTION'; payload: Partial<Action> & { name: string } }
  | { type: 'SELECT_ACTION'; payload: string }
  | { type: 'SET_FILTER'; payload: ActionFilter }
  | { type: 'CACHE_DIFF'; payload: { name: string; old: string; new: string } };
```

No need for Redux, Zustand, or other state management libraries for this scope.

### 8.4 What Diffs to Show

The diff panel should compare:

| Scenario | Old Value | New Value |
|----------|-----------|-----------|
| **First request** (no prior approval) | Empty string `""` | Current `request.*` content |
| **Updated request** (prior approval exists) | Content at last approved hash | Current `request.*` content |
| **Re-review of approved** (no changes) | Approved content | Same (no diff shown, "No changes" message) |
| **Metadata diff** (optional) | Previous `request.meta.json` | Current `request.meta.json` |

The backend should serve both the old and new content as raw strings. The frontend computes and renders the diff client-side using react-diff-viewer-continued's built-in jsdiff integration.

### 8.5 Mobile Considerations

For mobile/tablet approval (approve from phone):
- The action list collapses to a full-width list (click to navigate to detail)
- Diff switches to unified view automatically on narrow screens
- Approve/Reject buttons are sticky at the bottom
- Touch-friendly tap targets (minimum 44px)
- shadcn/ui components are already responsive

This is a post-MVP consideration but the architecture should not preclude it.

---

## Sources

### Diff Viewer Libraries
- [react-diff-viewer-continued (npm)](https://www.npmjs.com/package/react-diff-viewer-continued)
- [react-diff-viewer-continued (GitHub - Aeolun)](https://github.com/Aeolun/react-diff-viewer-continued)
- [@git-diff-view/react (npm)](https://www.npmjs.com/package/@git-diff-view/react)
- [git-diff-view (GitHub)](https://github.com/MrWangJustToDo/git-diff-view)
- [@monaco-editor/react (npm)](https://www.npmjs.com/package/@monaco-editor/react)
- [Monaco React (DiffEditor docs)](https://deepwiki.com/suren-atoyan/monaco-react/2.2-diffeditor-component)
- [@codemirror/merge (npm)](https://www.npmjs.com/package/@codemirror/merge)
- [react-codemirror-merge (npm)](https://www.npmjs.com/package/react-codemirror-merge)
- [diff2html](https://diff2html.xyz/)
- [react-diff-view (GitHub)](https://github.com/otakustay/react-diff-view)

### Diff Algorithm
- [jsdiff / diff (npm)](https://www.npmjs.com/package/diff)
- [jsdiff (GitHub)](https://github.com/kpdecker/jsdiff)

### Approval Workflow Patterns
- [Terraform Core Workflow](https://developer.hashicorp.com/terraform/intro/core-workflow)
- [ArgoCD Diff Strategies](https://argo-cd.readthedocs.io/en/stable/user-guide/diff-strategies/)
- [ArgoCD App Diff Preview (Codefresh)](https://codefresh.io/blog/argo-cd-preview-diff/)

### Real-Time Updates
- [SSE with FastAPI (Medium)](https://mahdijafaridev.medium.com/implementing-server-sent-events-sse-with-fastapi-real-time-updates-made-simple-6492f8bfc154)
- [SSE vs WebSockets (Ably)](https://ably.com/blog/websockets-vs-sse)
- [SSE vs WebSockets for 95% of Real-Time Apps](https://dev.to/polliog/server-sent-events-beat-websockets-for-95-of-real-time-apps-heres-why-a4l)
- [FastAPI WebSocket/SSE Notifications](https://blog.greeden.me/en/2025/10/28/weaponizing-real-time-websocket-sse-notifications-with-fastapi-connection-management-rooms-reconnection-scale-out-and-observability/)

### Dashboard Components
- [shadcn/ui Components](https://ui.shadcn.com/docs/components)
- [shadcn/ui Dashboard Tutorial (2026)](https://designrevision.com/blog/shadcn-dashboard-tutorial)
