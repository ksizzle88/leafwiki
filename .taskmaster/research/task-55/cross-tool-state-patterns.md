# Cross-Tool Data Flow & Shared State Patterns

**Research for**: Dev Toolkit (Epic #55, Core Framework #56)
**Date**: 2026-03-13
**Focus**: How 4-5 tools (plugins) share data, communicate, and navigate between each other

---

## Table of Contents

1. [Communication Pattern Taxonomy](#1-communication-pattern-taxonomy)
2. [Shared Data Store Patterns](#2-shared-data-store-patterns)
3. [Event Bus / Pub-Sub Patterns](#3-event-bus--pub-sub-patterns)
4. [URL-Based Deep Linking & Cross-Tool Navigation](#4-url-based-deep-linking--cross-tool-navigation)
5. [Context Menus & Selection-Based Actions](#5-context-menus--selection-based-actions)
6. [Shared Services (Backend)](#6-shared-services-backend)
7. [Real-Time Updates (Server → Client)](#7-real-time-updates-server--client)
8. [Data Flow Diagram](#8-data-flow-diagram)
9. [Pattern Comparison Matrix](#9-pattern-comparison-matrix)
10. [Recommended Architecture](#10-recommended-architecture)
11. [Use Case Walkthroughs](#11-use-case-walkthroughs)

---

## 1. Communication Pattern Taxonomy

Cross-tool communication in multi-plugin applications falls into five distinct categories, each with different coupling, latency, and complexity characteristics:

| Pattern | Direction | Coupling | Latency | Best For |
|---------|-----------|----------|---------|----------|
| **Shared Store** | Read/write by all | Medium (shared schema) | Instant (in-memory) | Global UI state, selection context, user preferences |
| **Event Bus** | Pub/sub, many-to-many | Low (event contract only) | Instant (synchronous) | Cross-tool notifications, state change broadcasts |
| **URL Deep Linking** | One-way (trigger navigation) | Very low (URL string only) | User-initiated | Tool-to-tool navigation with context |
| **Shared Services** | Request/response | Medium (service API) | Varies (I/O bound) | File index, search, file watching, settings |
| **Server-Sent Events** | Server → all clients | Low (event stream) | Near real-time | File system changes, background task progress |

### Precedent Systems Studied

| System | Communication Model | Key Mechanism |
|--------|-------------------|---------------|
| **Backstage** | Plugin isolation + route refs + utility APIs | Plugins never call each other directly; communicate via shared utility APIs and opaque route references. External route refs enable cross-plugin navigation without hardcoded paths. |
| **VS Code** | Extensions isolated + API surface | Extensions cannot access each other's `globalState`. Must expose explicit APIs via `vscode.extensions.getExtension().exports` for inter-extension communication. |
| **Grafana** | Plugin types (data source / panel / app) | Panels consume data sources via Grafana's query system. App plugins compose panel + data source plugins. No direct plugin-to-plugin communication. |
| **Micro-frontends** | Event bus + shared store + URL routing | Module Federation exposes shared stores as singletons. Custom events or dedicated event buses handle cross-micro-frontend messaging. BroadcastChannel for multi-tab. |

**Key Insight**: Every mature plugin system maintains strict isolation between plugins and routes communication through well-defined intermediaries (event buses, shared services, route references). No system allows plugins to import each other's code directly.

---

## 2. Shared Data Store Patterns

### 2.1 Zustand (Recommended for Dev Toolkit Frontend)

Zustand is a lightweight (~1KB), hook-based state management library that requires no providers or context wrappers. It's ideal for a plugin-based architecture because:

- **No Provider wrapping**: Stores are module-level singletons, accessible from any component without nesting providers
- **Selective subscriptions**: Components only re-render when their subscribed slice changes
- **Middleware**: Supports persistence (localStorage), devtools, immer for immutable updates
- **Framework-agnostic core**: Can be used outside React (in services, event handlers)

**Pattern for the Dev Toolkit:**

```typescript
// stores/toolkit-store.ts — Shared global state
import { create } from 'zustand';

interface ToolkitState {
  // Active tool / navigation
  activeTool: string;
  
  // Selection context (cross-tool)
  selectedFilePath: string | null;
  selectedEntityId: string | null;
  
  // Search
  globalSearchQuery: string;
  globalSearchResults: SearchResult[];
  
  // Actions
  selectFile: (path: string) => void;
  selectEntity: (id: string) => void;
  setSearchQuery: (query: string) => void;
}

export const useToolkitStore = create<ToolkitState>((set) => ({
  activeTool: 'markdown-browser',
  selectedFilePath: null,
  selectedEntityId: null,
  globalSearchQuery: '',
  globalSearchResults: [],
  
  selectFile: (path) => set({ selectedFilePath: path }),
  selectEntity: (id) => set({ selectedEntityId: id }),
  setSearchQuery: (query) => set({ globalSearchQuery: query }),
}));
```

**Why Not Redux**: Redux's boilerplate (actions, reducers, dispatch) is overkill for 4-5 plugins sharing a handful of state values. Zustand provides the same global store pattern with 90% less ceremony.

**Why Not React Context**: Context causes re-renders in all consumers when any value changes. Zustand's selector-based subscriptions are more performant for cross-tool state where plugins only care about specific slices.

### 2.2 What Should Live in the Shared Store

Not everything belongs in a shared store. The principle: **shared store is for UI coordination state, not data**.

| In the Shared Store | NOT in the Shared Store |
|---------------------|------------------------|
| Currently selected file path | File contents (fetch from API) |
| Currently selected entity ID | Entity data (fetch from API) |
| Global search query | Search index (backend service) |
| Active tool name | Tool-specific internal state |
| Sidebar collapsed/expanded | Plugin health status (API) |
| User preferences (theme, layout) | Cached API responses (React Query) |

### 2.3 Per-Plugin Local State

Each plugin maintains its own internal state independently. For example, the Markdown Browser's scroll position, open tabs, and editor state are local to that plugin's component tree — not shared globally. Use `useState`, `useReducer`, or a plugin-scoped Zustand store for this.

```typescript
// plugins/markdown-browser/stores/editor-store.ts
// This is PRIVATE to the markdown browser plugin
export const useEditorStore = create<EditorState>((set) => ({
  openTabs: [],
  activeTab: null,
  scrollPosition: 0,
  // ... markdown-browser-specific state
}));
```

---

## 3. Event Bus / Pub-Sub Patterns

### 3.1 When to Use Events vs. Shared Store

| Use Events When | Use Shared Store When |
|-----------------|----------------------|
| One-time notification ("file changed") | Persistent state ("selected file is X") |
| Multiple consumers may or may not care | All tools need to read the same value |
| Action/command pattern ("open file in editor") | Derived state ("search results for query") |
| Cross-boundary communication (server → client) | UI synchronization (sidebar ↔ main panel) |

### 3.2 TypeScript Event Bus Implementation

For the Dev Toolkit, a typed event bus provides decoupled communication between plugins without them importing each other:

```typescript
// lib/event-bus.ts
type EventMap = {
  'file:selected': { path: string; source: string };
  'file:changed': { path: string; type: 'create' | 'modify' | 'delete' };
  'entity:selected': { id: string; type: string; source: string };
  'tool:navigate': { toolId: string; params?: Record<string, string> };
  'search:execute': { query: string };
  'context:action': { action: string; payload: unknown };
};

type EventCallback<K extends keyof EventMap> = (data: EventMap[K]) => void;

class ToolkitEventBus {
  private listeners = new Map<string, Set<Function>>();

  on<K extends keyof EventMap>(event: K, callback: EventCallback<K>): () => void {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, new Set());
    }
    this.listeners.get(event)!.add(callback);
    
    // Return unsubscribe function
    return () => {
      this.listeners.get(event)?.delete(callback);
    };
  }

  emit<K extends keyof EventMap>(event: K, data: EventMap[K]): void {
    this.listeners.get(event)?.forEach(cb => cb(data));
  }
}

// Singleton — importable by any plugin
export const eventBus = new ToolkitEventBus();
```

**Key design decisions:**
- **Typed event map**: Compile-time safety for event names and payloads. Adding a new event type is a single interface addition.
- **Singleton module export**: Not a class you instantiate — import `eventBus` from anywhere.
- **Unsubscribe via return value**: Following the React hooks cleanup pattern. Easy to use in `useEffect`.
- **`source` field in events**: Prevents infinite loops where Tool A emits → Tool B handles → emits → Tool A handles. Each handler can check `if (data.source === myPluginId) return`.

### 3.3 React Hook for Event Bus

```typescript
// hooks/useEventBus.ts
import { useEffect } from 'react';
import { eventBus, EventMap } from '../lib/event-bus';

export function useEventBus<K extends keyof EventMap>(
  event: K,
  handler: (data: EventMap[K]) => void,
  deps: React.DependencyList = []
) {
  useEffect(() => {
    const unsubscribe = eventBus.on(event, handler);
    return unsubscribe;
  }, [event, ...deps]);
}
```

Usage in a plugin:

```typescript
// plugins/agent-builder/components/AgentBuilder.tsx
function AgentBuilder() {
  const navigate = useNavigate();

  // Listen for file selections from other tools
  useEventBus('file:selected', ({ path, source }) => {
    if (source === 'agent-builder') return; // Ignore our own events
    if (path.endsWith('.md') && path.includes('agents/')) {
      // Auto-navigate to this agent definition
      navigate(`/agents?file=${encodeURIComponent(path)}`);
    }
  });
  
  // ...
}
```

### 3.4 Event Bus vs. Custom DOM Events

An alternative is using the browser's native `CustomEvent` API on `window`:

```typescript
// Emit
window.dispatchEvent(new CustomEvent('toolkit:file-selected', { 
  detail: { path: '/agents/researcher.md' }
}));

// Listen
window.addEventListener('toolkit:file-selected', (e: CustomEvent) => {
  console.log(e.detail.path);
});
```

**Tradeoffs:**

| Aspect | Custom EventBus class | CustomEvent on window |
|--------|----------------------|----------------------|
| Type safety | Strong (generic EventMap) | Weak (must cast `e.detail`) |
| Namespace collisions | Impossible (typed keys) | Possible (string events) |
| SSR compatibility | Works (no DOM needed) | Requires `window` |
| Debugging | Custom logging middleware | Browser DevTools event listener |
| Memory leaks | Explicit unsubscribe | Must `removeEventListener` |

**Recommendation**: Use the custom TypeScript EventBus class. The type safety alone is worth it for a multi-plugin system where event contracts matter.

---

## 4. URL-Based Deep Linking & Cross-Tool Navigation

### 4.1 The Backstage Route Reference Pattern

Backstage solves cross-plugin navigation elegantly with **route references** — opaque tokens that plugins use to link to each other without knowing concrete URL paths:

1. **Plugin A** declares a route ref: `createRouteRef()` → assigned to a page at path `/agents`
2. **Plugin B** declares an external route ref: `createExternalRouteRef()` for "where to navigate when user clicks an agent link"
3. **App shell** binds them: `bind(markdownBrowser.externalRoutes.agentDetails, agentBuilder.routes.details)`
4. **Plugin B** uses `useRouteRef(agentDetailsRouteRef)` to get a function that returns the concrete URL

This level of indirection is powerful for large platforms where plugins are independently versioned and deployed. For the Dev Toolkit with 4-5 co-located plugins, it is **overkill**.

### 4.2 Recommended: Simple URL Routing with Context Parameters

For the Dev Toolkit, each plugin owns a URL prefix. Cross-tool navigation is simply a link to the other tool's URL with query parameters carrying context:

```
Markdown Browser → Agent Builder:
  /agents?file=/workspace/.claude/agents/researcher.md

Agent Builder → Markdown Browser:
  /markdown?file=/workspace/.claude/CLAUDE.md&line=45

jtbl → Markdown Browser:
  /markdown?file=/tmp/export.md

Permissions Gateway → Agent Builder:
  /agents?entity=researcher&tab=permissions
```

### 4.3 Navigation Helper

```typescript
// lib/navigation.ts
const TOOL_PATHS = {
  'markdown-browser': '/markdown',
  'json-table': '/json',
  'agent-builder': '/agents',
  'permissions-gateway': '/gateway',
} as const;

type ToolId = keyof typeof TOOL_PATHS;

export function navigateToTool(
  toolId: ToolId,
  params?: Record<string, string>
): string {
  const base = TOOL_PATHS[toolId];
  if (!params || Object.keys(params).length === 0) return base;
  const query = new URLSearchParams(params).toString();
  return `${base}?${query}`;
}

// Usage:
// navigateToTool('agent-builder', { file: '/workspace/.claude/agents/researcher.md' })
// → '/agents?file=%2Fworkspace%2F.claude%2Fagents%2Fresearcher.md'
```

### 4.4 Router Integration

The shell app reads URL parameters and passes them as props to the active plugin:

```typescript
// In the shell's router
<Route path="/agents" element={
  <ErrorBoundary>
    <Suspense fallback={<Loading />}>
      <AgentBuilder />
    </Suspense>
  </ErrorBoundary>
} />
```

The plugin reads its parameters from the URL:

```typescript
// plugins/agent-builder/components/AgentBuilder.tsx
function AgentBuilder() {
  const [searchParams] = useSearchParams();
  const initialFile = searchParams.get('file');
  const initialTab = searchParams.get('tab');
  
  useEffect(() => {
    if (initialFile) {
      loadAgentFile(initialFile);
    }
  }, [initialFile]);
  
  // ...
}
```

### 4.5 Why Not Path-Based Routing (e.g., `/agents/file/path/to/agent.md`)

Path-based routing encodes the context in the URL path instead of query parameters. This looks cleaner but creates problems:
- File paths contain `/` which collides with route segments
- Requires catch-all route patterns (`/agents/*`) and manual parsing
- Query parameters are the standard mechanism for passing context to a page
- Search engines and bookmarks handle query params well

**Stick with query parameters for cross-tool context.**

---

## 5. Context Menus & Selection-Based Actions

### 5.1 Cross-Tool Context Actions

A powerful UX pattern: right-clicking (or clicking a dropdown) on an item in one tool reveals actions that open other tools with context.

**Examples:**
- In Markdown Browser, right-click an agent `.md` file → "Open in Agent Builder"
- In jtbl, right-click a cell containing a file path → "View in Markdown Browser"
- In Agent Builder, right-click a dependency node → "View CLAUDE.md"
- In Permissions Gateway, right-click an agent → "Edit in Agent Builder"

### 5.2 Action Registry Pattern

Rather than tools hardcoding knowledge of other tools, a registry allows plugins to contribute actions that appear in other plugins' context menus:

```typescript
// lib/action-registry.ts
interface ContextAction {
  id: string;
  label: string;
  icon?: string;
  pluginId: string;
  
  // When should this action appear?
  appliesTo: (context: SelectionContext) => boolean;
  
  // What happens when clicked?
  execute: (context: SelectionContext) => void;
}

interface SelectionContext {
  type: 'file' | 'entity' | 'cell' | 'node';
  value: string;
  metadata?: Record<string, unknown>;
}

class ActionRegistry {
  private actions: ContextAction[] = [];

  register(action: ContextAction): void {
    this.actions.push(action);
  }

  getActionsFor(context: SelectionContext): ContextAction[] {
    return this.actions.filter(a => a.appliesTo(context));
  }
}

export const actionRegistry = new ActionRegistry();
```

**Plugin registration example:**

```typescript
// plugins/agent-builder/index.ts (during plugin init)
actionRegistry.register({
  id: 'open-in-agent-builder',
  label: 'Open in Agent Builder',
  icon: 'bot',
  pluginId: 'agent-builder',
  appliesTo: (ctx) => {
    return ctx.type === 'file' && 
           ctx.value.endsWith('.md') && 
           ctx.value.includes('agents/');
  },
  execute: (ctx) => {
    window.location.href = navigateToTool('agent-builder', { file: ctx.value });
  },
});
```

### 5.3 Shared Context Menu Component

```typescript
// components/ContextMenu.tsx
function ContextMenu({ context, position }: Props) {
  const actions = actionRegistry.getActionsFor(context);
  
  if (actions.length === 0) return null;
  
  return (
    <div style={{ top: position.y, left: position.x }} className="context-menu">
      {actions.map(action => (
        <button key={action.id} onClick={() => action.execute(context)}>
          <Icon name={action.icon} />
          {action.label}
        </button>
      ))}
    </div>
  );
}
```

This pattern mirrors VS Code's `contributes.menus` system where extensions declare which commands appear in which menus, but simplified for our 4-5 plugin scope.

---

## 6. Shared Services (Backend)

### 6.1 Services That Multiple Plugins Need

| Service | Consumers | Purpose |
|---------|-----------|---------|
| **File Index** | Markdown Browser, Agent Builder | List and categorize all `.md`, `.json`, agent definition files in workspace |
| **File Watcher** | All tools | Push notifications when files change (create/modify/delete) |
| **Search** | All tools (global search bar) | Full-text search across markdown files, JSON data, agent definitions |
| **Settings** | All tools | Toolkit-wide preferences (theme, default file paths, editor config) |
| **File Reader** | Markdown Browser, Agent Builder, jtbl | Read and parse files with caching |

### 6.2 Backend Service Architecture

**Note on stack tension**: The existing research has two competing recommendations — FastAPI (Python) from the web framework comparison, and Fastify (Node) from the plugin architecture research. The shared service patterns described here apply to both, with implementation differences noted.

#### Fastify Decorator Pattern (Node.js)

Fastify's decorator pattern provides the cleanest shared service model for a plugin-based backend. Services registered at the root scope with `fastify-plugin` are inherited by all plugin scopes:

```typescript
// services/file-index.ts
import fp from 'fastify-plugin';

async function fileIndexPlugin(fastify: FastifyInstance) {
  const index = new FileIndex('/workspace');
  await index.build();
  
  // Decorate the Fastify instance — all plugins can access this
  fastify.decorate('fileIndex', index);
  
  // Clean up on shutdown
  fastify.addHook('onClose', async () => {
    await index.dispose();
  });
}

// fp() breaks encapsulation so ALL plugins get access
export default fp(fileIndexPlugin, { name: 'file-index' });
```

Plugins access the service via the Fastify instance:

```typescript
// plugins/markdown-browser/routes.ts
async function markdownRoutes(fastify: FastifyInstance) {
  fastify.get('/api/markdown/files', async (req, reply) => {
    const files = fastify.fileIndex.listByExtension('.md');
    return files;
  });
}
```

#### FastAPI Dependency Injection Pattern (Python)

FastAPI uses `Depends()` for the same pattern. Shared services are singletons injected via the DI system:

```python
# services/file_index.py
from functools import lru_cache

class FileIndex:
    def __init__(self, root: str):
        self.root = root
        self._build()
    
    def list_by_extension(self, ext: str) -> list[str]:
        ...

@lru_cache
def get_file_index() -> FileIndex:
    return FileIndex("/workspace")

# plugins/markdown_browser/routes.py
from fastapi import APIRouter, Depends

router = APIRouter(prefix="/api/markdown")

@router.get("/files")
async def list_files(index: FileIndex = Depends(get_file_index)):
    return index.list_by_extension(".md")
```

**Limitation**: FastAPI's `Depends()` does not propagate across `app.mount()` sub-application boundaries. Mounted sub-apps get their own DI scope. Workarounds:
1. Use module-level singletons (like `@lru_cache` above) instead of FastAPI's DI
2. Use the `dependency-injector` library for a proper DI container
3. Pass shared services as constructor arguments when creating sub-app routers

### 6.3 File Watcher as Shared Service

The file watcher is the most important shared service because multiple plugins need real-time file change notifications. Based on the existing file-watching-strategies research, chokidar v5 (or `@parcel/watcher` for native performance) should be used as a singleton:

```typescript
// services/file-watcher.ts
import fp from 'fastify-plugin';
import chokidar from 'chokidar';

async function fileWatcherPlugin(fastify: FastifyInstance) {
  const watcher = chokidar.watch('/workspace', {
    ignored: ['**/node_modules/**', '**/.git/**', '**/.*'],
    persistent: true,
    ignoreInitial: true,
  });
  
  // Internal event bus for server-side consumers
  watcher.on('all', (event, path) => {
    fastify.eventBus.emit('file:changed', { 
      path, 
      type: event as 'add' | 'change' | 'unlink',
    });
  });
  
  fastify.decorate('fileWatcher', watcher);
  fastify.addHook('onClose', async () => watcher.close());
}

export default fp(fileWatcherPlugin, { 
  name: 'file-watcher',
  dependencies: ['event-bus'],
});
```

### 6.4 Search Service

A shared search service indexes content from all plugin domains:

```typescript
// services/search.ts
interface SearchResult {
  path: string;
  type: 'markdown' | 'json' | 'agent' | 'config';
  title: string;
  snippet: string;
  line?: number;
  score: number;
}

class SearchService {
  private providers: SearchProvider[] = [];

  // Plugins register search providers during init
  registerProvider(provider: SearchProvider): void {
    this.providers.push(provider);
  }

  async search(query: string): Promise<SearchResult[]> {
    const results = await Promise.all(
      this.providers.map(p => p.search(query))
    );
    return results
      .flat()
      .sort((a, b) => b.score - a.score);
  }
}

interface SearchProvider {
  type: string;
  search(query: string): Promise<SearchResult[]>;
}
```

Each plugin registers its own search provider:

```typescript
// plugins/markdown-browser/index.ts (during onInit)
ctx.searchService.registerProvider({
  type: 'markdown',
  async search(query) {
    // Use ripgrep or a text index to search .md files
    return searchMarkdownFiles(query);
  },
});
```

This is analogous to VS Code's Search Providers API where extensions contribute results to the unified search experience.

---

## 7. Real-Time Updates (Server → Client)

### 7.1 Server-Sent Events (SSE) vs. WebSocket

For pushing file change notifications from the server to the browser:

| Aspect | SSE | WebSocket |
|--------|-----|-----------|
| Direction | Server → Client only | Bidirectional |
| Protocol | HTTP (works through proxies, CDNs) | Custom protocol (ws://) |
| Reconnection | Built-in auto-reconnect | Must implement manually |
| Browser support | Native `EventSource` API | Native `WebSocket` API |
| Complexity | Very low | Medium |
| When to use | File changes, notifications, progress | Chat, collaborative editing, gaming |

**Recommendation: SSE for the Dev Toolkit.** File system change notifications are strictly server-to-client. SSE is simpler, auto-reconnects, and works through all HTTP proxies (important in devcontainer port forwarding). WebSocket is only needed if we later add collaborative editing features.

### 7.2 SSE Implementation

**Backend (Fastify/Node):**

```typescript
// routes/events.ts
fastify.get('/api/events', async (request, reply) => {
  reply.raw.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
  });

  const handler = (data: FileChangeEvent) => {
    reply.raw.write(`event: file-change\n`);
    reply.raw.write(`data: ${JSON.stringify(data)}\n\n`);
  };

  fastify.eventBus.on('file:changed', handler);

  request.raw.on('close', () => {
    fastify.eventBus.off('file:changed', handler);
  });
});
```

**Backend (FastAPI/Python):**

```python
from sse_starlette.sse import EventSourceResponse

@app.get("/api/events")
async def event_stream():
    async def generate():
        async for event in file_watcher.events():
            yield {
                "event": "file-change",
                "data": json.dumps(event),
            }
    return EventSourceResponse(generate())
```

**Frontend:**

```typescript
// hooks/useServerEvents.ts
export function useServerEvents() {
  const queryClient = useQueryClient(); // If using React Query

  useEffect(() => {
    const source = new EventSource('/api/events');

    source.addEventListener('file-change', (e) => {
      const data = JSON.parse(e.data);
      
      // Update the shared store
      useToolkitStore.getState().handleFileChange(data);
      
      // Emit on the client event bus for plugin-specific handling
      eventBus.emit('file:changed', data);
      
      // Invalidate any React Query caches for affected paths
      queryClient.invalidateQueries({ queryKey: ['file', data.path] });
    });

    return () => source.close();
  }, []);
}
```

### 7.3 Event Flow: File Change → UI Update

```
1. User edits a file in VS Code terminal
   ↓
2. chokidar detects inotify event on /workspace
   ↓
3. File watcher service emits 'file:changed' on server event bus
   ↓
4. SSE endpoint pushes event to all connected browser clients
   ↓
5. Client receives SSE event, dispatches to:
   a. Shared Zustand store (updates selectedFile metadata if affected)
   b. Client event bus (plugins can react independently)
   c. React Query cache invalidation (stale data refetched)
   ↓
6. Markdown Browser: re-renders if viewing the changed file
   Agent Builder: refreshes dependency graph if an agent file changed
   jtbl: no-op (JSON data is loaded on demand)
   Permissions Gateway: refreshes if an action file appeared/disappeared
```

---

## 8. Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        BROWSER (SPA)                            │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐     │
│  │                   Shell (Router)                        │     │
│  │  ┌──────────┐  ┌──────────┐  ┌───────────────────┐    │     │
│  │  │ Sidebar  │  │ Search   │  │ Breadcrumb / Nav   │    │     │
│  │  │  Nav     │  │  Bar     │  │                    │    │     │
│  │  └──────────┘  └──────────┘  └───────────────────┘    │     │
│  └────────────────────────────────────────────────────────┘     │
│                             │                                    │
│  ┌──────────────────────────┼────────────────────────────┐      │
│  │       Shared Layer       │                             │      │
│  │  ┌──────────────┐  ┌────┴──────┐  ┌──────────────┐   │      │
│  │  │ Zustand      │  │ Event     │  │ Action        │   │      │
│  │  │ Store        │  │ Bus       │  │ Registry      │   │      │
│  │  │ (UI state)   │  │ (pub/sub) │  │ (ctx menus)   │   │      │
│  │  └──────────────┘  └───────────┘  └──────────────┘   │      │
│  └───────────────────────────────────────────────────────┘      │
│                             │                                    │
│  ┌──────────┐ ┌──────────┐ │ ┌──────────┐ ┌──────────────┐     │
│  │ Markdown │ │  jtbl    │ │ │ Agent    │ │ Permissions   │     │
│  │ Browser  │ │  2.0     │ │ │ Builder  │ │ Gateway       │     │
│  │          │ │          │ │ │          │ │               │     │
│  └────┬─────┘ └────┬─────┘ │ └────┬─────┘ └──────┬───────┘     │
│       │             │       │      │              │              │
│  ─────┴─────────────┴───────┴──────┴──────────────┴──────        │
│                    REST API + SSE                                 │
└──────────────────────────────┬──────────────────────────────────┘
                               │ HTTP
┌──────────────────────────────┴──────────────────────────────────┐
│                      SERVER (Fastify / FastAPI)                  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                    Shared Services                          │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │  │
│  │  │ File     │  │ File     │  │ Search   │  │ Settings │  │  │
│  │  │ Index    │  │ Watcher  │  │ Service  │  │ Service  │  │  │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │  │
│  └────────────────────────────────────────────────────────────┘  │
│                             │                                    │
│  ┌──────────┐ ┌──────────┐ │ ┌──────────┐ ┌──────────────┐     │
│  │ /api/    │ │ /api/    │ │ │ /api/    │ │ /api/         │     │
│  │ markdown │ │ json     │ │ │ agents   │ │ gateway       │     │
│  │ routes   │ │ routes   │ │ │ routes   │ │ routes        │     │
│  └──────────┘ └──────────┘ │ └──────────┘ └──────────────┘     │
│                             │                                    │
│  ┌──────────────────────────┴────────────────────────────────┐  │
│  │                   SSE Event Stream                         │  │
│  │                /api/events (file changes, notifications)   │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                    File System                              │  │
│  │                 /workspace (bind mount)                     │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 9. Pattern Comparison Matrix

| Pattern | Complexity | Coupling | Use in Dev Toolkit | Implementation Priority |
|---------|-----------|---------|-------------------|------------------------|
| **Zustand shared store** | Low | Medium | Global UI state, selection context | P0 (required from day 1) |
| **Typed event bus (client)** | Low | Low | Cross-plugin notifications, file changes | P0 (required from day 1) |
| **URL query params** | Very low | Very low | Cross-tool navigation with context | P0 (required from day 1) |
| **SSE from server** | Low-Medium | Low | File change notifications | P0 (required for live reload) |
| **Shared backend services** | Medium | Medium | File index, search, file watcher | P0 (core infrastructure) |
| **Action registry** | Medium | Low | Right-click "Open in..." actions | P1 (nice-to-have, add after MVP) |
| **Global search** | Medium | Medium | Unified search across all tools | P1 (add after individual tools work) |
| **Context menus** | Low-Medium | Low | Cross-tool actions on selection | P1 (add after core navigation works) |

---

## 10. Recommended Architecture

### 10.1 Three-Layer Communication Model

The Dev Toolkit should use a **three-layer communication model** that separates concerns cleanly:

**Layer 1: Shared State (Zustand)**
- What: Global UI coordination state
- Scope: Frontend only
- Examples: Selected file, active tool, sidebar state, user preferences
- Access: Any React component via `useToolkitStore`
- Persistence: Optional localStorage sync for preferences

**Layer 2: Events (Event Bus + SSE)**
- What: Notifications about state changes and actions
- Scope: Client-side event bus + server-to-client SSE
- Examples: File changed, entity selected, tool navigation request
- Access: `eventBus.on()` / `eventBus.emit()` + `EventSource`
- Key rule: Events are fire-and-forget. Handlers must not assume other handlers exist.

**Layer 3: Services (Backend DI)**
- What: Shared data access and operations
- Scope: Backend only (consumed via REST API from frontend)
- Examples: File index, search, file watcher, settings
- Access: Fastify decorators or FastAPI `Depends()`
- Key rule: Services are singletons. Plugins consume, not create.

### 10.2 Rules for Plugin Communication

1. **Plugins NEVER import each other's code.** All cross-plugin communication goes through the shared layer (store, events, URL, services).
2. **Events carry data, not commands.** `file:changed` with path data, not `markdown-browser:refresh`. Let the receiving plugin decide what to do.
3. **URL is the primary cross-tool navigation mechanism.** `navigateToTool('agent-builder', { file: path })`. Deep links are bookmarkable and shareable.
4. **The shared store is thin.** Only coordination state. Plugin-internal state stays plugin-local.
5. **Backend services are singletons registered at startup.** Plugins declare dependencies, framework resolves them.
6. **SSE is the only server→client push channel.** No polling for file changes.

### 10.3 What NOT to Build

- **No custom RPC between plugins**: No `pluginA.call('methodName', args)`. This creates tight coupling.
- **No shared database between plugins**: Each plugin manages its own data. Shared data lives in shared services.
- **No BroadcastChannel / SharedWorker**: These are for multi-tab scenarios. The toolkit is a single-tab SPA.
- **No Redux / MobX / Recoil**: Zustand is sufficient and dramatically simpler for this scale.
- **No Module Federation**: The plugins are co-located in one codebase. Module Federation solves separate-deployment problems we don't have.

---

## 11. Use Case Walkthroughs

### Use Case 1: Markdown Browser → Agent Builder

**User story**: User is browsing `.md` files in the Markdown Browser, sees an agent definition file (`agents/researcher.md`), and wants to view it in the Agent Builder with its dependency graph.

**Flow:**
1. User right-clicks on `agents/researcher.md` in the Markdown Browser's file tree
2. Shell's `<ContextMenu>` calls `actionRegistry.getActionsFor({ type: 'file', value: 'agents/researcher.md' })`
3. Agent Builder's registered action matches (file ends with `.md`, path contains `agents/`)
4. Menu shows "Open in Agent Builder"
5. User clicks → `action.execute()` calls `navigate('/agents?file=agents/researcher.md')`
6. React Router renders the Agent Builder component
7. Agent Builder reads `file` from URL search params, loads and displays the agent

**Communication used**: Action Registry (context menu) + URL navigation (query params)

### Use Case 2: File Changed → Multiple Tools Update

**User story**: User edits `agents/researcher.md` in VS Code's text editor. The Markdown Browser and Agent Builder both update live.

**Flow:**
1. VS Code saves the file → inotify fires
2. Server's chokidar file watcher detects the change
3. Server emits `file:changed` on the internal event bus
4. SSE endpoint pushes `{ event: "file-change", data: { path: "agents/researcher.md", type: "change" } }`
5. Client receives SSE event:
   - Updates Zustand store if this is the currently selected file
   - Emits `file:changed` on client event bus
   - Invalidates React Query cache for this file path
6. Markdown Browser (if viewing this file): Refetches and re-renders the markdown
7. Agent Builder (if this agent is in the current graph): Refreshes the node data

**Communication used**: Server event bus → SSE → Client event bus + Zustand store + React Query invalidation

### Use Case 3: Global Search

**User story**: User types "auth middleware" in the global search bar. Results come from markdown files, agent definitions, and JSON configs.

**Flow:**
1. User types in the search bar (in the shell)
2. Shell calls `GET /api/search?q=auth+middleware`
3. Server's search service fans out to all registered search providers:
   - Markdown provider searches `.md` files (ripgrep or text index)
   - Agent provider searches agent definitions
   - JSON provider searches `.json` files
4. Results merged, scored, deduplicated, and returned
5. Shell displays unified results grouped by type
6. User clicks a result → navigates to the appropriate tool with context:
   - Markdown result → `/markdown?file=docs/auth.md&line=42`
   - Agent result → `/agents?file=agents/auth-agent.md`

**Communication used**: REST API (search endpoint) + URL navigation (result click)

### Use Case 4: jtbl → Markdown Export

**User story**: User has a JSON table open in jtbl, exports it as markdown, and wants to view the rendered output.

**Flow:**
1. User clicks "Export as Markdown" in jtbl
2. jtbl generates a markdown string from the table data
3. jtbl calls `POST /api/markdown/preview` with the markdown content (or writes to a temp file)
4. jtbl navigates to `/markdown?file=/tmp/jtbl-export.md` (or uses an in-memory preview mode)
5. Markdown Browser receives the URL, loads the file, renders it

**Communication used**: REST API (file creation) + URL navigation

### Use Case 5: Permissions Gateway → Agent Builder

**User story**: User is reviewing agent permissions in the Gateway and wants to see the full agent definition for one of them.

**Flow:**
1. User sees agent "researcher" in the permissions list
2. User clicks "View Agent Definition" link
3. Gateway navigates to `/agents?entity=researcher`
4. Agent Builder reads the `entity` param, looks up the file path from the file index service, loads it

**Communication used**: URL navigation with entity identifier

---

## Sources

### Backstage
- [Frontend Routes / Route References](https://backstage.io/docs/frontend-system/architecture/routes/)
- [Frontend Plugins](https://backstage.io/docs/frontend-system/architecture/plugins/)
- [Backend Plugins](https://backstage.io/docs/backend-system/architecture/plugins/)
- [Composability System](https://backstage.io/docs/plugins/composability/)
- [Architecture Overview](https://backstage.io/docs/overview/architecture-overview/)
- [External Route Refs API](https://backstage.io/docs/reference/frontend-plugin-api.createexternalrouteref/)

### VS Code
- [Common Capabilities (Storage API)](https://code.visualstudio.com/api/extension-capabilities/common-capabilities)
- [Cross-Extension Data Sharing Discussion](https://github.com/microsoft/vscode-discussions/discussions/1169)
- [VS Code API Reference](https://code.visualstudio.com/api/references/vscode-api)

### Micro-Frontend Communication
- [Communication Patterns in Microfrontends (Shared Store, Event Bus, Message Bus, BroadcastChannel, Web Workers)](https://medium.com/@mfflik/communication-patterns-in-microfrontends-with-webpack-module-federation-shared-store-event-bus-ae2a1ed031a6)
- [Patterns for Managing Shared State Across Microfrontends](https://medium.com/@rahul.dinkar/patterns-for-managing-shared-state-across-microfrontends-2ae0013022a1)
- [Event Bus for Micro Frontends](https://oskari.io/blog/event-bus-micro-frontend)
- [Micro Frontends in Action — Communication Patterns (Manning)](https://livebook.manning.com/book/micro-frontends-in-action/chapter-6)

### Event Bus
- [How to Implement an Event Bus in TypeScript (This Dot Labs)](https://www.thisdot.co/blog/how-to-implement-an-event-bus-in-typescript)
- [JavaScript Event Bus (Dev.to)](https://dev.to/mohsenfallahnjd/javascript-event-bus-js-typescript-17jp)
- [ts-event-bus — Distributed Messaging in TypeScript](https://github.com/Dashlane/ts-event-bus)
- [ts-bus — Lightweight Event Bus](https://github.com/ryardley/ts-bus)

### State Management
- [Zustand (pmndrs)](https://github.com/pmndrs/zustand)
- [Zustand and React Context (TkDodo)](https://tkdodo.eu/blog/zustand-and-react-context)

### Fastify Shared Services
- [Fastify Decorators](https://fastify.dev/docs/latest/Reference/Decorators/)
- [Fastify Plugin Guide](https://fastify.dev/docs/latest/Guides/Plugins-Guide/)
- [fastify-decorators (DI framework)](https://github.com/L2jLiga/fastify-decorators)

### FastAPI Shared Services
- [FastAPI Dependencies](https://fastapi.tiangolo.com/tutorial/dependencies/)
- [Sub Applications / Mounts](https://docs.w3cub.com/fastapi/advanced/sub-applications/index)
- [Dependency Override Propagation Discussion](https://github.com/fastapi/fastapi/discussions/6252)

### Server-Sent Events
- [FastAPI SSE Tutorial](https://fastapi.tiangolo.com/tutorial/server-sent-events/)
- [SSE with FastAPI (Mahdi Jafari)](https://mahdijafaridev.medium.com/implementing-server-sent-events-sse-with-fastapi-real-time-updates-made-simple-6492f8bfc154)
- [sse-starlette](https://pypi.org/project/sse-starlette/)

### Grafana
- [Plugin Types and Usage](https://grafana.com/developers/plugin-tools/key-concepts/plugin-types-usage)
- [Plugin Management](https://grafana.com/docs/grafana/latest/administration/plugin-management/)

### React Context / DI
- [Dependency Injection in React (Code Driven Development)](https://codedrivendevelopment.com/posts/dependency-injection-in-react)
- [React Context for DI, Not State Management (Test Double)](https://testdouble.com/insights/react-context-for-dependency-injection-not-state-management)
- [DI with Provider Pattern (500Tech)](https://500tech.com/blog/all/dependency-injection-in-react/)

### Context Menus
- [React Flow Context Menu Example](https://reactflow.dev/examples/interaction/context-menu)
- [Custom Context Menu Hook in React](https://www.perpetualny.com/blog/create-a-custom-context-menu-hook-in-react)
