# VS Code Extension API — Capabilities, Limitations, and Integration Patterns

**Research Date**: 2026-03-13
**Issue**: #56 — Dev Toolkit: Core Framework
**Epic**: #55 — Dev Toolkit: Local-First IDE for Agent Development & Operations

---

## Executive Summary

The VS Code Extension API offers deep native integration through webview panels, tree views, custom editors, terminal management, and command palette integration. However, for the Dev Toolkit's use case — a multi-tool plugin architecture with rich UI — the extension API introduces significant complexity and lock-in compared to the web server approach.

**Recommendation**: VS Code integration should be an optional thin wrapper (Phase 3) around the web server, not the primary UI layer. The best pattern is **Pattern C: Extension as Thin Wrapper** — a small extension that provides navigation commands and opens Simple Browser panels pointing at the localhost web server.

---

## 1. Webview Panels

### Capabilities

Webview panels are the primary mechanism for rendering custom HTML UI inside VS Code. They function as sandboxed iframes that extensions control via message passing.

**What they can render:**
- Full HTML5, CSS3, and JavaScript (when `enableScripts: true`)
- Any frontend framework (React, Svelte, Vue, etc.)
- Audio (WAV, MP3, Ogg, FLAC) and video (H.264, VP8)
- Web fonts, SVGs, Canvas elements

**Creation and lifecycle:**
```typescript
const panel = vscode.window.createWebviewPanel(
  'devToolkit',           // viewType identifier
  'Dev Toolkit',          // title
  vscode.ViewColumn.One,  // editor column
  {
    enableScripts: true,
    retainContextWhenHidden: false,  // default; true has high memory cost
    localResourceRoots: [vscode.Uri.joinPath(context.extensionUri, 'media')]
  }
);
```

**Message passing (extension <-> webview):**
```typescript
// Extension -> Webview
panel.webview.postMessage({ command: 'update', data: payload });

// Webview -> Extension
const vscode = acquireVsCodeApi();  // call ONCE per webview
vscode.postMessage({ command: 'save', content: '...' });

// Extension listens
panel.webview.onDidReceiveMessage(message => { /* handle */ });
```

**State persistence:**
- `vscode.getState()` / `vscode.setState()` — persists JSON state across tab switches (even when webview content is destroyed)
- `WebviewPanelSerializer` — restores webview panels across VS Code restarts
- `retainContextWhenHidden: true` — keeps webview alive in background (high memory cost; avoid if possible)

### Limitations

| Limitation | Impact on Dev Toolkit |
|------------|----------------------|
| **No direct filesystem access** | All file operations must proxy through extension host via message passing |
| **State lost on tab switch** (unless managed) | Must manually serialize/restore state for forms, editors, scroll position |
| **Web Workers limited to data:/blob: URIs** | Cannot use `importScripts`; complex computation must go through extension host |
| **Webview UI Toolkit deprecated (Jan 2025)** | No official component library; must build or use third-party styling |
| **Isolated context** | Cannot access VS Code API directly; `acquireVsCodeApi()` provides only `postMessage`, `getState`, `setState` |
| **Resource loading** | Must use `webview.asWebviewUri()` for local files; cannot use standard file paths |
| **High resource cost** | Each webview runs in its own process; multiple panels = significant memory |
| **No shared state between webviews** | Multiple panels cannot communicate directly; must hub through extension host |

### Content Security Policy (CSP)

Webviews should include a CSP meta tag for security:
```html
<meta http-equiv="Content-Security-Policy"
  content="default-src 'none';
           img-src ${webview.cspSource} https:;
           script-src ${webview.cspSource};
           style-src ${webview.cspSource};" />
```

Key restrictions:
- Inline scripts blocked (no `onclick` handlers, no `<script>` tags with inline code)
- Inline styles can be restricted
- Only HTTPS external resources (no HTTP)
- `localResourceRoots` limits which local directories the webview can access

