# Markdown Editor Library Research for Dev Toolkit (#57)

Research conducted: 2026-03-13
Context: GitHub Issue #57 — Markdown Browser & Editor for agent memory, docs, and notes

---

## Executive Summary

After evaluating 12+ editor libraries across WYSIWYG, code, and hybrid categories, the **recommended architecture** is:

- **Primary WYSIWYG editor**: **Tiptap** (ProseMirror-based, MIT, headless, extensible)
- **Raw markdown mode**: **CodeMirror 6** (lightweight, modular, excellent markdown support)
- **Worth considering as alternative**: **MDXEditor** (Lexical-based, built-in frontmatter, simpler but less flexible)

---

## Part 1: Detailed Evaluation of All Candidates

### WYSIWYG / Block Editors

#### 1. Tiptap — RECOMMENDED

| Metric | Value |
|--------|-------|
| npm weekly downloads | ~5.9M (`@tiptap/core`) |
| GitHub stars | 35,579 |
| License | MIT (core + most extensions) |
| Foundation | ProseMirror |
| Bundle size (starter-kit) | ~45-60 KB gzipped (modular, tree-shakable) |
| React support | First-class (`@tiptap/react`) |
| Collaboration | Yjs/Liveblocks support |
| Open issues | ~891 |

**Strengths:**
- Dominant adoption — nearly 6M weekly downloads, the most-used rich text editor framework
- 100+ extensions available, most now MIT-licensed (previously some were paid "Pro")
- Headless architecture: full control over UI, theming, and rendering
- Excellent markdown support via `@tiptap/markdown` (bidirectional parse/serialize)
- Custom node extensions allow building frontmatter editors, agent config blocks, etc.
- Markdown shortcuts out-of-the-box (type `## ` for H2, `**` for bold, etc.)
- Official keyboard shortcuts for formatting (Ctrl+B, Ctrl+I, etc.)
- Y.js collaboration support for future real-time editing
- Active development: v3.x released, updates as recent as March 2026
- Extensive documentation and community examples

**Weaknesses:**
- No built-in raw markdown source view — requires custom toggle implementation (e.g., switch to CodeMirror)
- Performance requires following best practices (avoid state traversal during transactions, `shouldRerenderOnTransaction: false`)
- Deep customization requires ProseMirror knowledge
- No built-in frontmatter editor (must build as custom node extension)
- 891 open issues suggests high usage but also some backlog

**Markdown Fidelity:**
The Markdown extension provides bidirectional conversion. Custom serializers/parsers can be defined per extension to maintain clean markdown output. The `editor.getMarkdown()` and `setContent(md, { contentType: 'markdown' })` APIs are clean.

**Frontmatter Approach:**
Build a custom Node extension using `addNodeView()` to render a YAML form editor. Define `parseMarkdown` to capture `---` fenced YAML blocks and `renderMarkdown` to serialize back. This is well-supported by the extension architecture.

---

#### 2. Milkdown

| Metric | Value |
|--------|-------|
| npm weekly downloads | ~91K (`@milkdown/core`) |
| GitHub stars | 11,179 |
| License | MIT |
| Foundation | ProseMirror + remark |
| Bundle size | ~40 KB gzipped (core) |
| React support | `@milkdown/react` |
| Collaboration | Yjs support |
| Open issues | ~28 |

**Strengths:**
- Markdown-first: every editor state maps 1:1 to valid markdown (excellent fidelity)
- Plugin-based architecture with composable plugins (v7)
- Lightweight core (~40KB gzipped)
- Built on remark ecosystem — access to remark/rehype plugins
- Low issue count (28) suggests good stability
- Theme system with customizable styling

