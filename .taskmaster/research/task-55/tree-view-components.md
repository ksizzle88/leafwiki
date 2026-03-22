# Tree View & File Explorer UI Components

**Research for**: Dev Toolkit (Epic #55) — Markdown Browser (#57) and Agent Builder (#60)
**Date**: 2026-03-13

---

## 1. Executive Summary

**Recommendation: react-arborist (if React) or KeenMate/svelte-treeview (if Svelte)**

For a React-based stack (as recommended by the frontend-framework-comparison research), **react-arborist** is the clear winner: it has the highest adoption (225K weekly downloads, 3.6K stars), built-in virtualization for 10K+ nodes, inline rename, drag-and-drop, and customizable node rendering. It is explicitly designed to replicate VS Code sidebar / macOS Finder / Windows Explorer behavior.

For a Svelte-based stack (if the form-factor evaluation's HTMX path is chosen and enriched with Svelte islands), **@keenmate/svelte-treeview** is the best option: Svelte 5 native, three rendering modes (recursive, progressive flat, virtual scroll), drag-and-drop, and integrated FlexSearch.

If the framework decision is still open and the team wants maximum flexibility, **headless-tree** (@headless-tree/core + framework bindings) deserves consideration: framework-agnostic core with a thin React binding today and the potential for Svelte/Vue bindings in the future.

---

## 2. Use Cases

### Markdown Browser (#57)
- Tree of `.md` files in configurable root directories (`/workspace`, `~/.claude`, `.taskmaster/`)
- Display last-modified timestamps alongside file names
- File type icons (`.md` specific, possibly different icons for CLAUDE.md, settings, plans)
- Full-text search/filter across file names
- Click to open in viewer/editor
- Tree updates when files are added/removed externally (file watching)
- Expected scale: ~50-500 files in typical workspace, up to ~2000 in large projects

### Agent Builder (#60)
- Tree of agent config files across config hierarchy:
  - `.claude/settings.json`, `.claude/settings.local.json`, `.claude/CLAUDE.md`
  - `.claude/agents/*.md`, `.claude/commands/*.md`, `.claude/hooks/*.sh`
  - `~/.claude/` (global equivalents)
- Visual indicator of override precedence (which setting wins)
- Status indicators (valid, warning, error from validation)
- Click to open in editor with live preview
- Expected scale: ~20-100 files

### Shared Requirements
- Keyboard navigation (arrow keys, Enter to open, Home/End)
- Indentation guides (visual lines showing nesting depth)
- Collapsible folders
- Custom node rendering (timestamps, badges, status icons)
- Responsive layout (works in both full browser and VS Code simple browser panel)
- Accessible (ARIA tree roles, screen reader support)

---

## 3. Library Comparison

### 3.1 React Libraries

| Feature | react-arborist | react-complex-tree | headless-tree | rc-tree (Ant Design) | @blueprintjs/core Tree |
|---|---|---|---|---|---|
| **GitHub Stars** | 3,600 | 1,300 | 785 | ~1,000 (part of Ant) | Part of Blueprint |
| **Weekly Downloads** | 225,000 | 25,000 | ~5,000 (est.) | ~500,000 (Ant ecosystem) | ~200,000 (Blueprint) |
| **Last Release** | Active | Oct 2025 (v2.6.1) | Jan 2026 (v1.6.3) | Active (Ant releases) | Active (Blueprint) |
| **Bundle Size** | ~15KB gz | ~12KB gz | 9.5KB core + 0.4KB React | ~20KB gz | Large (full Blueprint) |
| **Virtualization** | Built-in | No (manual) | Built-in | Built-in (height prop) | No |
| **Lazy Loading** | Via data callbacks | Yes (async items) | Yes (async data loader) | Yes (loadData prop) | Manual |
| **Drag & Drop** | Built-in | Built-in (multi-select) | Built-in | Built-in | No |
| **Inline Rename** | Built-in | Built-in (F2) | Built-in | No | No |
| **Keyboard Nav** | Full | Full (W3C spec) | Full | Basic | Basic |
| **Search/Filter** | Built-in filter | Built-in typeahead | Built-in typeahead | No built-in | No built-in |
| **Custom Node Render** | Full (node renderer) | Full (render functions) | Full (headless BYOUI) | Limited (title/icon) | Limited |
| **Multi-Select** | Yes | Yes | Yes | Yes (checkable) | No |
| **Context Menus** | Via custom renderer | Via custom renderer | Via custom renderer | Via right-click event | No |
| **Indentation Guides** | Via CSS | Via CSS | Via CSS | Via CSS | Via CSS |
| **TypeScript** | Yes | Yes | Yes | Yes | Yes |
| **Dependencies** | react-dnd (opt) | Zero | Zero | rc-util | Full Blueprint |
| **Accessibility** | ARIA attributes | W3C compliant | ARIA + W3C | Basic ARIA | Basic ARIA |
| **Maturity** | Stable | Stable (successor exists) | Beta (mostly stable) | Stable (Ant ecosystem) | Stable |

### 3.2 Svelte Libraries

| Feature | @keenmate/svelte-treeview | svelte-file-tree-explorer | shadcn-svelte-extras Tree | Framework7 Tree |
|---|---|---|---|---|
| **GitHub Stars** | 44 | ~30 | Part of shadcn-svelte | Part of Framework7 |
| **Svelte Version** | Svelte 5 (runes) | Svelte 4+ | Svelte 5 | Svelte 4+ |
| **Rendering Modes** | 3 (recursive, progressive, virtual) | Recursive only | Recursive only | Recursive only |
| **Virtual Scroll** | Yes (10K+ nodes) | No | No | No |
| **Drag & Drop** | Yes (position control) | No | No | No |
| **Search** | FlexSearch integration | No | No | No |
| **Context Menus** | Built-in | No | No | No |
| **Custom Rendering** | Extensive slots | Basic slots | Component slots | Limited |
| **Performance** | Progressive batching (20→40→80...) | Basic | Basic | Basic |
| **TypeScript** | Yes | No | Yes | Yes |
| **Maturity** | Young (5 issues open) | Minimal | Basic | Part of large framework |

### 3.3 Framework-Agnostic

| Feature | headless-tree | jstree | Fancytree |
|---|---|---|---|
| **Approach** | Headless (BYOUI) | jQuery widget | jQuery widget |
| **Framework** | Core + bindings | jQuery required | jQuery required |
| **Modern Stack** | Yes (2024+) | Legacy | Legacy |
| **Bundle** | 9.5KB core | ~100KB + jQuery | ~120KB + jQuery |
| **Virtual Scroll** | Yes | Partial | Yes |
| **Drag & Drop** | Yes | Yes | Yes |
| **Relevance** | High | Low (jQuery dep) | Low (jQuery dep) |

---

## 4. Deep Dive: Top Candidates

### 4.1 react-arborist (RECOMMENDED for React)

**Why it wins:**
- Explicitly designed for "VSCode sidebar, Mac Finder, Windows Explorer" patterns — exactly what the Markdown Browser needs
- Built-in virtualization renders only visible rows, handles 30K+ nodes (demonstrated in their "Top Cities" demo)
- Custom node renderer gives full control over what appears in each row (timestamps, icons, badges, status indicators)
- Inline rename, drag-drop, and folder create/delete are built-in behaviors
- Controlled and uncontrolled modes — can be driven by external state (file watcher updates) or internal state
- 225K weekly downloads = battle-tested, bugs get found and fixed quickly

**API surface (relevant to our use cases):**
```tsx
<Tree
  data={fileTreeData}           // Nested node array
  rowHeight={28}                // Compact rows like VS Code
  indent={16}                   // Indentation per level
  openByDefault={false}         // Collapsed by default
  width="100%"
  height={600}                  // Enables virtualization
  searchTerm={searchFilter}     // Filter tree by text
  onActivate={(node) => openFile(node.data.path)}  // Click handler
  onRename={({id, name}) => renameFile(id, name)}  // Inline rename
  onCreate={({parentId, type}) => createNode(parentId, type)}
  onDelete={({ids}) => deleteNodes(ids)}
>
  {CustomNodeRenderer}          // Full control over row content
</Tree>
```

**Custom node rendering example (what the Markdown Browser needs):**
- File icon (based on extension: `.md`, `settings.json`, `.sh`)
- File name (with highlight on search match)
- Last-modified timestamp (right-aligned, dimmed)
- Git status indicator (modified/untracked color)
- Validation status badge (for Agent Builder)

**Performance characteristics:**
- Only renders visible rows (virtualized via react-window internally)
- Smooth scrolling at 60fps with 30K+ nodes
- No DOM bloat — a tree with 30K items only creates ~50 DOM rows
- Incremental updates: add/remove nodes without full re-render

**Limitations:**
- React-only (no Svelte/Vue bindings)
- Depends on react-dnd for drag-and-drop (adds ~20KB if used)
- No built-in context menu (must implement via custom renderer + a menu library)
- No built-in indentation guide lines (achievable via CSS borders on indent containers)

### 4.2 headless-tree (RECOMMENDED if framework flexibility matters)

**Why it's interesting:**
- Framework-agnostic core (`@headless-tree/core` at 9.5KB gz) with thin framework bindings
- React binding is only 50 LOC — Svelte/Vue bindings are viable
- Inspired by TanStack Table's architecture: modular features, tree-shakeable
- Successor to react-complex-tree, inheriting its strong accessibility story
- Async data loader supports lazy-loading children on expand
- Most recent release: Jan 2026 — actively maintained

**Why it's not the top pick (yet):**
- Still in beta (though "mostly stable and production ready" per README)
- React-only bindings shipped today — no Svelte binding exists yet
- Smaller community (785 stars vs 3,600 for react-arborist)
- Headless means you build ALL the rendering yourself — more work upfront
- Fewer real-world examples and tutorials

**When to choose headless-tree over react-arborist:**
- If the Dev Toolkit might switch frameworks later (Svelte bindings could be written)
- If you need extreme control over rendering and don't want any built-in styling
- If the TanStack-style hook API feels more natural to the team
- If you value the W3C accessibility compliance inherited from react-complex-tree

### 4.3 @keenmate/svelte-treeview (RECOMMENDED for Svelte)

**Why it's the best Svelte option:**
- Only Svelte 5 tree component with all three rendering modes: recursive (< 500 nodes), progressive flat (500-10K), virtual scroll (10K+)
- Progressive rendering is clever: first batch renders 20 nodes, then doubles each frame (20 → 40 → 80 → 160...), keeping the UI responsive
- Integrated FlexSearch for fast full-text tree searching
- Built-in drag-and-drop with position control (above/below/child)
- Dynamic context menus with icons and disabled states

**Caveats:**
- Very young (44 stars, 5 open issues) — could have undiscovered bugs
- Must use `$state.raw()` for large arrays (> 1000 items) due to Svelte 5 proxy overhead
- Community is tiny compared to React alternatives

### 4.4 rc-tree / Ant Design Tree (NOT RECOMMENDED)

**Why it's popular but wrong for this project:**
- 500K weekly downloads due to Ant Design ecosystem, but tightly coupled to Ant's design system
- Virtual scroll + async loading have known bugs (issues #23325, #20732)
- Limited custom node rendering (title/icon/extra, not full row control)
- Performance issues reported: "CLICK and EXPAND have poor response speed" with virtual scroll enabled
- Opinionated styling conflicts with shadcn/ui or custom design systems

### 4.5 @blueprintjs/core Tree (NOT RECOMMENDED)

**Why not:**
- No virtualization — performance degrades at ~1K nodes
- No drag-and-drop
- No inline rename
- Requires full Blueprint UI library (large bundle)
- Blueprint RFC for virtualization has been open since 2020+

---

## 5. File Icon Libraries

Both the Markdown Browser and Agent Builder benefit from file-type icons. Options:

| Library | Framework | Icons | Method | Size |
|---|---|---|---|---|
| **vscode-material-icon-theme-js** | Any | 1000+ | `getIconForFile(path)` returns SVG path | ~50KB icons |
| **react-file-icon** | React | ~80 extensions | `<FileIcon extension="md" />` | ~15KB |
| **svelte-file-icons** | Svelte | 930+ | `<FileIcon name="markdown" />` | Tree-shakeable |
| **lucide-react** (already in shadcn/ui) | React | Generic file/folder icons | `<FileText />`, `<Folder />` | Already bundled |
| **Custom SVG sprites** | Any | As needed | Manual | Minimal |

**Recommendation:** Start with Lucide icons (already bundled with shadcn/ui) for basic file/folder distinction. Add `vscode-material-icon-theme-js` or `react-file-icon` later for extension-specific icons if the user experience benefits.

---

## 6. VS Code-Like File Explorer Patterns

Key patterns to replicate from VS Code's file explorer:

### Visual Design
- **Row height**: 22-24px (compact, information-dense)
- **Indent**: 8-16px per level with optional indent guides (subtle vertical lines)
- **File icons**: Left-aligned, 16x16px, extension-specific
- **Folder arrows**: Chevron (▸/▾) before folder icon, toggle on click
- **Selected row**: Highlighted background, no outline
- **Focused row**: Subtle border (keyboard focus indicator)
- **Hover**: Slight background color change, inline action buttons appear

### Interactions
- **Single click**: Select and preview file
- **Double click**: Open file permanently (no preview tab)
- **Arrow keys**: Navigate up/down, left to collapse, right to expand
- **Enter**: Open selected file
- **F2**: Rename inline
- **Delete**: Delete with confirmation
- **Right-click**: Context menu (new file, new folder, rename, delete, copy path)
- **Ctrl+Click**: Multi-select
- **Type to filter**: Start typing to filter visible items

### File Decorations (Git Integration)
- **Modified**: File name in a different color (yellow/orange)
- **Untracked**: File name in green
- **Ignored**: File name dimmed (gray)
- **Conflict**: File name in red
- **Badge**: Letter indicator (M, U, A, D) right-aligned

### Inline Actions
- **On hover**: Show action buttons (new file, new folder, collapse all, refresh)
- **Header bar**: Persistent action buttons at top of tree

---

## 7. Performance Benchmarks

Based on library documentation and community reports:

| Library | 100 nodes | 1K nodes | 10K nodes | 30K+ nodes |
|---|---|---|---|---|
| **react-arborist** | Instant | Instant | Smooth (virtualized) | Smooth (demo proves it) |
| **headless-tree** | Instant | Instant | Smooth (virtualized) | Smooth (claimed) |
| **rc-tree (virtual)** | Instant | Instant | Usable (click/expand slow) | Problematic |
| **Blueprint Tree** | Instant | Slow (no virtual) | Unusable | N/A |
| **KeenMate svelte-treeview** | Instant | Instant (progressive) | Smooth (virtual) | Not tested publicly |
| **Custom recursive** | Instant | Slow | Unusable | N/A |

For the Markdown Browser's expected scale (~50-2000 files), any virtualized library handles it comfortably. The Agent Builder's scale (~20-100 files) is trivial for any library.

---

## 8. Recommendation Matrix

### If React stack (frontend-framework-comparison recommendation):

| Component | Library | Confidence |
|---|---|---|
| **File tree (primary)** | **react-arborist** | High — proven, popular, full-featured |
| **File icons** | Lucide (bundled) → react-file-icon (later) | Medium |
| **Context menus** | shadcn/ui ContextMenu (Radix) | High — already in the stack |
| **Search overlay** | shadcn/ui Command (cmdk) | High — already in the stack |

### If Svelte stack (form-factor evaluation path with Svelte islands):

| Component | Library | Confidence |
|---|---|---|
| **File tree (primary)** | **@keenmate/svelte-treeview** | Medium — young but capable |
| **File icons** | svelte-file-icons | Medium |
| **Context menus** | Custom Svelte component | Medium |
| **Search** | Built-in FlexSearch integration | High |

### If framework flexibility is a priority:

| Component | Library | Confidence |
|---|---|---|
| **File tree (primary)** | **headless-tree** | Medium — beta, but architecturally sound |
| **File icons** | vscode-material-icon-theme-js | High — framework agnostic |
| **Context menus** | Build with framework primitives | N/A |

---

## 9. Integration Notes

### With Markdown Browser (#57)
- Tree data source: filesystem scan of configurable root directories, filtered by `.md` extension
- Tree should re-render when files change (integrate with file watcher — see file-watching-strategies.md research)
- Node data should include: path, name, isFolder, lastModified, size, gitStatus
- Selected file ID should sync with URL (deep-linking: `?file=/workspace/README.md`)
- Search should filter the tree AND trigger full-text search in file contents (two search modes)

### With Agent Builder (#60)
- Tree data source: combined scan of `.claude/` directories across config hierarchy
- Nodes need extra metadata: configType (agent, command, hook, settings), validationStatus, overriddenBy
- Tree should be grouped by type (Agents, Commands, Hooks, Settings) rather than flat file listing
- Override indicators: if a project setting overrides a global one, show the override chain
- Validation badges: green check, yellow warning, red error on each node

### Shared Tree Component
Both tools use a file tree, but with different data models and node renderers. The recommended pattern:

```
components/
  file-tree/
    FileTree.tsx        # Wrapper around react-arborist with common config
    FileTreeNode.tsx     # Default node renderer (icon + name + timestamp)
    
plugins/
  markdown-browser/
    MarkdownFileTree.tsx  # Extends FileTree with .md filtering, timestamps
    MarkdownNode.tsx      # Custom node with last-modified display
    
  agent-builder/
    AgentConfigTree.tsx   # Extends FileTree with grouped sections, validation
    AgentConfigNode.tsx   # Custom node with status badges, override indicator
```

---

## 10. Open Questions

1. **Framework decision**: The form-factor evaluation recommends HTMX, the frontend-framework comparison recommends React. This must be resolved before choosing a tree library. The tree libraries strongly favor React (react-arborist is far ahead of Svelte alternatives in maturity).

2. **Tree as navigation vs. tree as data display**: Should the tree component also be used to display non-file hierarchies (e.g., markdown heading outline, agent dependency graph in tree form)? If so, react-arborist's generic data model supports this.

3. **Offline-first or server-driven**: Should the tree data be loaded entirely on the client (filesystem scan → JSON → tree) or streamed from the server (lazy-load children on expand)? For <2000 files, full client-side load is fine. For larger workspaces, lazy loading with react-arborist's async callbacks or headless-tree's async data loader would be needed.

---

## 11. Sources

### React Libraries
- [react-arborist (GitHub)](https://github.com/brimdata/react-arborist) — 3.6K stars, "complete tree view for React"
- [react-arborist demo](https://react-arborist.netlify.app/) — Live demo with 30K node performance test
- [react-complex-tree (GitHub)](https://github.com/lukasbach/react-complex-tree) — 1.3K stars, W3C accessible
- [react-complex-tree docs](https://rct.lukasbach.com/) — Accessibility guide, API reference
- [headless-tree (GitHub)](https://github.com/lukasbach/headless-tree) — 785 stars, framework-agnostic successor
- [Headless-Tree announcement (Medium)](https://medium.com/@lukasbach/headless-tree-and-the-future-of-react-complex-tree-fc920700e82a)
- [npm trends comparison](https://npmtrends.com/react-accessible-treeview-vs-react-arborist-vs-react-checkbox-tree-vs-react-complex-tree-vs-react-simple-tree-menu-vs-react-tree-menu-vs-react-treeview)
- [7 Best React Tree View Components (2026)](https://reactscript.com/best-tree-view/)

### Svelte Libraries
- [KeenMate svelte-treeview (GitHub)](https://github.com/KeenMate/svelte-treeview) — Svelte 5, three render modes
- [svelte-file-tree-explorer (GitHub)](https://github.com/saibotsivad/svelte-file-tree-explorer) — Simple file tree
- [shadcn-svelte-extras Tree View](https://www.shadcn-svelte-extras.com/components/tree-view) — shadcn-svelte tree

### Framework-Agnostic
- [10 Best Tree View JavaScript Libraries (2026)](https://www.cssscript.com/best-tree-view/)
- [10 Best Tree View Plugins jQuery (2026)](https://www.jqueryscript.net/blog/Best-Tree-View-Plugins-jQuery.html)

### File Icons
- [vscode-material-icon-theme (GitHub)](https://github.com/material-extensions/vscode-material-icon-theme)
- [react-file-icon (npm)](https://www.npmjs.com/package/react-file-icon)
- [svelte-file-icons (npm)](https://www.npmjs.com/package/svelte-file-icons)

### VS Code Tree Implementation
- [VS Code Tree View API](https://code.visualstudio.com/api/extension-guides/tree-view)
- [Ant Design Tree (known issues)](https://github.com/ant-design/ant-design/issues/23325)
- [Blueprint Virtualization RFC](https://github.com/palantir/blueprint/wiki/Blueprint-Virtualization)