### Accessing localhost URLs

Webviews can embed iframes pointing to localhost, but with caveats:
- By default, localhost in a webview resolves to the **developer's machine**, not the container
- In remote/devcontainer scenarios, must use `vscode.env.asExternalUri()` to get a forwarded URI
- The returned URI may not reference localhost at all (especially in Codespaces)

```typescript
const localServerUri = await vscode.env.asExternalUri(
  vscode.Uri.parse('http://localhost:8080')
);
// Use localServerUri.toString() in webview iframe src
```

### Multiple Webviews / Shared State

- Webviews are intentionally isolated — "even multiple webviews created by the same extension should never be able to affect each other"
- To synchronize state across multiple panels, the extension host acts as a message hub
- Libraries like **vscode-messenger** and **Tangle** simplify multi-webview communication
- Pattern: webview sends state change -> extension host broadcasts to all other webviews

### Performance

- Each webview runs in a separate Electron renderer process
- Opening 4-5 webview panels concurrently consumes ~200-400MB additional RAM
- `retainContextWhenHidden: true` roughly doubles the memory cost per panel
- Message passing adds serialization/deserialization latency (noticeable for large payloads)
- No GPU acceleration for Canvas/WebGL in some environments

---

## 2. Tree Views

### Capabilities

Tree views provide hierarchical navigation in VS Code's sidebar (Explorer, Source Control, etc.).

**TreeDataProvider API:**
```typescript
interface TreeDataProvider<T> {
  getChildren(element?: T): ProviderResult<T[]>;   // required
  getTreeItem(element: T): TreeItem | Thenable<TreeItem>;  // required
  getParent?(element: T): ProviderResult<T>;  // optional, enables reveal()
  resolveTreeItem?(item: TreeItem): Thenable<TreeItem>;  // optional, lazy resolve tooltip/command
  onDidChangeTreeData?: Event<T | undefined | null | void>;  // refresh signal
}
```

**Registration:**
```typescript
// Basic registration
vscode.window.registerTreeDataProvider('devToolkitTools', myProvider);

// Advanced (enables programmatic reveal, title modification)
const treeView = vscode.window.createTreeView('devToolkitTools', {
  treeDataProvider: myProvider,
  showCollapseAll: true,
  canSelectMany: false
});
```

**Features:**
- Custom icons (ThemeIcon, file icons, or custom SVGs)
- Inline actions (icon buttons) on tree items
- Context menu items via `contributes.menus` in package.json
- Drag-and-drop support (via `TreeDragAndDropController`)
- Programmatic reveal: `treeView.reveal(element, { select: true, focus: true, expand: 3 })`
- Descriptions (secondary text) on tree items
- Tooltip on hover (can be markdown)

### Limitations

- Maximum reveal depth of 3 levels
- No custom rendering — items are text + icon + description only (no HTML, no custom widgets)
- No inline editing of tree items (must open a separate UI)
- Limited layout control — always a vertical list
- No grouping headers or separators (must simulate with non-interactive items)

### Dev Toolkit Relevance

Tree views would be useful for:
- **Tool navigation**: Left sidebar listing available tools (Markdown Browser, jtbl, Agent Gateway, Agent Builder)
- **Agent browser**: Hierarchical view of agent definitions
- **File browser**: Filtered view of markdown files or JSON files

However, tree views alone cannot provide the rich UI needed for data tables, markdown rendering, or DAG visualization — those still need webviews or the web server.

---

## 3. Custom Editors

### Three Provider Types

| Type | Document Model | Save/Undo | Best For |
|------|---------------|-----------|----------|
| **CustomTextEditorProvider** | VS Code's TextDocument | Automatic | Text formats (JSON, YAML, Markdown) |
| **CustomReadonlyEditorProvider** | Custom (read-only) | N/A | Previews, visualizations |
| **CustomEditorProvider** | Custom (read-write) | Extension implements | Binary formats |

