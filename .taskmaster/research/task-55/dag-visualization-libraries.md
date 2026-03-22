# DAG Visualization Libraries for Agent Builder (#60)

**Research for**: Dev Toolkit (Epic #55, Agent Builder #60)  
**Date**: 2026-03-13  
**Context**: The Agent Builder needs to visualize a dependency graph (DAG) of agents, commands, hooks, and MCP servers. Expected scale: 50–200 nodes, hierarchical layout, interactive (click to navigate, hover for details, zoom/pan).

---

## 1. Executive Summary

**Recommendation: React Flow (@xyflow/react) + ELK.js for layout**

React Flow is the clear winner for the Agent Builder's DAG visualization needs. It renders nodes as actual React/HTML components (not Canvas or SVG primitives), which means DAG nodes can contain rich content — icons, labels, status badges, clickable links, and mini-previews of agent definitions. Combined with ELK.js for automatic hierarchical layout, this pairing provides the best balance of interactivity, customizability, and DAG-specific layout quality.

This aligns with the frontend framework decision (React + Vite + shadcn/ui) already made in the [frontend-framework-comparison.md](frontend-framework-comparison.md).

---

## 2. Library Comparison Matrix

| Criterion | React Flow | Cytoscape.js | D3.js + d3-dag | G6 (AntV) | vis-network | Sigma.js | Mermaid.js |
|---|---|---|---|---|---|---|---|
| **Rendering** | DOM (HTML/React) | Canvas (HTML5) | SVG | Canvas/WebGL/SVG | Canvas | WebGL | SVG (static) |
| **React nodes in graph** | **Yes (native)** | No (Canvas pixels) | No (SVG only) | Yes (v5+) | No (Canvas) | No (WebGL) | No |
| **DAG layout built-in** | No (uses external) | Via dagre plugin | Via d3-dag/dagre | Built-in dagre/elk | Hierarchical mode | No | dagre/elk renderer |
| **Layout engines** | Dagre, ELK, D3 | Dagre, CoSE, Cola, etc. | Sugiyama, Zherebko | 10+ layouts, WASM | Hierarchical, Force | Force-directed | Dagre, ELK |
| **Interactivity** | Excellent | Excellent | Manual (DIY) | Good | Good | Good (large graphs) | Minimal |
| **Zoom/Pan** | Built-in | Built-in | Manual (DIY) | Built-in | Built-in | Built-in | No |
| **Minimap** | Built-in component | Via extension | No | Built-in plugin | No | No | No |
| **Edge routing** | Via ELK | Via layout plugin | Manual | Built-in | Basic | No | Via renderer |
| **Click/hover events** | Native React events | Canvas hit detection | SVG events | Event system | Canvas events | WebGL picking | Limited |
| **Custom node content** | **Full React components** | Canvas drawing API | SVG elements | React nodes (v5+) | HTML via title | Labels only | Text only |
| **Export (SVG/PNG)** | Via html-to-image | Yes (Canvas export) | Native SVG | Yes (Canvas export) | Yes (Canvas export) | Yes (WebGL export) | Native SVG |
| **Accessibility** | **ARIA roles, keyboard nav, screen reader** | Limited | Manual | Limited | Limited | Limited | Static only |
| **Bundle size (gz)** | ~40KB | ~170KB | ~30KB (d3-dag) | ~300KB+ | ~170KB | ~40KB | ~200KB |
| **NPM weekly downloads** | ~850K (@xyflow/react) | ~2.5M | ~55K (d3-dag) | ~147K | ~300K (vis) | ~57K | ~3M+ |
| **GitHub stars** | 35.6K | 10.6K | 2.1K | 12K | 3K | 11.3K | 73K+ |
| **License** | MIT | MIT | MIT | MIT | Apache-2.0 | MIT | MIT |
| **Maintenance** | **Very active** (2026) | Active (monthly) | Light maintenance | Active (Ant Group) | Community-driven | Active | Very active |
| **TypeScript** | First-class | Types available | Types available | TypeScript-first | Types via @types | TypeScript-first | Types available |

---

## 3. Detailed Library Analysis

### 3.1 React Flow (@xyflow/react) — RECOMMENDED

**What it is**: A React library for building node-based UIs — workflow editors, flow charts, DAG visualizers. Maintained by the xyflow team. Used by ~12,000 dependent projects including Stripe, Typeform, and many AI/ML workflow builders.

**Version**: 12.x (`@xyflow/react`, successor to `reactflow` v11)

**Key strengths for Agent Builder**:

1. **Nodes are React components**: Each DAG node can be a full React component with shadcn/ui buttons, icons, tooltips, status badges. An agent node can show the agent name, model, tool count, and a mini-preview. A command node can show its slash-command syntax. This is impossible with Canvas-based libraries (Cytoscape, vis-network, G6).

2. **Best-in-class accessibility**: ARIA roles (`role="group"`, `aria-label`, `aria-roledescription`), keyboard navigation (Tab to nodes, Enter/Space to select, arrow keys to move), `aria-live` regions for announcing changes. Meets WCAG 2.1 AA criteria.

3. **Built-in components**: MiniMap, Controls (zoom in/out/fit), Background (dots/lines/cross), Panel (overlay UI). All ready to use with zero configuration.

4. **Excellent documentation**: Official examples for dagre layout, ELK layout, D3-hierarchy layout, auto-layout, sub-flows, and more at reactflow.dev/examples.

5. **React ecosystem fit**: Works naturally with React state management, React Router, shadcn/ui theming, and the toolkit's existing component library choices.

6. **Active development**: Last release Feb 2026, 6,053 commits, 369 releases, 126 contributors.

**Weaknesses**:

1. **No built-in layout**: Requires an external layout engine (dagre, ELK, D3). This is by design — React Flow handles rendering and interaction, layout engines handle positioning.

2. **DOM-based rendering has a ceiling**: For very large graphs (1000+ nodes), DOM rendering is slower than Canvas/WebGL. Not a concern for 50–200 nodes.

3. **Export quirks**: PNG/SVG export uses `html-to-image` which has known issues with edge rendering. Workaround: `dom-to-svg` or server-side rendering with Puppeteer.

**Layout engine pairing**:

| Layout Engine | Bundle Size | Complexity | Best For | Edge Routing |
|---|---|---|---|---|
| **Dagre** | ~40KB | Low | Simple trees/DAGs | No |
| **ELK.js** | ~1.5MB | High | Complex DAGs, nested groups | Yes |
| **D3-Hierarchy** | ~15KB | Low | Single-root trees | No |

**Recommendation**: Start with **dagre** for simplicity (Agent Builder's graph is a relatively simple DAG). Upgrade to **ELK.js** if edge routing or nested subgraph support becomes needed. Note: dagre's npm package is technically unmaintained (last update 2018), but `@dagrejs/dagre` is the updated fork receiving patches.

**Example DAG node for Agent Builder**:
```tsx
function AgentNode({ data }) {
  return (
    <div className="rounded-lg border bg-card p-3 shadow-sm">
      <div className="flex items-center gap-2">
        <BotIcon className="h-4 w-4" />
        <span className="font-medium">{data.name}</span>
      </div>
      <div className="text-xs text-muted-foreground mt-1">
        {data.model} · {data.toolCount} tools
      </div>
      <Handle type="target" position={Position.Top} />
      <Handle type="source" position={Position.Bottom} />
    </div>
  );
}
```

### 3.2 Cytoscape.js — Strong Alternative

**What it is**: A graph theory library for visualization and analysis. Used by dbt-docs, Nx project graph, and many bioinformatics tools. The most downloaded graph library on npm (~2.5M/week).

**Version**: 3.33.x

**Key strengths**:

1. **Richest layout ecosystem**: Dagre, CoSE (compound spring embedder), Cola (constraint-based), fCoSE (fast compound), Euler, breadthfirst, concentric, circle, grid — all via plugins.
2. **Graph theory built-in**: Shortest path, minimum spanning tree, centrality, clustering algorithms.
3. **Battle-tested for DAGs**: dbt and Nx both use Cytoscape for their lineage/dependency graphs.
4. **Compound nodes**: Native support for parent-child grouping (e.g., group agents by category).
5. **Very mature**: Monthly feature releases, weekly patches.

**Weaknesses**:

1. **Canvas-based**: Nodes are drawn on Canvas, not HTML. Cannot use React components inside nodes. Node content is limited to shapes, text labels, and images. This is the critical limitation for the Agent Builder — you cannot put a shadcn/ui card with interactive elements inside a Cytoscape node.
2. **React integration is imperative**: Cytoscape uses an imperative API (`cy.add()`, `cy.layout()`) which fights React's declarative paradigm. The `react-cytoscapejs` wrapper helps but is a thin bridge.
3. **No built-in accessibility**: No ARIA support, no keyboard navigation out of the box.

**When to choose Cytoscape over React Flow**: If you need graph algorithms (shortest path, clustering), compound node grouping, or are building a graph analysis tool rather than an interactive visual editor. Also if node content doesn't need to be rich React components.

### 3.3 D3.js + d3-dag — Low-Level Power

**What it is**: D3 is a low-level data visualization library. `d3-dag` adds DAG-specific layout algorithms (Sugiyama, Zherebko, Grid).

**Key strengths**:

1. **Full control**: You own every SVG element. No library conventions to fight.
2. **Sugiyama algorithm**: The gold standard for layered DAG layout (minimizes edge crossings).
3. **Tiny bundle**: d3-dag is ~30KB gzipped.

**Weaknesses**:

1. **Conflicts with React**: D3 manipulates the DOM directly. React also wants to manage the DOM. Using both requires careful isolation (e.g., D3 in a `useEffect` hook with a ref, or using D3 for data/layout only and React for rendering).
2. **Everything is DIY**: No built-in zoom/pan, minimap, node interaction, edge routing. You build it all.
3. **d3-dag is in light maintenance**: The maintainer has stated they won't expand to new use cases.
4. **Steep learning curve**: D3's enter/update/exit pattern and scales/axes take significant time to master.

**When to choose D3**: Only if you need a highly custom visualization that no other library can provide, or if you're using D3 for layout calculations only and feeding positions to React Flow.

### 3.4 G6 (AntV) — Feature-Rich but Heavyweight

**What it is**: A graph visualization engine by Ant Group. Part of the AntV ecosystem (alongside G2 for charts, S2 for tables).

**Version**: 5.x

**Key strengths**:

1. **Built-in layouts**: 10+ layouts including dagre, antv-dagre (enhanced dagre), force, circular, radial, grid — no external library needed.
2. **GPU acceleration**: Some layouts use WebGPU/WASM for performance on large graphs.
3. **React nodes (v5)**: Version 5 added support for rendering React components as nodes.
4. **3D support**: Can render 3D graphs if needed.
5. **Rich theming**: Light/dark themes with 20+ color palettes.

**Weaknesses**:

1. **Large bundle**: ~300KB+ gzipped. Significantly heavier than React Flow.
2. **Ant Group ecosystem lock-in**: Documentation and examples are primarily in Chinese. English docs exist but are less comprehensive.
3. **Smaller Western community**: Harder to find Stack Overflow answers, English tutorials, or community plugins.
4. **React integration is newer**: The React node support in v5 is less battle-tested than React Flow's native approach.

**When to choose G6**: If you need GPU-accelerated layout for very large graphs (1000+ nodes) or want built-in graph analytics. Overkill for 50–200 nodes.

### 3.5 vis-network — Aging but Simple

**What it is**: Part of the vis.js ecosystem. Displays interactive network graphs with automatic layout.

**Key strengths**:

1. **Simple API**: Easy to get a graph rendering quickly with minimal configuration.
2. **Built-in hierarchical layout**: Native support for top-down/left-right directed layouts.
3. **Clustering**: Automatic clustering of densely connected nodes.

**Weaknesses**:

1. **Canvas-based**: Same limitation as Cytoscape — no React components in nodes.
2. **Community-maintained**: The original vis.js team disbanded. The visjs community org maintains it, but development is slower.
3. **Apache 2.0 license**: Not a dealbreaker, but different from the MIT-licensed alternatives.
4. **Less configurable**: Fewer layout options and less edge routing control than Cytoscape or ELK.

**When to choose vis-network**: For quick prototypes or simple network visualizations where rich node content isn't needed.

### 3.6 Sigma.js — Wrong Fit

**What it is**: A WebGL-based graph renderer optimized for large graphs (10K–100K nodes).

**Key strengths**:

1. **WebGL performance**: Handles huge graphs that would bring D3/Cytoscape to their knees.
2. **React wrapper**: `@react-sigma/core` provides React integration.

**Weaknesses**:

1. **Designed for large networks**: The performance advantages are irrelevant at 50–200 nodes.
2. **Force-directed only**: No hierarchical/layered DAG layout. Needs external layout.
3. **Minimal node customization**: Labels only, no rich node content.
4. **No edge routing**: Edges are straight lines.

**When to choose Sigma.js**: Only for very large graph visualizations (social networks, knowledge graphs with 10K+ nodes). Wrong tool for a 50–200 node DAG.

### 3.7 Mermaid.js — Diagram-as-Code (Complementary)

**What it is**: A text-to-diagram library. Already relevant to the toolkit via Issue #57 (Markdown Browser).

**Key strengths**:

1. **Text-first**: Define graphs in markdown-like syntax. Perfect for documentation and static rendering.
2. **Multiple renderers**: Uses dagre by default, ELK optionally.
3. **Wide adoption**: 73K+ GitHub stars. Supported in GitHub markdown, VS Code, Notion, etc.

**Weaknesses**:

1. **Static output**: Renders SVG that is not interactive (no click-to-navigate, no drag, no zoom/pan).
2. **No event handling**: Cannot attach click handlers to nodes.
3. **Not a graph editor**: Read-only visualization only.

**When to use Mermaid**: For the CLI `agent-builder graph` command that outputs a text-based DAG representation. Also for embedding static DAG previews in markdown documentation. **Not** for the interactive web UI.

**Complementary role**: Mermaid can be used for the `agent-builder graph` CLI output (DOT-format or Mermaid syntax), while React Flow handles the interactive web visualization. The two serve different use cases and can coexist.

---

## 4. Layout Algorithm Deep Dive

The layout algorithm determines how nodes are positioned. This is separate from the rendering library.

### 4.1 Dagre (Layered/Hierarchical)

- **Algorithm**: Simplified Sugiyama with four phases: rank assignment, ordering, position, edge routing
- **Bundle**: ~40KB gzipped
- **Maintenance**: Original `dagre` package last updated 2018. `@dagrejs/dagre` fork receives patches.
- **Used by**: Mermaid (default renderer), React Flow examples, many DAG tools
- **Pros**: Fast, simple API, good results for tree-shaped DAGs
- **Cons**: No edge routing (edges go through nodes), no compound/nested node support, limited configuration
- **Best for**: Simple DAGs with 10–100 nodes and mostly tree-like structure

### 4.2 ELK.js (Eclipse Layout Kernel)

- **Algorithm**: Multiple algorithms, primarily "layered" (enhanced Sugiyama) with sophisticated edge routing
- **Bundle**: ~1.5MB gzipped (large because it's a Java-to-JS transpilation)
- **Maintenance**: Active, backed by Kiel University research group
- **Used by**: Mermaid (optional renderer), many industrial tools
- **Pros**: Best edge routing (orthogonal, polyline, splines), compound/nested node support, highly configurable, handles complex DAGs better than dagre
- **Cons**: Large bundle, complex configuration API (Java-isms), slower than dagre
- **Best for**: Complex DAGs with 50–200+ nodes, cross-edges, nested groups

### 4.3 D3-Hierarchy

- **Algorithm**: Tidy tree, treemap, partition, pack
- **Bundle**: ~15KB gzipped
- **Pros**: Tiny, fast, beautiful tree layouts
- **Cons**: Requires single root node, assumes uniform node sizes, tree-only (not general DAG)
- **Best for**: Strictly tree-shaped data only

### 4.4 d3-dag (Sugiyama, Zherebko, Grid)

- **Algorithm**: Full Sugiyama with multiple options for each phase
- **Bundle**: ~30KB gzipped
- **Maintenance**: Light maintenance mode
- **Pros**: Most mathematically rigorous Sugiyama implementation in JS, minimizes edge crossings
- **Cons**: Light maintenance, API learning curve, no React integration
- **Best for**: When layout quality matters more than ease of use

### Recommendation

**Start with dagre** → it's the simplest, fastest, and works well for the Agent Builder's relatively simple dependency graph (agents reference commands, commands reference agents, hooks fire for events — mostly tree-like with some cross-edges).

**Upgrade to ELK.js** if/when:
- Edge routing through nodes becomes a problem
- Nested grouping is needed (e.g., show agents grouped by team or config layer)
- The graph becomes more complex with many cross-layer edges

---

## 5. Existing DAG UIs — Lessons Learned

### 5.1 dbt Cloud Lineage Graph
- **Technology**: Cytoscape.js with dagre layout
- **Design**: Horizontal left-to-right flow, models as rounded rectangles, color-coded by type (model, source, test)
- **Interaction**: Click to select, double-click to navigate, shift-click for multi-select, search and filter by tag/type
- **Lesson**: Type-based color coding and filtering are essential for DAGs with mixed node types

### 5.2 Apache Airflow DAG View
- **Technology**: React-based (Airflow 3), previously Grid/Tree view
- **Design**: Top-to-bottom task dependency graph, tasks colored by status (success/running/failed)
- **Interaction**: Click task for details sidebar, zoom/pan, filter by status
- **Lesson**: Real-time status coloring on nodes provides immediate operational context

### 5.3 Nx Project Graph
- **Technology**: Cytoscape.js with React wrapper
- **Design**: Force-directed layout with grouping by project type (app, lib, e2e)
- **Interaction**: Click to focus, trace dependencies, filter by affected/project type
- **Lesson**: The ability to trace dependency chains (forward and reverse) is highly valuable

### 5.4 GitHub Actions Workflow Visualization
- **Technology**: Custom implementation
- **Design**: Left-to-right job dependency graph with status indicators
- **Interaction**: Click job to expand steps, real-time status updates
- **Lesson**: Compact node design with expandable details keeps the overview clean

### 5.5 Terraform Graph
- **Technology**: Graphviz (DOT format) for CLI, various web tools for visualization
- **Design**: Resource dependency graph
- **Lesson**: CLI export in DOT format is valuable for CI/CD integration and documentation

### Key Takeaways for Agent Builder

1. **Node type differentiation**: Use distinct shapes/colors/icons for agents, commands, hooks, MCP servers
2. **Dependency tracing**: Show "what depends on X" and "what does X depend on"
3. **Filter by type**: Toggle visibility of node types to reduce visual noise
4. **Click-to-navigate**: Clicking a node should open its definition in the editor (#57)
5. **Status indicators**: Show validation status (valid/warning/error) on each node
6. **Compact + expandable**: Show minimal info by default, expand on click/hover

---

## 6. Architecture Recommendation

### Rendering Layer: React Flow

```
@xyflow/react          # Core library (~40KB gz)
  ├── Custom node types (AgentNode, CommandNode, HookNode, MCPNode)
  ├── Custom edge types (DependsOn, Fires, References)
  ├── MiniMap component
  ├── Controls component (zoom, fit, export)
  └── Panel component (filters, legend)
```

### Layout Layer: dagre → ELK.js upgrade path

```
Phase 1 (MVP):
  @dagrejs/dagre       # Simple hierarchical layout (~40KB gz)

Phase 2 (if needed):
  elkjs                 # Advanced layout with edge routing (~1.5MB gz)
```

### Export Layer

```
CLI output:
  mermaid               # Text-based DAG (graph TD / flowchart LR)
  graphviz DOT format   # For external tool consumption

Web export:
  html-to-image / dom-to-svg   # PNG/SVG screenshot of current view
```

### Integration with Agent Builder

```
agent-builder/
  components/
    DependencyGraph.tsx       # Main React Flow canvas
    nodes/
      AgentNode.tsx           # Agent definition node
      CommandNode.tsx         # Slash command node
      HookNode.tsx            # Lifecycle hook node
      MCPServerNode.tsx       # MCP server node
    edges/
      DependencyEdge.tsx      # "depends on" edge with label
      FiresEdge.tsx           # "fires" edge for hooks
    controls/
      GraphFilters.tsx        # Filter by node type, status
      GraphLegend.tsx         # Color/icon legend
      GraphToolbar.tsx        # Export, layout direction, zoom
  hooks/
    useAgentGraph.ts          # Build graph data from agent definitions
    useGraphLayout.ts         # Run dagre/ELK layout
  utils/
    graph-builder.ts          # Transform agent config → React Flow nodes/edges
    layout.ts                 # dagre/ELK layout wrapper
```

---

## 7. Final Comparison: Why React Flow Wins

| Requirement (from #60) | React Flow | Cytoscape | D3 + d3-dag | G6 |
|---|---|---|---|---|
| Rich interactive node content | **Yes (React components)** | No (Canvas) | Partial (SVG) | Yes (v5, newer) |
| Click node → navigate to definition | **Native React onClick** | Canvas hit test | SVG event | Event system |
| Hover for details | **React tooltip/popover** | Canvas tooltip | SVG title | Custom tooltip |
| Zoom/Pan | **Built-in** | Built-in | DIY | Built-in |
| Minimap | **Built-in component** | Extension | No | Plugin |
| Keyboard accessibility | **Built-in (Tab, Enter, arrows)** | No | No | No |
| Screen reader support | **Built-in (ARIA)** | No | No | No |
| shadcn/ui integration | **Native (DOM nodes)** | No | Partial | Partial (v5) |
| Export PNG/SVG | Via library | Via Canvas | Native SVG | Via Canvas |
| Bundle size | ~40KB + layout | ~170KB | ~30KB | ~300KB |
| React ecosystem fit | **Designed for React** | Imperative wrapper | Fights React | Ant ecosystem |
| Community & docs | **Excellent (35K stars)** | Good (10K stars) | Small | Growing (12K) |

---

## 8. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Dagre layout quality insufficient for complex graphs | Medium | Low | ELK.js is a drop-in layout replacement; React Flow examples show both |
| React Flow performance at 200 nodes | Low | Low | DOM rendering handles 200 nodes easily; library virtualizes off-screen nodes |
| html-to-image export issues | Medium | Low | Use dom-to-svg or server-side Puppeteer rendering as fallback |
| dagre package unmaintained | Low | Low | @dagrejs/dagre fork exists; ELK.js is the long-term upgrade |
| ELK.js bundle size (1.5MB) if needed | Medium | Low | Code-split ELK.js; load only when user requests advanced layout |
| Accessibility coverage gaps | Low | Medium | React Flow's ARIA support is the best available; supplement with custom labels |

---

## 9. Sources

### Library Documentation
- [React Flow (xyflow)](https://reactflow.dev/) — Official docs, examples, API reference
- [React Flow Layout Overview](https://reactflow.dev/learn/layouting/layouting) — Layout engine comparison
- [React Flow Accessibility](https://reactflow.dev/learn/advanced-use/accessibility) — ARIA, keyboard, screen reader support
- [React Flow ELK.js Example](https://reactflow.dev/examples/layout/elkjs) — ELK integration example
- [xyflow GitHub](https://github.com/xyflow/xyflow) — Source, 35.6K stars, MIT license

### Alternative Libraries
- [Cytoscape.js](https://js.cytoscape.org/) — Graph theory library, dagre plugin
- [Cytoscape.js Dagre Plugin](https://github.com/cytoscape/cytoscape.js-dagre) — DAG layout for Cytoscape
- [d3-dag](https://github.com/erikbrinkman/d3-dag) — DAG layout algorithms (Sugiyama, Zherebko)
- [G6 (AntV)](https://g6.antv.antgroup.com/en) — Feature-rich graph visualization
- [vis-network](https://github.com/visjs/vis-network) — Interactive network graphs
- [Sigma.js](https://www.sigmajs.org/) — WebGL graph renderer for large graphs
- [Mermaid.js](https://mermaid.js.org/) — Diagram-as-code
- [reagraph](https://reagraph.dev/) — WebGL graphs for React (2D/3D)

### Layout Algorithms
- [dagre](https://github.com/dagrejs/dagre) — Directed graph layout (original, unmaintained)
- [@dagrejs/dagre](https://www.npmjs.com/package/@dagrejs/dagre) — Updated fork
- [ELK.js (kieler/elkjs)](https://github.com/kieler/elkjs) — Eclipse Layout Kernel in JS
- [Mermaid dagre→ELK migration](https://github.com/mermaid-js/mermaid/issues/1969) — ELK adoption context

### Real-World DAG UIs
- [dbt Graph Visualization (DeepWiki)](https://deepwiki.com/dbt-labs/dbt-docs/3.4-graph-visualization) — dbt uses Cytoscape.js
- [Nx Graph (@nx/graph)](https://www.npmjs.com/package/@nx/graph) — Nx uses Cytoscape.js
- [Airflow UI](https://airflow.apache.org/docs/apache-airflow/stable/ui.html) — Airflow 3 React-based
- [Reaflow](https://github.com/reaviz/reaflow) — React workflow editor

### Comparisons
- [npm trends: graph libraries](https://npmtrends.com/@antv/g6-vs-cytoscape-vs-graphdracula-vs-sigma-vs-vis) — Download comparison
- [Ranking of JS Graph Vis Libraries](https://mingyizhao.medium.com/background-b553fda47349) — Community analysis
- [D3 vs Cytoscape discussion](https://groups.google.com/g/cytoscape-discuss/c/Ny8_1HuT0vo) — Technical comparison