**Weaknesses:**
- **No frontmatter support** — feature request opened March 2025 (Issue #1712), still open
- Much smaller community (91K downloads vs Tiptap's 5.9M)
- React integration requires manual UI component construction (no pre-built toolbar/menus)
- Less documentation and fewer examples than Tiptap
- No built-in raw markdown toggle
- Fewer ready-made extensions

**Markdown Fidelity:**
Best-in-class. Milkdown's core principle is "for every state, there is an equal markdown." This means round-trip fidelity is guaranteed by design.

**Verdict:** Excellent markdown fidelity but the missing frontmatter support and smaller ecosystem are dealbreakers for the agent memory use case.

---

#### 3. BlockNote

| Metric | Value |
|--------|-------|
| npm weekly downloads | ~160K (`@blocknote/core`) |
| GitHub stars | 9,213 |
| License | AGPL-3.0 (core), some features require commercial license |
| Foundation | ProseMirror → Tiptap → BlockNote (3 layers) |
| Bundle size | ~150-200 KB gzipped; **788KB+ with Shiki code highlighting** |
| React support | `@blocknote/react` (React-focused) |
| Collaboration | Yjs support |
| Open issues | ~191 |

**Strengths:**
- Notion-like UX out of the box: slash menus, drag/drop, block nesting
- Built-in formatting toolbar, animations, and polished UI
- AI integration via `@blocknote/xl-ai`
- TypeScript-first with strong typing
- Collaboration via Yjs

**Weaknesses:**
- **Heavy bundle size** — base is large, and Shiki code highlighting adds 788KB (192KB gzipped)
- Three layers of abstraction (ProseMirror → Tiptap → BlockNote) makes deep customization difficult
- AGPL-3.0 license for core; some exporters require commercial license
- React-focused — limited portability
- Block-based model may not map cleanly to raw markdown editing
- Markdown conversion is not 1:1 (goes through BlockNote JSON intermediate format)

**Markdown Fidelity:**
Moderate. BlockNote uses its own JSON document model. Markdown import/export exists but goes through an intermediate format. Not ideal for preserving exact markdown formatting.

**Verdict:** Too heavy, too abstracted, and licensing concerns. The Notion-like UX is nice but overkill for a markdown-focused tool.

---

#### 4. Plate

| Metric | Value |
|--------|-------|
| npm weekly downloads | ~87K (`@udecode/plate`) |
| GitHub stars | 16,017 |
| License | MIT |
| Foundation | Slate.js |
| Bundle size | Modular (varies by plugins) |
| React support | First-class (React-focused) |
| Collaboration | Hocuspocus only |
| Open issues | ~35 |

**Strengths:**
- Comprehensive plugin system with per-plugin Zustand stores
- Headless architecture with shadcn/ui component library
- Bidirectional markdown with `MarkdownPlugin`
- Low open issue count (35)
- SSR support

**Weaknesses:**
- Slate.js foundation: fewer resources than ProseMirror ecosystem
- Collaboration limited to Hocuspocus (no Yjs/Liveblocks)
- Smaller community than Tiptap
- Less battle-tested at scale
- Complex setup for full-featured editor

**Markdown Fidelity:**
Good. The MarkdownPlugin provides bidirectional conversion with customizable mdast ↔ Plate JSON rules.

**Verdict:** Strong alternative to Tiptap, but the smaller ProseMirror-alternative ecosystem and limited collaboration options are drawbacks.

---

#### 5. Lexical

| Metric | Value |
|--------|-------|
| npm weekly downloads | ~2.2M |
| GitHub stars | 23,068 |
| License | MIT |
| Foundation | Custom (Meta) |
| Bundle size | Core is small (~10-15KB); grows with plugins |
| React support | `@lexical/react` |
| Collaboration | Yjs/Liveblocks |
| Open issues | ~559 |

**Strengths:**
- Meta-backed with active development
- Minimal core — pay for what you use
- Strong React 18+ integration
- Good markdown import/export (`@lexical/markdown`)
- Headless, SSR-capable
- Foundation for MDXEditor

**Weaknesses:**
- Less mature markdown ecosystem than ProseMirror/Tiptap
- Fewer community extensions
- Collaboration has edge-case bugs
- Steeper learning curve for custom nodes
- Documentation improving but still gaps

**Markdown Fidelity:**
Good. Serialization supports JSON, Markdown, and HTML. Custom transformers allow fine-tuning.

**Verdict:** Strong framework but not the best fit for a markdown-first tool. Better as a general rich text framework.

---

### Code Editors (for Raw Markdown Mode)

#### 6. CodeMirror 6 — RECOMMENDED for raw mode

| Metric | Value |
|--------|-------|
| Bundle size | ~93KB gzipped (basic-setup); modular imports can reduce further |
| Markdown support | `@codemirror/lang-markdown` |
| Mobile support | Excellent (native platform integration) |
| Accessibility | Built-in screen reader + keyboard navigation |
| React wrapper | `@uiw/react-codemirror` |

**Why CodeMirror over Monaco:**
- **43% smaller bundle** than Monaco (which adds 2.4-5MB)
- Modular: import only what you need
- Superior mobile support (Monaco is unusable on mobile)
- Built-in accessibility features
- Markdown syntax highlighting with nested code block highlighting
- Used by Sourcegraph, Replit, and many others

---

#### 7. Monaco Editor

| Metric | Value |
|--------|-------|
| Bundle size | **5-10MB uncompressed; 2.4MB+ optimized** |
| Features | Full VS Code experience |
| Mobile support | **Not supported** |

**Verdict:** Too heavy for a markdown editor. The VS Code feature set is overkill. Use CodeMirror 6 instead.

---

### Hybrid / Purpose-Built Markdown Editors

#### 8. MDXEditor — STRONG ALTERNATIVE

| Metric | Value |
|--------|-------|
| npm weekly downloads | ~313K |
| GitHub stars | 3,282 |
| License | MIT |
| Foundation | Lexical |
| Bundle size | ~598KB (up to 851KB gzipped with all plugins) |
| React support | Native React component |
| Open issues | ~88 |

**Strengths:**
- **Built-in frontmatter support** (`frontmatterPlugin()` + `InsertFrontmatter` toolbar button)
- Purpose-built for markdown/MDX editing
- Inline WYSIWYG editing (formatting appears as you type, no preview pane needed)
- Plugin system keeps bundle small (only include what you need)
- Supports tables, images, code blocks, syntax highlighting
- Works with Next.js, Vite, Remix out of the box

**Weaknesses:**
- Heavier bundle than Tiptap (598KB-851KB vs ~50KB)
- Less extensible than Tiptap for custom block types
- Smaller community (3.2K stars vs 35K)
- MDX-focused: some features oriented toward JSX-in-markdown which we don't need
- No built-in raw markdown source toggle
- Accessibility documentation sparse

**Frontmatter Implementation:**
```tsx
<MDXEditor
  markdown={content}
  plugins={[
    frontmatterPlugin(),
    toolbarPlugin({ toolbarContents: () => <InsertFrontmatter /> })
  ]}
/>
```

**Verdict:** If the priority is "get frontmatter editing working fast with minimal custom code," MDXEditor is the fastest path. But it trades flexibility and bundle size for convenience.

---

#### 9. ByteMD

| Metric | Value |
|--------|-------|
| Foundation | Svelte (with React wrapper) |
| Architecture | Split-pane (editor + preview) |
| Plugin system | remark/rehype based |

**Strengths:** Lightweight, XSS-safe, split-pane preview. 
**Weaknesses:** Svelte-based (React wrapper is a shim), split-pane is not true WYSIWYG, smaller community.
**Verdict:** Not suitable — split-pane model doesn't match the "Obsidian-like" vision.

---

#### 10. Vditor

**Verdict:** Chinese-origin, documentation primarily in Chinese. Not recommended for maintainability.

---

## Part 2: Architecture Recommendation

### Recommended Architecture: Tiptap + CodeMirror 6

```
┌─────────────────────────────────────────────┐
│              Markdown Editor Plugin          │
├─────────────────────────────────────────────┤
│                                             │
│  ┌─────────────────┐  ┌──────────────────┐ │
│  │   WYSIWYG Mode  │  │   Source Mode    │ │
│  │   (Tiptap)      │  │   (CodeMirror 6) │ │
│  │                  │  │                  │ │
│  │  - Rich editing  │  │  - Raw markdown  │ │
│  │  - Formatting    │  │  - Syntax HL     │ │
│  │  - Custom blocks │  │  - Line numbers  │ │
│  │  - Frontmatter   │  │  - Search/replace│ │
│  │    form editor   │  │                  │ │
│  └────────┬─────────┘  └────────┬─────────┘ │
│           │                     │            │
│           └──────┬──────────────┘            │
│                  │                           │
│          ┌───────▼────────┐                  │
│          │  Markdown AST  │                  │
│          │  (shared state)│                  │
│          └────────────────┘                  │
│                                             │
├─────────────────────────────────────────────┤
│  Toggle: [WYSIWYG] [Source] [Split Preview] │
└─────────────────────────────────────────────┘
```

**How the toggle works:**
1. User clicks "Source" → `editor.getMarkdown()` serializes Tiptap content → passed to CodeMirror
2. User clicks "WYSIWYG" → CodeMirror raw text → `editor.setContent(md, { contentType: 'markdown' })` → Tiptap renders
3. Unsaved changes tracked in both modes via shared state

### Why This Architecture

| Criterion | Tiptap + CM6 | MDXEditor | BlockNote | Milkdown |
|-----------|-------------|-----------|-----------|----------|
| WYSIWYG quality | Excellent | Good | Excellent | Good |
| Raw markdown mode | Via CodeMirror | None built-in | None built-in | None built-in |
| Markdown fidelity | Good (customizable) | Good | Moderate | Excellent |
| Frontmatter editing | Custom extension | Built-in | None | None |
| Extension system | 100+ extensions | Plugin-based | Limited customization | Plugin-based |
| Bundle size (total) | ~140KB gzipped | ~600-850KB | ~350-950KB | ~130KB |
| Community / support | Dominant | Growing | Growing | Small |
| Collaboration ready | Yjs/Liveblocks | No | Yjs | Yjs |
| License | MIT | MIT | AGPL-3.0 | MIT |
| Keyboard shortcuts | Built-in | Built-in | Built-in | Manual |
| Theming | Full control (headless) | Limited | Pre-styled | Theme system |

### Bundle Size Estimate

| Component | Gzipped Size |
|-----------|-------------|
| `@tiptap/starter-kit` | ~45-55 KB |
| `@tiptap/react` | ~5 KB |
| `@tiptap/markdown` | ~10-15 KB |
| Custom extensions (frontmatter, etc.) | ~5-10 KB |
| `@codemirror/basic-setup` + markdown | ~93 KB |
| `@uiw/react-codemirror` wrapper | ~5-10 KB |
| **Total estimated** | **~165-190 KB** |

vs. MDXEditor alone: **~600-850 KB**
vs. BlockNote with Shiki: **~350-950 KB**

### Key Decisions for the Planner

1. **Tiptap is headless** — we need to build our own toolbar, menus, and UI. This is actually a strength for matching the Dev Toolkit's design system, but it means more upfront work.

2. **Frontmatter must be a custom Tiptap extension** — define a custom Node that parses `---` YAML blocks, renders a key-value form editor in the NodeView, and serializes back to YAML on save. MDXEditor gives this for free.

3. **Mode toggle requires state management** — switching between Tiptap and CodeMirror requires serializing/deserializing markdown. Edge cases: cursor position preservation, undo history across modes, handling parse errors when switching from raw to WYSIWYG.

4. **CodeMirror 6 for raw mode is worth the ~93KB** — provides real syntax highlighting, search/replace, proper cursor handling, and accessibility. A plain `<textarea>` would save bytes but deliver a poor experience.

5. **Y.js is the right collaboration foundation** — both Tiptap and CodeMirror support it, so future real-time editing is achievable without rearchitecting.

### Alternative Approach: MDXEditor for MVP

If time-to-market matters more than flexibility:

- Use MDXEditor as the sole editor component
- Get frontmatter editing, toolbar, and markdown support out of the box
- Accept the larger bundle (~600KB+) and less customization
- CodeMirror 6 could still be added for raw mode
- Migration to Tiptap later is feasible since both produce/consume standard markdown

---

## Part 3: Accessibility Assessment

| Editor | Keyboard Navigation | Screen Reader | ARIA Roles |
|--------|-------------------|---------------|------------|
| Tiptap | Excellent (ProseMirror foundation) | Good (contenteditable) | Customizable |
| CodeMirror 6 | Excellent (built-in) | Built-in support | Yes |
| MDXEditor | Good (Lexical foundation) | Undocumented | Partial |
| BlockNote | Good | Undocumented | Partial |
| Milkdown | Manual setup required | Undocumented | Manual |

Tiptap + CodeMirror 6 provides the best accessibility story since both have documented support.

---

## Part 4: Performance Considerations

**Large file handling (1000+ lines):**
- Tiptap: Good with virtual rendering and lazy node views. Set `shouldRerenderOnTransaction: false` for React.
- CodeMirror 6: Excellent — built for large documents with viewport-based rendering.
- MDXEditor: Untested at scale, Lexical's virtual DOM may help.

**Sub-second file open (acceptance criterion):**
- Tiptap markdown parse + render: should meet this for files under 1MB
- CodeMirror: essentially instant for any reasonable file size
- Risk area: initial parse of very large markdown with many code blocks, tables, or embedded content

---

## Part 5: Special Requirements Assessment

### Frontmatter-aware editing

| Editor | Support | Effort |
|--------|---------|--------|
| MDXEditor | Built-in `frontmatterPlugin()` | Zero |
| Tiptap | Custom Node extension | Medium (2-3 days) |
| Milkdown | No support (open feature request) | High |
| BlockNote | No support | High |

### Syntax highlighting for embedded code blocks

| Editor | Support |
|--------|---------|
| Tiptap | Via `@tiptap/extension-code-block-lowlight` (free, uses lowlight/highlight.js) |
| CodeMirror 6 | Native multi-language support |
| MDXEditor | Built-in via Lexical code blocks |
| BlockNote | Via Shiki (+788KB bundle cost) |

### Side-by-side preview

All approaches support this as a layout concern — render markdown on one side, source/WYSIWYG on the other.

### Cross-file link navigation

Must be implemented at the plugin host level regardless of editor choice. The editor needs to intercept `[link](./other.md)` clicks and emit a navigation event. Tiptap's `Link` extension supports custom `onClick` handlers.

---

## References

- [Liveblocks 2025 Editor Comparison](https://liveblocks.io/blog/which-rich-text-editor-framework-should-you-choose-in-2025)
- [Tiptap Documentation](https://tiptap.dev/docs)
- [Tiptap Markdown Extension](https://tiptap.dev/docs/editor/markdown)
- [CodeMirror 6 Documentation](https://codemirror.net/docs/ref/)
- [MDXEditor Documentation](https://mdxeditor.dev/editor/docs/overview)
- [MDXEditor Frontmatter Plugin](https://mdxeditor.dev/editor/docs/front-matter)
- [BlockNote Documentation](https://www.blocknotejs.org/)
- [Milkdown Documentation](https://milkdown.dev/)
- [Milkdown Frontmatter Issue #1712](https://github.com/Milkdown/milkdown/issues/1712)
- [Plate Documentation](https://platejs.org/)
- [npm trends comparison](https://npmtrends.com/@tiptap/core-vs-@milkdown/core-vs-@blocknote/core-vs-lexical-vs-@mdxeditor/editor-vs-@udecode/plate)
- [Sourcegraph: Migrating Monaco to CodeMirror](https://sourcegraph.com/blog/migrating-monaco-codemirror)
- [BlockNote Bundle Size Issue #1487](https://github.com/TypeCellOS/BlockNote/issues/1487)
- [Tiptap Open-Sources Pro Extensions](https://tiptap.dev/blog/release-notes/were-open-sourcing-more-of-tiptap)