### CustomTextEditorProvider

- **Easiest to implement**: VS Code handles save, backup, hot exit, undo/redo
- Extension creates a webview that displays the document content
- Changes flow bidirectionally:
  1. User edits in webview -> extension receives message -> creates `WorkspaceEdit` -> applies to `TextDocument`
  2. `TextDocument` changes -> `onDidChangeTextDocument` fires -> extension updates webview
- Could be used for a markdown editor: webview renders WYSIWYG, edits create workspace edits to the .md file
- **Limitation**: The editing model is text-based — complex structural edits (like drag-and-drop reordering in a form) must be translated to text diffs

### CustomReadonlyEditorProvider

- Simplest implementation: just render content in a webview, no edit lifecycle
- Could be used for rendered markdown preview, JSON visualization, agent definition viewer
- No undo/redo, no save — just display

### Dev Toolkit Relevance

Custom editors could replace the built-in text/markdown editor for specific file types:
- `.md` files could open in a custom WYSIWYG editor (CustomTextEditorProvider)
- Agent definition YAML files could open in a visual builder (CustomTextEditorProvider)
- JSON files could open in a table/tree viewer (CustomReadonlyEditorProvider)

**Tradeoff**: This gives deep VS Code integration (files open directly in the custom editor) but requires implementing the full editing lifecycle and is VS Code-only.

---

## 4. Terminal Integration

### Capabilities

```typescript
// Create a terminal
const terminal = vscode.window.createTerminal({
  name: 'Dev Toolkit',
  cwd: '/workspace',
  env: { PORT: '8080' }
});

// Send commands
terminal.sendText('dev-toolkit serve');
terminal.show();

// Listen for events
vscode.window.onDidOpenTerminal(t => { /* ... */ });
vscode.window.onDidCloseTerminal(t => { /* ... */ });
vscode.window.onDidChangeActiveTerminal(t => { /* ... */ });

// Access all terminals
const terminals = vscode.window.terminals;
```

**Features:**
- Create named terminal instances with custom environment
- Send text (commands) to terminals programmatically
- Show/hide terminal panel
- Listen for terminal open/close/change events
- Terminal profiles: contribute custom terminal profiles via `contributes.terminal.profiles`

### Limitations

- **No output reading**: Cannot read terminal stdout/stderr from the extension API (security restriction)
- **No PTY control**: Cannot create custom terminal renderers or intercept keystrokes (TerminalRenderer API was never finalized)
- **Send-only**: `sendText()` writes to stdin but you cannot capture the response
- To capture output, must use `child_process` instead and route output through the extension host

### Dev Toolkit Relevance

Terminal API would be useful for:
- Starting the dev-toolkit web server: `terminal.sendText('dev-toolkit serve')`
- Running CLI commands: `terminal.sendText('claudio toolkit json data.json')`
- Providing a dedicated terminal tab for toolkit operations

---

## 5. Status Bar, Notifications, Commands

### Status Bar

```typescript
const statusBar = vscode.window.createStatusBarItem(
  vscode.StatusBarAlignment.Right, 100
);
statusBar.text = '$(server) Dev Toolkit';
statusBar.tooltip = 'Click to open Dev Toolkit';
statusBar.command = 'devToolkit.open';
statusBar.show();
```

- Supports text, icons (Codicons via `$(icon-name)`), colors, and tooltips
- Click triggers a registered command
- Can show background color for warnings/errors
- Good for: showing toolkit server status (running/stopped), quick-launch button

### Notifications

```typescript
// Information
vscode.window.showInformationMessage('Dev Toolkit server started on port 8080');

// With actions
const action = await vscode.window.showInformationMessage(
  'Dev Toolkit ready', 'Open in Browser', 'Dismiss'
);
if (action === 'Open in Browser') {
  vscode.env.openExternal(vscode.Uri.parse('http://localhost:8080'));
}

// Progress
vscode.window.withProgress({
  location: vscode.ProgressLocation.Notification,
  title: 'Starting Dev Toolkit...',
  cancellable: true
}, async (progress, token) => {
  // long-running operation
});
```

