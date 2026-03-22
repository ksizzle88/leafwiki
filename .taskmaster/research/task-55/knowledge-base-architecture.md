# Knowledge Base Architecture: Obsidian, Foam & Related Tools

**Research Date**: 2026-03-13
**Context**: Dev Toolkit Markdown Browser & Editor (Issue #57, Epic #55)
**Focus**: Architectural patterns from knowledge management tools that can be adopted for the Dev Toolkit's "lightweight Obsidian for agent memory" experience.

---

## 1. Executive Summary

This research examines how Obsidian, Foam, Dendron, Notable, MarkText, and Zettlr architect their knowledge base features — file indexing, link resolution, backlink generation, full-text search, graph visualization, and live preview. The goal is to identify patterns that the Dev Toolkit's Markdown Browser can adopt without over-engineering.

**Key recommendations:**
- **File indexing**: Build a MetadataCache-like system using Python watchdog (backend) + WebSocket push to frontend, with MiniSearch (frontend) for instant full-text search
- **Backlinks**: Maintain a bidirectional link map in memory, updated incrementally on file change events
- **Link resolution**: Implement Obsidian-style shortest-unique-path matching for `[[wikilinks]]` and standard relative path resolution for `[markdown](links)`
- **Search**: MiniSearch on the frontend for instant client-side search; Whoosh on the backend for larger vaults as a fallback
- **Graph view**: Force-directed layout via D3-force, rendered in a React component (optional feature, not critical for MVP)
- **Agent Memory view**: Aggregate CLAUDE.md files from all levels into a single hierarchical view with precedence indicators
- **Live preview**: Tiptap in read-only mode with a toggle to CodeMirror 6 for raw editing (already recommended in existing research)

---

## 2. Tool-by-Tool Architectural Analysis

### 2.1 Obsidian

**Architecture**: Electron app (Chromium + Node.js), local file storage, plugin system. The entire vault is a folder of plain Markdown files.

#### MetadataCache: The Core Innovation

Obsidian's MetadataCache is the architectural heart of the application. It is a pre-parsing indexing subsystem that:

1. **Parses every `.md` file once** when modified, extracting structural elements into a `CachedMetadata` object per file
2. **Stores extracted metadata** including:
   - `LinkCache`: All internal wikilinks with position data
   - `EmbedCache`: Embedded content references (`![[...]]`)
   - `HeadingCache`: Document headings with level and position
   - `TagCache`: Hash tags with positions
   - `BlockCache`: Block references (`^block-id`)
   - `FrontmatterCache`: YAML frontmatter properties
   - `FrontmatterLinkCache`: Links within YAML properties
3. **Maintains two critical link maps**:
   - `resolvedLinks`: `Map<sourcePath, Map<destPath, count>>` — tracks all resolved internal links
   - `unresolvedLinks`: `Map<sourcePath, Map<linkText, count>>` — tracks broken references
4. **Operates asynchronously**: `getFileCache(file)` returns immediately with cached data or `null` if not yet parsed. Link resolution occurs after initial vault parsing completes.
5. **Uses incremental updates**: Only modified files are reparsed, not the entire vault.

**Event system** drives reactive updates:

| Event | Parameters | When |
|-------|-----------|------|
| `changed` | `file: TFile` | File metadata updated in cache |
| `resolved` | none | All links resolved vault-wide (initial scan complete) |
| `deleted` | `file: TFile, prevCache` | File removed from vault |

**Performance guidance from Obsidian docs**: Register event listeners once, cache expensive computations, debounce responses to frequent metadata changes, wait for the `"resolved"` event before building link graphs.

#### Link Resolution Algorithm

Obsidian resolves `[[wiki-links]]` through a multi-step process:

1. **Parse**: `parseLinktext("Note#Heading|Display")` extracts path, subpath (heading/block), and display text
2. **Extract path**: `getLinkpath()` isolates just the file reference
3. **Resolve file**: `getFirstLinkpathDest(linkpath, sourcePath)` finds the actual `TFile` using:
   - Exact filename match (case-insensitive, ignoring `.md` extension)
   - Normalized match (treating spaces, dashes, underscores as equivalent)
   - Path prefix match if a folder path is provided
   - **Shortest unique path wins** — if only one file named `MyNote.md` exists anywhere in the vault, `[[MyNote]]` resolves to it regardless of folder depth
4. **Resolve subpath**: `resolveSubpath()` locates the specific heading or block within the target file

**Ambiguity resolution**: When multiple files share a name, the file at the shallowest path wins. `[[A]]` resolves to root `A.md` over `Folder/A.md`.

#### Plugin System

Obsidian's plugin architecture follows a **hub-and-spoke model**:

- **Hub**: The `App` class provides access to all subsystems (`vault`, `workspace`, `metadataCache`, `fileManager`, `keymap`)
- **Spoke**: Each plugin extends `Plugin` (which extends `Component`), receiving `this.app` for access to everything
- **Lifecycle**: `onload()` registers commands, views, events, settings; `onunload()` auto-cleans all registered resources
- **Registration methods with auto-cleanup**: `addCommand()`, `registerView()`, `registerEvent()`, `registerEditorExtension()` (CodeMirror 6 extensions)
- **Data persistence**: `loadData()` / `saveData()` persist plugin settings to `.obsidian/plugins/<id>/data.json`
- **Platform abstraction**: `DataAdapter` interface abstracts filesystem (Node.js on desktop, Capacitor on mobile)

**Key insight for Dev Toolkit**: Obsidian's plugin model is similar to the Dev Toolkit's planned plugin architecture — both mount sub-applications that share access to core services (file system, metadata, workspace layout). The Dev Toolkit can adopt the same pattern of a central `App` context providing shared services to plugin components.

#### Graph View

Obsidian's graph view uses a **force-directed layout** algorithm:

- Nodes represent files; edges represent internal links
- Uses physics simulation with configurable forces (link, charge, center)
- Supports filtering by tags, folders, and search queries
- Renders in Canvas/WebGL for performance at scale (1000+ nodes)
- The 3D graph plugin uses ThreeJS + d3-force-3d

**Key insight for Dev Toolkit**: A graph view is a nice-to-have, not a core requirement. If implemented, D3-force with HTML/SVG rendering (via React Flow) handles the agent memory use case (typically <100 files) without WebGL complexity.

---

### 2.2 Foam (VS Code Extension)

**Architecture**: VS Code extension using VS Code's native APIs for file system access, markdown preview, and tree views.

#### Core Components

1. **FoamWorkspace**: Central repository for all resources (notes, attachments). Acts as the file index.
2. **ResourceProviders**: Fetch and parse different file types (MarkdownProvider, AttachmentProvider)
3. **FoamGraph**: Maintains the link graph with three key data structures:
   - **Links Map**: `Map<sourceURI, ResourceLink[]>` — outgoing links from each resource
   - **Backlinks Map**: `Map<targetURI, ResourceLink[]>` — incoming links to each resource
   - **Placeholders Map**: References to non-existent resources (dangling links)

#### Graph Construction Algorithm

When a resource is added or modified:
1. Extract all `ResourceLink` objects from the resource (via markdown parsing)
2. Map source URIs to target URIs in the Links Map
3. Record reverse connections in the Backlinks Map
4. Identify dangling references and add to Placeholders Map
5. Debounce updates to avoid excessive recalculation

#### Wikilink Resolution

1. **Parse**: Extract `[[note-name]]`, `[[note#section]]`, `[[note|alias]]` from markdown
2. **Resolve**: `FoamWorkspace.resolveLink()` computes minimal identifiers for resources and matches against stored URIs
3. **Navigate**: Resolved link opens the corresponding file in VS Code

#### Graph Visualization

- Uses a **force-directed layout** (D3-style)
- Nodes colored by type (regular, orphaned, placeholder)
- Interactive: clicking a node navigates to the file
- Customizable via `foam.graph.style` settings

**Key insight for Dev Toolkit**: Foam's three-map architecture (links, backlinks, placeholders) is the simplest effective pattern for bidirectional linking. The Dev Toolkit should adopt this exact structure.

---

### 2.3 Dendron (VS Code Extension)

**Architecture**: Hierarchical note system using dot-delimited filenames (e.g., `project.backend.api.auth`).

#### Key Patterns

1. **Hierarchy-as-filename**: `project.backend.api.auth.md` creates an implicit tree structure without folders
2. **Lookup**: Fuzzy-matching navigation across the hierarchy — type partial paths to find notes
3. **Schema system**: Optional type system that describes the expected hierarchy structure, enabling validation and auto-suggestions scoped to hierarchy level
4. **Templates**: Schema-driven templates pre-populate new notes based on their position in the hierarchy

**Key insight for Dev Toolkit**: Dendron's hierarchy model maps well to agent config files which already follow a hierarchical pattern (`.claude/settings.json`, `.claude/CLAUDE.md`, `.taskmaster/plans/`, `.taskmaster/tasks/`). The markdown browser could present these as a logical hierarchy tree, not just a flat file tree.

---

### 2.4 Notable

**Architecture**: Electron app, plain Markdown files with metadata stored as YAML frontmatter.

#### Key Patterns

1. **Data-driven organization**: Tags (including nestable tags like `foo/bar/baz`) replace folders as the primary organizational mechanism
2. **Special tag namespaces**: `Notebooks/foo` for notebook grouping, `Templates/foo` for templates — tags with different icons and behaviors
3. **Split-pane layout**: File tree (left) + Editor (center) + Preview (right)
4. **Fuzzy search**: Full-text search across all notes
5. **Attachments as plain files**: Images and files stored alongside notes

**Key insight for Dev Toolkit**: The tag-based organization could be useful for the Agent Memory view — tag CLAUDE.md files by scope (global, project, local), tag settings files by type (permissions, MCP, hooks), and provide filtered views by tag.

---

### 2.5 MarkText

**Architecture**: Electron app with Vue/Vuex UI, built on a custom editor engine called "Muya."

#### Muya Editor Engine

Muya is the core WYSIWYG engine, providing:
1. **Block-based content model**: Document is a tree of blocks (paragraphs, headings, code blocks, lists, tables)
2. **Real-time preview rendering**: Markdown syntax is rendered inline as you type (WYSIWYG)
3. **Module system**: Separate modules for markdown parsing, block structure, document transformations, event handling, and export
4. **CommonMark + GFM compliance**: Renders according to spec with extensions (KaTeX, frontmatter, emoji)
5. **Virtual DOM rendering**: Efficient re-rendering of changed blocks only

**Key insight for Dev Toolkit**: MarkText's block-based approach is similar to what Tiptap/ProseMirror provides. The existing research already recommends Tiptap, which achieves the same WYSIWYG effect with better React integration and a larger extension ecosystem.

---

### 2.6 Zettlr

**Architecture**: Electron app using CodeMirror as the embedded editor, Pandoc for document conversion.

#### Key Patterns

1. **CodeMirror-based editing**: Raw markdown editing with rich syntax highlighting and inline previews
2. **Pandoc integration**: Export to 30+ formats via configurable profiles
3. **Citation management**: First-class support for academic citations via Citeproc
4. **Zettelkasten features**: Wikilinks, tags, and unique IDs for linking notes
5. **Fine-grained parser**: Direct interaction with CodeMirror for syntax highlighting, recently rewritten for v4.0 (Dec 2025)

**Key insight for Dev Toolkit**: Zettlr's approach of enhancing CodeMirror with custom syntax highlighting and inline previews is relevant for the raw markdown editing mode. CodeMirror 6's extension system supports exactly this pattern.

---

## 3. Architectural Patterns to Adopt

### 3.1 File Indexing System

**Pattern**: Build a MetadataCache-like service that runs on the backend (FastAPI), monitors file changes, and pushes updates to the frontend via WebSocket.

**Recommended architecture**:

```
┌─────────────────────────────────────────────────┐
│                  FastAPI Backend                  │
│                                                   │
│  ┌─────────────┐    ┌──────────────────────────┐ │
│  │  watchdog    │───→│  MarkdownIndexService     │ │
│  │  (file       │    │                           │ │
│  │   watcher)   │    │  - parse frontmatter      │ │
│  │              │    │  - extract links           │ │
│  │  Events:     │    │  - extract headings        │ │
│  │  - created   │    │  - extract tags            │ │
│  │  - modified  │    │  - build link maps         │ │
│  │  - deleted   │    │  - update search index     │ │
│  └─────────────┘    └──────────┬───────────────┘ │
│                                 │                  │
│                    ┌────────────▼───────────────┐ │
│                    │  WebSocket broadcast        │ │
│                    │  (file_changed, index_ready)│ │
│                    └────────────┬───────────────┘ │
└─────────────────────────────────┼──────────────────┘
                                  │
┌─────────────────────────────────▼──────────────────┐
│                 React Frontend                      │
│                                                      │
│  ┌────────────┐  ┌─────────────┐  ┌──────────────┐ │
│  │ FileTree   │  │ MiniSearch  │  │ BacklinkPanel│ │
│  │ (react-    │  │ (client-    │  │ (from link   │ │
│  │  arborist) │  │  side FTS)  │  │  maps)       │ │
│  └────────────┘  └─────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────┘
```

**Implementation details**:

1. **File watching (Python watchdog)**:
   - Watch configured root directories (`/workspace`, `~/.claude`, `.taskmaster/`)
   - Filter for `.md`, `.json`, `.yaml` files
   - Debounce events (100-200ms) to handle rapid writes
   - Use `awaitWriteFinish`-equivalent to avoid reading partial writes

2. **Metadata extraction (backend)**:
   - Parse YAML frontmatter (via `python-frontmatter` or `pyyaml`)
   - Extract markdown links: `[text](url)` and `[[wikilinks]]` via regex
   - Extract headings (levels, text, line numbers)
   - Extract tags (`#tag` patterns)
   - Store as structured JSON per file

3. **Index data structure** (in-memory, Python dict):
   ```python
   file_index: Dict[str, FileMetadata] = {
       "/workspace/CLAUDE.md": FileMetadata(
           path="/workspace/CLAUDE.md",
           title="CLAUDE.md",
           headings=[Heading(level=1, text="CLAUDE.md", line=1), ...],
           links=[Link(text="reference", target="./other.md", line=42), ...],
           tags=["#project", "#config"],
           frontmatter={"type": "config", "scope": "project"},
           modified_at=datetime(2026, 3, 13, ...),
           size_bytes=4096,
       ),
       ...
   }
   ```

4. **Link maps** (Foam's three-map pattern):
   ```python
   forward_links: Dict[str, List[ResolvedLink]]   # source → [targets]
   back_links: Dict[str, List[ResolvedLink]]       # target → [sources]
   unresolved_links: Dict[str, List[str]]           # source → [broken link texts]
   ```

5. **Frontend sync**: On WebSocket `file_changed` event, frontend updates its local MiniSearch index and re-renders affected components. On initial load, backend sends the full index via REST API.

### 3.2 Backlink Generation

**Pattern**: Maintain a bidirectional link map updated incrementally on file change events.

**Algorithm** (runs on backend when a file is modified):

```
function onFileChanged(filePath):
    1. Remove all existing forward links FROM this file
    2. Remove all existing back links TO other files that came FROM this file
    3. Parse the file's new content
    4. Extract all links (markdown links + wikilinks)
    5. For each link:
       a. Resolve the link to a target file path
       b. Add to forward_links[filePath]
       c. Add to back_links[targetPath]
       d. If target doesn't exist, add to unresolved_links[filePath]
    6. Broadcast updated backlinks via WebSocket
```

**Frontend display**: A "Backlinks" panel (similar to Obsidian/Foam) shows all files linking to the currently viewed file, with surrounding context lines.

### 3.3 Link Resolution

**Pattern**: Support two link formats with different resolution strategies.

**Standard Markdown Links** `[text](./path/to/file.md)`:
- Resolve relative to the source file's directory
- Support `../` for parent directory traversal
- Handle URL-encoded paths

**Wiki-style Links** `[[Note Name]]` (optional feature):
- Match against filename (case-insensitive, ignore `.md` extension)
- Normalize spaces, dashes, underscores as equivalent
- Shortest unique path wins (if only one match exists, resolve regardless of folder)
- Support heading references: `[[Note#Heading]]`
- Support display text: `[[Note|Display Text]]`

**Recommendation**: Start with standard markdown link resolution only. Wiki-links are a nice-to-have that adds complexity to the parser and resolver. The agent memory use case primarily uses standard markdown links.

### 3.4 Full-Text Search

**Pattern**: Dual-layer search — fast client-side for instant results, server-side for comprehensive indexing.

**Frontend (MiniSearch)**:
- Index file content in the browser using MiniSearch (~7KB gzipped)
- Supports incremental add/remove (no full re-index needed)
- Fuzzy matching, prefix search, field weighting
- Instant results as user types (<10ms for 1000 documents)
- Index sent from backend on initial load, updated via WebSocket

**Why MiniSearch over alternatives**:

| Library | Size | Incremental | Space Efficiency | API | Best For |
|---------|------|-------------|------------------|-----|----------|
| **MiniSearch** | ~7KB | Yes (add/remove/discard) | ~50% less than Lunr | Simple, clean | Small-medium collections, real-time updates |
| FlexSearch | ~6KB | Limited | Most compact | Complex, advanced | Maximum throughput, large datasets |
| Lunr.js | ~8KB | No (rebuild required) | Larger index | Lunr-specific | Static collections |
| Fuse.js | ~5KB | Yes | In-memory, no index | Very simple | Small lists, fuzzy only |

MiniSearch wins for this use case because:
1. Incremental indexing — can add/remove individual documents when files change, no full rebuild
2. Clean API that maps well to React state management
3. `react-minisearch` integration library exists
4. Half the index size of Lunr for the same collection
5. `discard()` + automatic vacuuming is ideal for file deletion scenarios

**Backend (Whoosh, optional)**:
- Pure Python full-text search library
- Useful for very large vaults (10K+ files) where sending the full index to the client is impractical
- Can serve as a fallback via REST API: `GET /api/search?q=query`
- For MVP, client-side MiniSearch is likely sufficient

### 3.5 Knowledge Graph Visualization

**Pattern**: Force-directed graph using D3-force, rendered as a React component.

**When to build this**: Not MVP. The graph view is visually impressive but not core to the "browse and edit agent memory" use case. Prioritize file tree, search, and backlinks first.

**If/when implemented**:

1. **Data source**: The `forward_links` and `back_links` maps from the indexing service
2. **Layout**: D3-force with:
   - Link force (edges pull connected nodes together)
   - Charge force (nodes repel each other)
   - Center force (gravity toward viewport center)
3. **Rendering options**:
   - **React Flow** (already recommended for Agent Builder #60): DOM-based, nodes can contain React components, interactive
   - **D3 + SVG**: Lighter weight, good for read-only visualization
   - **Sigma.js / WebGL**: For large graphs (1000+ nodes) — overkill for agent memory
4. **Node coloring**: Color by file type (CLAUDE.md = blue, settings = green, plans = orange, tasks = yellow)
5. **Interaction**: Click node to navigate to file, hover for preview tooltip

**Estimated node count for typical agent workspace**:
- CLAUDE.md files: 3-5 (global, project, local + any subdirectory ones)
- Settings files: 3-5
- Task files: 10-50
- Plan files: 5-20
- Research/memory files: 10-50
- Other markdown: varies

Total: ~30-130 nodes. D3-force + SVG handles this easily without WebGL.

### 3.6 Live Preview / Toggle Architecture

**Pattern**: Two rendering modes sharing the same document state.

The existing research already recommends this architecture:
1. **Read/preview mode**: Tiptap in read-only mode (renders GFM, code blocks, tables, task lists, Mermaid)
2. **WYSIWYG edit mode**: Tiptap in edit mode (same renderer, now editable)
3. **Raw markdown mode**: CodeMirror 6 with markdown language support (for users who prefer source editing)

**Toggle mechanism**: A mode selector (Read / Edit / Source) in the toolbar. The document content is the source of truth as a markdown string. Tiptap serializes/deserializes via `@tiptap/markdown`. CodeMirror works directly with the markdown string.

**Sync pattern**:
```
Markdown String (source of truth)
    ↕ (serialize/deserialize)
Tiptap ProseMirror Document (WYSIWYG mode)
    ↕ (direct edit)
CodeMirror Text Buffer (source mode)
```

---

## 4. Agent Memory Specific Patterns

### 4.1 CLAUDE.md Hierarchy Aggregation

Claude Code loads CLAUDE.md files from multiple levels with a defined precedence:

| Level | Location | Precedence |
|-------|----------|-----------|
| Enterprise | System-wide policies | Highest |
| User Global | `~/.claude/CLAUDE.md` | High |
| Project | `./CLAUDE.md` | Medium |
| Project Local | `./.claude/CLAUDE.md` (deprecated) | Lower |
| Subdirectory | `./subdir/CLAUDE.md` (loaded on demand) | Lowest (most specific wins for conflicts) |

**Recommended "Agent Memory" view**:

1. **Hierarchical display**: Show all CLAUDE.md files in a tree, grouped by scope level
2. **Precedence indicators**: Visual badges showing which level each file belongs to (e.g., colored tags: Global, Project, Local)
3. **Merged view**: A read-only "effective configuration" view that shows the merged result of all CLAUDE.md files, with inline annotations showing which file each section comes from
4. **Diff on change**: When a CLAUDE.md file is modified, show a side-by-side diff highlighting what changed (using react-diff-viewer, already recommended in frontend research)

**Implementation approach**:

```
Agent Memory View
├── 📋 Effective Configuration (merged, read-only)
│   └── Sections annotated with source file
├── 🌍 Global (~/.claude/CLAUDE.md)
├── 📁 Project (/workspace/CLAUDE.md)
├── 📁 Project Settings (/workspace/.claude/CLAUDE.md)
└── 📂 Subdirectory CLAUDE.md files (discovered on demand)
```

### 4.2 Settings File Navigation

Beyond CLAUDE.md, agent memory includes:

| File Type | Purpose | Location |
|-----------|---------|----------|
| `settings.json` | Claude Code settings | `.claude/settings.json`, `~/.claude/settings.json` |
| `settings.local.json` | Personal overrides (gitignored) | `.claude/settings.local.json` |
| `mcp.json` | MCP server configuration | `.claude/mcp.json`, `~/.claude/mcp.json` |
| Plans | Task execution plans | `.taskmaster/plans/` |
| Tasks | Task definitions and specs | `.taskmaster/tasks/` |
| Research | Research findings | `.taskmaster/research/` |
| Memory | Persistent agent memory | `.claude/projects/*/memory/` |

**Quick Links panel**: A sidebar section with direct links to common agent config files, grouped by category:
- **Config**: CLAUDE.md files, settings.json, mcp.json
- **Tasks**: Active plans, task queue, research
- **Memory**: Memory files from `.claude/projects/*/memory/`

### 4.3 Config Precedence Visualization

For JSON settings files that have multiple layers (like `settings.json`), show:

1. **Which file defines which setting**: A table view where each setting row shows the value and its source file
2. **Override highlighting**: When a project setting overrides a global setting, show the global value struck through with the project value highlighted
3. **Unresolved conflicts**: Flag settings that appear at multiple levels for review

---

## 5. Recommended Approach for the Dev Toolkit

### Phase 1 (MVP): Core Browsing & Editing

1. **File tree** (react-arborist): Browse `.md` files across configured root directories
2. **Markdown rendering** (Tiptap read-only or markdown-it + React): Render GFM with syntax highlighting
3. **Raw editing** (CodeMirror 6): Edit markdown files with syntax highlighting and save
4. **File search** (MiniSearch): Full-text search across all indexed markdown files
5. **Navigation**: Breadcrumbs, back/forward, clicking markdown links navigates within the browser

### Phase 2: Knowledge Base Features

6. **Backlinks panel**: Show files linking to the current file
7. **Agent Memory view**: Aggregated CLAUDE.md hierarchy with precedence indicators
8. **Quick Links**: Sidebar shortcuts to common agent config files
9. **File watching**: Auto-update file tree and index when files change externally

### Phase 3: Advanced Features

10. **WYSIWYG editing** (Tiptap): Rich text editing with markdown shortcuts
11. **Knowledge graph**: Force-directed graph of file relationships
12. **Config precedence viewer**: Merged view of JSON settings with source annotations
13. **Diff view**: Side-by-side diff for recently changed files

### Technology Mapping

| Feature | Frontend Library | Backend Service |
|---------|-----------------|-----------------|
| File tree | react-arborist | `GET /api/files` (file listing) |
| Markdown rendering | Tiptap (read-only) or react-markdown | — |
| Raw editing | CodeMirror 6 | `GET/PUT /api/files/{path}` |
| WYSIWYG editing | Tiptap | `PUT /api/files/{path}` |
| Full-text search | MiniSearch | `GET /api/index` (initial index) |
| Backlinks | React component | Link maps from MarkdownIndexService |
| File watching | WebSocket client | Python watchdog + WebSocket broadcast |
| Graph view | D3-force or React Flow | Link map data from index |
| Agent Memory view | Custom React component | CLAUDE.md file aggregation service |

---

## 6. Key Architectural Decisions

### Decision 1: Server-Side Indexing, Client-Side Search

**Rationale**: The backend (FastAPI + watchdog) handles file watching and metadata extraction because it has direct filesystem access and can use efficient Python libraries. The frontend handles search because MiniSearch provides instant results without network round-trips. The backend sends the full index to the frontend on initial load and pushes incremental updates via WebSocket.

**Alternative considered**: Full server-side search with Whoosh. Rejected for MVP because it adds network latency to every keystroke. Can be added later as a fallback for very large vaults.

### Decision 2: Three-Map Backlink Architecture (from Foam)

**Rationale**: Foam's pattern of maintaining `forward_links`, `back_links`, and `unresolved_links` maps is the simplest correct implementation. It's O(1) lookup for "what links to this file?" and O(n) update when a file changes (where n is the number of links in that file). This is fast enough for workspaces with thousands of files.

### Decision 3: Standard Markdown Links Only (MVP)

**Rationale**: `[[wiki-links]]` require a custom parser, custom resolver, and custom autocomplete. Standard markdown links `[text](path)` work with existing parsers (markdown-it, Tiptap's markdown extension). Wiki-links can be added in Phase 2 if there's demand.

### Decision 4: No Knowledge Graph in MVP

**Rationale**: The graph view is visually compelling but not actionable for daily agent development work. File tree + search + backlinks cover 95% of navigation needs. Graph can be added in Phase 3 using the same link map data that already powers backlinks.

### Decision 5: MiniSearch over FlexSearch

**Rationale**: MiniSearch supports incremental document add/remove (essential for file watching updates), has a simpler API, uses less memory than alternatives, and has a React integration library. FlexSearch is faster for large datasets but its API is more complex and incremental updates are limited.

---

## 7. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Large vault performance (10K+ .md files) | Slow initial index, high memory usage | Lazy indexing (index on demand as directories are opened), pagination in file tree, backend-only search for large vaults |
| File watcher reliability across platforms | Missed events, stale index | Use watchdog with polling fallback, add a manual "re-index" button, periodic full scan (every 5 minutes) |
| MiniSearch memory usage with full file content | High browser memory for large vaults | Index titles + headings + first 500 chars only; full content search falls back to backend API |
| Markdown link resolution ambiguity | Wrong file opened | Show disambiguation UI when multiple files match; always prefer relative path resolution |
| CLAUDE.md aggregation complexity | Incorrect precedence display | Use Claude Code's documented hierarchy (Enterprise > User > Project > Local); test with real multi-level configs |
| Tiptap ↔ Markdown round-trip fidelity | Formatting loss on save | Extensive testing of round-trip conversion; offer "source mode" as escape hatch for edge cases |

---

## Sources

### Obsidian Architecture
- [MetadataCache and Link Resolution (DeepWiki)](https://deepwiki.com/obsidianmd/obsidian-api/2.4-metadatacache-and-link-resolution)
- [Plugin Development (DeepWiki)](https://deepwiki.com/obsidianmd/obsidian-api/3-plugin-development)
- [API Reference (DeepWiki)](https://deepwiki.com/obsidianmd/obsidian-api/5-api-reference)
- [Internal Links - Obsidian Help](https://help.obsidian.md/links)
- [Obsidian Wiki Link Rules (GitHub Gist)](https://gist.github.com/dhpwd/9bb86c53b69cb63e09ccca42e3bf924c)
- [Obsidian Developer Documentation](https://docs.obsidian.md/)

### Foam Architecture
- [Foam VS Code Extension (DeepWiki)](https://deepwiki.com/foambubble/foam/2.3-vs-code-extension)
- [Foam GitHub Repository](https://github.com/foambubble/foam)

### Dendron
- [Dendron Documentation](https://wiki.dendron.so/)
- [Dendron Features](https://wiki.dendron.so/notes/4bb85c39-d8ac-48ad-a765-3f2a071f7bc9/)

### Notable
- [Notable App](https://notable.app/)

### MarkText
- [MarkText Architecture (GitHub)](https://github.com/marktext/marktext/blob/develop/docs/dev/ARCHITECTURE.md)

### Zettlr
- [Zettlr 4.0 Release Notes](https://zettlr.com/post/zettlr-400-released)

### Search Libraries
- [MiniSearch Documentation](https://lucaong.github.io/minisearch/)
- [MiniSearch Design Document (GitHub)](https://github.com/lucaong/minisearch/blob/master/DESIGN_DOCUMENT.md)
- [react-minisearch (npm)](https://www.npmjs.com/package/react-minisearch)
- [FlexSearch (GitHub)](https://github.com/nextapps-de/flexsearch)
- [Whoosh - Pure Python Full-Text Search](https://whoosh.readthedocs.io/en/latest/intro.html)

### File Watching
- [Chokidar (GitHub)](https://github.com/paulmillr/chokidar)
- [Python Watchdog (PyPI)](https://pypi.org/project/watchdog/)

### Graph Visualization
- [Obsidian Graph View - Physics and Force-Directed Graphs (Forum)](https://forum.obsidian.md/t/graph-view-physics-and-force-directed-graphs/72586)
- [3D Force-Directed Graph (GitHub)](https://github.com/vasturiano/3d-force-graph)

### CLAUDE.md Hierarchy
- [Claude Code Memory Documentation](https://code.claude.com/docs/en/memory)
- [CLAUDE.md Files and Memory Hierarchy (DeepWiki)](https://deepwiki.com/FlorianBruniaux/claude-code-ultimate-guide/4.1-claude.md-files-and-memory-hierarchy)

### Tiptap / ProseMirror
- [Tiptap Core Concepts](https://tiptap.dev/docs/editor/core-concepts/introduction)
- [Tiptap Markdown Support](https://tiptap.dev/docs/editor/markdown)
- [Tiptap Extension API](https://tiptap.dev/docs/editor/extensions/custom-extensions/create-new/extension)

### react-arborist
- [react-arborist (GitHub)](https://github.com/brimdata/react-arborist)