### Command Palette

```json
// package.json
{
  "contributes": {
    "commands": [
      {
        "command": "devToolkit.open",
        "title": "Dev Toolkit: Open",
        "icon": "$(server)"
      },
      {
        "command": "devToolkit.openMarkdownBrowser",
        "title": "Dev Toolkit: Open Markdown Browser"
      }
    ]
  }
}
```

Commands integrate into:
- Command Palette (Ctrl+Shift+P)
- Keyboard shortcuts (via `contributes.keybindings`)
- Context menus (right-click in file explorer, editor, etc.)
- Editor title bar actions

---

## 6. Extension-to-Extension Communication

### Public API Export

Extensions can expose APIs to other extensions:
```typescript
// Extension A: exports an API
export function activate(context) {
  return {
    getToolkitPort: () => 8080,
    openTool: (name: string) => { /* ... */ }
  };
}

// Extension B: consumes the API
const toolkitExt = vscode.extensions.getExtension('claudio.dev-toolkit');
if (toolkitExt?.isActive) {
  const api = toolkitExt.exports;
  api.openTool('markdown-browser');
}
```

### Extension Dependencies

```json
// package.json
{
  "extensionDependencies": ["claudio.dev-toolkit"]
}
```

- `extensionDependencies` ensures the dependency is installed but does NOT guarantee activation order
- Must check `.isActive` before accessing exports
- Activation events (`onCommand`, `onView`, `*`) control when extensions activate

### Dev Toolkit Relevance

If the Dev Toolkit extension exposed a public API, other extensions (e.g., a Claude Code extension) could:
- Open specific tools programmatically
- Query toolkit status
- Register additional tools/plugins

However, this creates tight coupling between VS Code extensions and is unnecessary if the web server provides a REST API that any client (extension, CLI, browser) can call.

---

## 7. Integration Patterns for the Dev Toolkit

### Pattern A: Extension Wraps Localhost Web Server

```
┌──────────────────────────────────┐
│ VS Code Extension Host           │
│  - Spawns web server as child    │
│    process on port 8080          │
│  - Opens Simple Browser panel    │
│    pointing at localhost:8080    │
│  - Status bar shows server state │
└──────────────────────────────────┘
         ↓
┌──────────────────────────────────┐
│ Simple Browser / Webview Panel   │
│  - Full web UI from the server   │
│  - All features of web app       │
└──────────────────────────────────┘
```

**Pros:**
- Reuse 100% of the web UI code
- Web app works independently of the extension
- Simple Browser handles port forwarding in remote scenarios

**Cons:**
- Requires the web server to be running
- Simple Browser has limited VS Code integration (no tree views, no status bar from the web app)
- Two processes to manage (extension host + web server)

### Pattern B: Extension IS the UI (No Web Server)

```
┌──────────────────────────────────┐
│ VS Code Extension Host           │
│  - All business logic here       │
│  - File reading, JSON parsing,   │
│    markdown processing           │
│  - Message passing to webviews   │
└──────────────────────────────────┘
         ↓ postMessage ↓
┌──────────────────────────────────┐
│ Webview Panel: Markdown Browser  │
│ Webview Panel: JSON Table        │
│ Webview Panel: Agent Builder     │
│ Webview Panel: Agent Gateway     │
│  - Each panel has own HTML/JS    │
│  - State managed independently   │
└──────────────────────────────────┘
```

**Pros:**
- Deepest VS Code integration (panels dock, tab, split natively)
- No separate server process
- Direct access to VS Code API (file system, git, terminal)

**Cons:**
- 4+ webview panels, each with its own message protocol
- State management complexity per panel (serialize on hide, restore on show)
- No shared navigation shell between panels
- Testing requires running VS Code (no headless testing)
- VS Code only — SSH users, non-VS-Code editors get nothing
- Debugging webviews is painful (no direct console.log)
- High memory overhead with multiple concurrent panels

### Pattern C: Extension as Thin Wrapper (RECOMMENDED)

```
┌──────────────────────────────────┐
│ VS Code Extension (thin layer)   │
│  - Tree view: tool navigation    │
│  - Commands: open tools          │
│  - Status bar: server status     │
│  - Starts server if not running  │
│  - Opens Simple Browser panels   │
└──────────────────────────────────┘
         ↓
┌──────────────────────────────────┐
│ Web Server (FastAPI on :8080)    │
│  - Full UI, plugin architecture  │
│  - All tools rendered here       │
│  - Works in any browser          │
└──────────────────────────────────┘
```

**What the extension provides:**
1. **Tree view** in the sidebar listing available tools (reads from web server API)
2. **Commands** in Command Palette: "Dev Toolkit: Open Markdown Browser", "Dev Toolkit: Open JSON Table", etc.
3. **Status bar item** showing server status (running/stopped), click to open
4. **Auto-start**: On activation, check if server is running on port 8080; if not, start it via terminal or child process
5. **Simple Browser integration**: Each command opens `simpleBrowser.api.open` with the tool's URL
6. **Keyboard shortcuts**: Quick-launch bindings for frequent tools

**What the extension does NOT provide:**
- No custom webview panels (the web server is the UI)
- No custom editors
- No business logic (all in the web server)
- No state management (web server handles it)

**Pros:**
- Minimal extension code (~200-400 lines)
- Web server works independently (browser, CLI, SSH)
- Best of both: VS Code sidebar navigation + full web UI
- Easy to maintain: extension is just commands and a tree view
- Testable: web server tests are standard HTTP tests
- Portable: works in VS Code, Cursor, Windsurf, any Electron-based fork

**Cons:**
- Requires web server to be running (but auto-start solves this)
- Simple Browser panels don't have the same tab-docking feel as native webview panels
- Two things to maintain (but the extension is tiny)

---

## 8. Existing Extensions — Architecture Lessons

### GitLens (Complex Extension with Webviews + Tree Views)

**Architecture:**
- Central `Container` service manages all components
- Multiple sidebar tree views (Commits, Branches, Remotes, Stashes, Tags, Contributors)
- Webviews for welcome page, settings, and rich visualizations
- Code decorations (blame annotations, CodeLens)

**Lessons:**
- Complex VS Code extensions require enormous engineering investment
- Tree views work well for hierarchical navigation
- Webview state management is a constant source of bugs
- Extension must handle different behaviors across VS Code, Cursor, Windsurf forks
- GitLens has 20+ million installs but still struggles with performance and reliability in webviews

### Draw.io Integration (Custom Editor with Embedded Web App)

**Architecture:**
- Uses `CustomEditorProvider` to register for `.drawio` file types
- Embeds the full Draw.io web application in a webview
- Bidirectional sync between webview (Draw.io) and VS Code document model
- Can use bundled offline version or online Draw.io

**Lessons:**
- Proves that embedding a full web application in a VS Code webview works
- But requires implementing the custom editor lifecycle (save, undo/redo, backup)
- The complexity is in the bridge layer, not the web app itself
- For the Dev Toolkit, this pattern is overkill — we don't need to register as a file type editor

### Thunder Client (REST Client with Full Webview UI)

**Architecture:**
- Single webview panel for the entire REST client UI
- Built with TypeScript, Flexbox, Ace Editor
- Local storage via Nedb (embedded database)
- Closed source

**Lessons:**
- A complete application UI can live in a single webview panel
- But Thunder Client is a single-purpose tool; the Dev Toolkit is a multi-tool platform
- If we tried this pattern, we'd need one mega-webview (complex) or multiple panels (memory-heavy)

### GitHub Copilot (Chat Panel + Inline Completions)

**Architecture:**
- Chat participant API for the sidebar chat panel
- Inline completion provider for code suggestions
- Tight integration with VS Code's built-in chat infrastructure

**Lessons:**
- Copilot leverages VS Code's built-in chat panel, which is NOT available via the extension API
- This is exactly why Cursor and Windsurf forked VS Code — the extension API doesn't allow customizing the chat panel's layout or behavior
- The Dev Toolkit should not depend on extension API features that may change or be restricted

---

## 9. Remote Development Considerations

### The localhost Problem

When VS Code runs with Remote SSH, Containers, or Codespaces:
- The extension host runs on the **remote machine** (inside the container)
- The webview runs on the **local machine** (the user's computer)
- `localhost` in the webview refers to the user's machine, NOT the container

### Solutions

1. **`vscode.env.asExternalUri()`**: Converts a container localhost URI to a forwarded URI that works from the user's machine
2. **`forwardPorts` in devcontainer.json**: Automatically forwards specified ports (Claudio already forwards 8080, 8081)
3. **Simple Browser**: Handles port forwarding automatically

### Implication for Dev Toolkit

The web server running on port 8080 inside the container is already accessible via VS Code's port forwarding. No special extension code is needed — VS Code handles this natively.

If writing a webview panel that needs to access the server, `asExternalUri()` must be used:
```typescript
const serverUri = await vscode.env.asExternalUri(
  vscode.Uri.parse('http://localhost:8080')
);
```

### Critical: Bind to 0.0.0.0

Applications binding to `127.0.0.1` are NOT accessible via port forwarding. The web server MUST bind to `0.0.0.0`:
```python
# FastAPI / Uvicorn
uvicorn.run(app, host="0.0.0.0", port=8080)
```

---

## 10. Simple Browser API

The VS Code Simple Browser provides a built-in way to open web pages inside VS Code panels.

**Programmatic access:**
```typescript
vscode.commands.executeCommand('simpleBrowser.api.open', 'http://localhost:8080');
```

**Capabilities:**
- Renders any web page in a VS Code editor tab
- Handles port forwarding in remote scenarios automatically
- Supports navigation, back/forward, refresh
- Can be opened in any editor column (side-by-side with code)

**Limitations:**
- No programmatic control once opened (cannot inject scripts, read content, or intercept navigation)
- Basic browser chrome (URL bar, back/forward) — cannot customize
- No extension-to-page communication (unlike webview panels)
- Cannot register as a handler for specific URL patterns

**Dev Toolkit usage:**
```typescript
// Open a specific tool
vscode.commands.executeCommand(
  'simpleBrowser.api.open',
  'http://localhost:8080/tools/markdown-browser'
);
```

---

## 11. Recommendation for the Dev Toolkit

### Phase 1-2: No VS Code Extension Needed

The web server (FastAPI) and CLI are sufficient. VS Code's built-in port forwarding makes the web UI accessible. Users can:
- Open `localhost:8080` in any browser
- Use Command Palette -> "Simple Browser: Show" to open inside VS Code
- Use the CLI in VS Code's integrated terminal

### Phase 3: Optional Thin Extension (Pattern C)

When VS Code-specific convenience is desired, build a minimal extension:

**Extension scope (~300 lines of TypeScript):**

| Component | Purpose | Complexity |
|-----------|---------|-----------|
| Tree View | Sidebar listing of available tools | Low |
| 4-5 Commands | "Open Markdown Browser", "Open JSON Table", etc. | Low |
| Status Bar Item | Show server status, click to open | Low |
| Auto-start | Check port 8080, start server if needed | Low |
| Settings | Port configuration, auto-start toggle | Low |

**Not in extension scope:**
- No webview panels (web server is the UI)
- No custom editors (web server handles file viewing/editing)
- No business logic (web server + core modules)
- No state management (web server handles it)

### Why NOT a Full Extension

| Factor | Full Extension | Thin Wrapper |
|--------|---------------|--------------|
| Development effort | Months (4+ webview panels) | Days (~300 lines) |
| Testing | Requires VS Code test harness | Standard HTTP tests for web; trivial for extension |
| Portability | VS Code only | Web works everywhere; extension is optional |
| Maintenance | VS Code API changes, fork compatibility | Minimal surface area |
| User experience | Potentially deeper integration | 90% as good with 10% of the effort |

---

## Sources

### VS Code Extension API Documentation
- [Webview API](https://code.visualstudio.com/api/extension-guides/webview)
- [Custom Editor API](https://code.visualstudio.com/api/extension-guides/custom-editors)
- [Tree View API](https://code.visualstudio.com/api/extension-guides/tree-view)
- [Extension API Reference](https://code.visualstudio.com/api/references/vscode-api)
- [Status Bar UX Guidelines](https://code.visualstudio.com/api/ux-guidelines/status-bar)
- [Notifications UX Guidelines](https://code.visualstudio.com/api/ux-guidelines/notifications)
- [Command Palette UX Guidelines](https://code.visualstudio.com/api/ux-guidelines/command-palette)
- [Activation Events](https://code.visualstudio.com/api/references/activation-events)
- [Supporting Remote Development](https://code.visualstudio.com/api/advanced-topics/remote-extensions)

### Extension Architecture Case Studies
- [GitLens Architecture (DeepWiki)](https://deepwiki.com/gitkraken/vscode-gitlens)
- [Building GitLens for VS Code (GitKon Talk)](https://www.gitkraken.com/gitkon/building-gitlens-vs-code)
- [Draw.io VS Code Integration](https://marketplace.visualstudio.com/items?itemName=hediet.vscode-drawio)
- [VS Code Extension Samples (Microsoft)](https://github.com/microsoft/vscode-extension-samples)

### Multi-Webview Communication
- [VS Code Messenger (TypeFox)](https://www.typefox.io/blog/vs-code-messenger/)
- [Effortless App State Sync across JS Sandboxes](https://dev.to/sourishkrout/effortless-app-state-sync-across-different-js-sandboxes-inline-frames-web-workers-worker-threads-or-vs-code-webviews-768)
- [Multiple Webviews in a Single Extension (Vogella)](https://vogella.com/blog/multiple-webviews-single-extension/)

### Performance and Security
- [Escaping Misconfigured VS Code Extensions (Trail of Bits)](https://blog.trailofbits.com/2023/02/21/vscode-extension-escape-vulnerability/)
- [React Webview UI Toolkit (GitHub Next)](https://githubnext.com/projects/react-webview-ui-toolkit/)
- [Building VS Code Extensions in 2026](https://abdulkadersafi.com/blog/building-vs-code-extensions-in-2026-the-complete-modern-guide)

### Remote Development and Port Forwarding
- [Developing inside a Container](https://code.visualstudio.com/docs/devcontainers/containers)
- [Port Forwarding](https://code.visualstudio.com/docs/debugtest/port-forwarding)
- [How to Configure Dev Container Port Forwarding](https://oneuptime.com/blog/post/2026-01-28-dev-container-port-forwarding/view)
- [VS Code Integrated Browser](https://code.visualstudio.com/docs/debugtest/integrated-browser)

### Webview UI Toolkit (Deprecated)
- [Webview UI Toolkit (Deprecated Jan 2025)](https://github.com/microsoft/vscode-webview-ui-toolkit)
- [How I Re-Architected My VS Code Extension to Work 100% Offline](https://freerave.medium.com/how-i-re-architected-my-vs-code-extension-to-work-100-offline-the-codetune-journey-3c71a6141b7d)

### Terminal API
- [Terminal API Example (Tyriar)](https://github.com/Tyriar/vscode-terminal-api-example)
- [Terminal Advanced Features](https://code.visualstudio.com/docs/terminal/advanced)
