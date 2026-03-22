# Plugin Architecture Patterns for Dev Tools

**Research for**: Dev Toolkit Core Framework (Issue #56, Epic #55)
**Date**: 2026-03-13
**Focus**: Plugin system for 4-5 web-based tools running on localhost

---

## Table of Contents

1. [Convention-Based Plugin Discovery](#1-convention-based-plugin-discovery)
2. [Plugin Interfaces and Contracts](#2-plugin-interfaces-and-contracts)
3. [Plugin Isolation and Crash Protection](#3-plugin-isolation-and-crash-protection)
4. [Plugin Lifecycle Management](#4-plugin-lifecycle-management)
5. [Frontend Plugin Patterns](#5-frontend-plugin-patterns)
6. [Plugin Configuration Declaration](#6-plugin-configuration-declaration)
7. [Comparison Matrix](#7-comparison-matrix)
8. [Recommended Approach](#8-recommended-approach)

---

## 1. Convention-Based Plugin Discovery

### Patterns Studied

#### Filesystem-Based (Nuxt, Gatsby, Fastify Autoload)

**Nuxt** is the purest example of convention-based discovery. Specific directories have automatic meaning:
- `plugins/` — All files auto-registered as Vue plugins
- `server/` — API routes auto-discovered by path
- `composables/` — Auto-imported into components
- Nested directory scanning is configurable via `imports.dirs` in `nuxt.config`

**Gatsby** uses `gatsby-config.js` as a manifest listing plugins by name, but each plugin uses convention files for its lifecycle hooks:
- `gatsby-node.js` — Build-time hooks (`createPages`, `onCreateNode`, `sourceNodes`)
- `gatsby-browser.js` — Client-side hooks (`wrapPageElement`, `onRouteUpdate`)
- `gatsby-ssr.js` — SSR hooks (`wrapRootElement`)

**Fastify Autoload** (`@fastify/autoload`) scans a directory and registers every file as a Fastify plugin:
- Each `.js`/`.ts` file in the directory is treated as a plugin
- Subdirectory names become route prefixes automatically
- `index.js` files in subdirectories act as the entry point (other files in that dir are skipped)
- Configurable: `maxDepth`, `indexPattern`, encapsulation behavior

#### Manifest-Based (VS Code, Grafana)

**VS Code** uses `package.json` with a `contributes` field declaring what the extension provides (commands, views, menus, keybindings, etc.) and an `activationEvents` field declaring when it loads. The manifest is entirely declarative — the runtime only loads extension code when triggered.

**Grafana** uses `plugin.json` declaring metadata (name, type, version, dependencies, supported Grafana versions). The `module.ts` file is the entry point for frontend code, `pkg/plugin/main.go` for backend.

### Analysis

| Approach | Pros | Cons | Best For |
|----------|------|------|----------|
| **Pure filesystem** | Zero config, just drop files | Implicit behavior hard to debug, no metadata | Small apps with simple plugins |
| **Manifest + convention** | Explicit capabilities, still convention-based structure | More boilerplate per plugin | Medium apps with typed contracts |
| **Central registry** | Full control over load order | Requires editing a central file for each plugin | Large apps with complex deps |

### Recommendation for Dev Toolkit

**Hybrid: Filesystem discovery + manifest per plugin.** Each plugin lives in `plugins/<name>/` and must export a manifest object (or have a `plugin.json`). The framework scans the `plugins/` directory, reads each manifest, validates it, and registers the plugin. This gives us:
- Drop-in convenience (create a directory, it's discovered)
- Explicit metadata (routes, nav entry, dependencies are declared, not guessed)
- Validation (bad manifests produce clear error messages)

---

## 2. Plugin Interfaces and Contracts

### Patterns Studied

#### Backstage (Most Relevant)

Backstage has separate frontend and backend plugin systems:

**Frontend plugins** (`createFrontendPlugin`):
- Unique `pluginId` per plugin
- Extensions provide UI components (pages, cards, tabs, nav items)
- Route references (`createRouteRef`, `createSubRouteRef`, `createExternalRouteRef`) enable cross-plugin navigation without hardcoded paths
- Slot-filling architecture: pages define slots, other plugins fill them with component extensions
- `withOverrides` method allows apps to customize plugin behavior

**Backend plugins** (`createBackendPlugin`):
- Extension points expose interfaces modules can implement
- `registerExtensionPoint` in the plugin's `register` callback
- All modules extending a plugin are fully initialized before the plugin itself initializes
- Extension points scoped to their parent plugin — no cross-plugin leaking

#### Fastify (Most Elegant for Backend)

Fastify plugins are plain functions that receive the Fastify instance, options, and a done callback:
- **Encapsulation by default**: Each `register` call creates a new scope (DAG)
- **Decorators** share state: `fastify.decorate('db', connection)` — children inherit, siblings don't see it
- **fastify-plugin** breaks encapsulation intentionally for shared infrastructure
- Routes, hooks, and decorators are all scoped to the plugin context
- Avvio manages the lifecycle ordering automatically

#### Strapi v5

Plugins define a structured server API object:
- `register()` — runs before database/routing init
- `bootstrap()` — runs after all plugins load
- `destroy()` — cleanup on shutdown
- Declares: `routes`, `controllers`, `services`, `policies`, `middlewares`, `contentTypes`
- All components accessible via `strapi.plugin('name').controller('name')` pattern
- Routes have types (`content-api` or `admin`) for scoping

#### Homebridge

Two plugin types: Accessory (static) and Platform (dynamic):
- `DynamicPlatformPlugin` interface with `configureAccessory` method
- `API.registerPlatformAccessories` / `API.unregisterPlatformAccessories` for runtime add/remove
- Accessories persisted to disk, recreated on restart
- Plugin template: `platform.ts` for discovery logic, `platformAccessory.ts` for control logic

#### VS Code

Extensions declare capabilities via `package.json` contributes:
- `activationEvents` define when code loads (lazy by default)
- `contributes` declares static capabilities (commands, views, menus, languages, etc.)
- Runtime API: `vscode.commands.registerCommand`, `vscode.window.createTreeView`, etc.
- Activation model: "when defines what, contributions define what, code defines how"

### Recommended Plugin Interface for Dev Toolkit

```typescript
interface DevToolkitPlugin {
  // Identity
  id: string;                           // Unique plugin identifier
  name: string;                         // Display name
  version: string;                      // Semver
  description?: string;                 // One-liner

  // Dependencies
  dependencies?: string[];              // Plugin IDs this depends on

  // Navigation
  nav: {
    label: string;                      // Sidebar label
    icon: string;                       // Icon identifier
    path: string;                       // URL path prefix (e.g., '/markdown')
    order?: number;                     // Sort order in sidebar
  };

  // Backend
  routes?: (router: Router) => void;    // Register backend routes
  
  // Frontend
  component: () => Promise<Component>;  // Lazy-loaded frontend component
  
  // Lifecycle
  onInit?: (ctx: PluginContext) => Promise<void>;
  onDestroy?: () => Promise<void>;
  
  // Health
  healthCheck?: () => Promise<HealthStatus>;
}
```

This draws from:
- **Strapi**: Lifecycle hooks (`register`/`bootstrap`/`destroy`)
- **Fastify**: Route registration via function receiving router
- **VS Code**: Declarative nav/metadata + imperative code
- **Backstage**: Typed plugin ID for cross-plugin references

---

## 3. Plugin Isolation and Crash Protection

### Patterns Studied

#### Process Isolation (Chrome, Homebridge)
- Each plugin runs in a separate OS process
- Communication via IPC (gRPC, stdin/stdout, message passing)
- **Pros**: Complete crash isolation, memory protection, resource limits via cgroups/ulimits
- **Cons**: High overhead, complex communication, not practical for 4-5 lightweight plugins

#### Error Boundaries (React)
- `componentDidCatch` / `getDerivedStateFromError` lifecycle methods
- Catch rendering errors in child component tree, display fallback UI
- Facebook wraps sidebar, info panel, conversation log, and message input in separate boundaries
- **Pros**: Native React pattern, zero overhead, granular per-widget
- **Cons**: Only catches render errors — not event handlers, async code, or SSR

#### Route-Level Error Handling (Express, Fastify)
- Express: Error-handling middleware `(err, req, res, next)`
- Fastify: Plugin-scoped error handlers via `setErrorHandler`
- Each plugin scope can have its own error handler without affecting others
- **Pros**: Simple, catches sync and async route errors
- **Cons**: Doesn't protect against process-crashing errors (unhandled rejection, OOM)

#### Sandboxed Execution (WebAssembly, isolated-vm)
- `isolated-vm`: V8 isolates for running untrusted JS with memory limits
- WebAssembly: Hardware-enforced boundary, same process
- **Pros**: Strong isolation without IPC overhead
- **Cons**: Severe API limitations, complex to set up, overkill for trusted local plugins

### Recommended Approach for Dev Toolkit

**Layered isolation (no process boundaries needed)**:

1. **Backend**: Fastify-style plugin encapsulation with per-plugin error handlers. If a plugin's route throws, it returns a 500 for that route without affecting other plugins. Use `process.on('uncaughtException')` and `process.on('unhandledRejection')` as last-resort global handlers.

2. **Frontend**: React Error Boundaries wrapping each plugin's component tree. If the Markdown Browser crashes, the JSON Table tool still works. The shell shows a "Plugin crashed — click to reload" fallback.

3. **Startup**: Try/catch around each plugin's `onInit()`. If a plugin fails to initialize, log the error, mark it as unhealthy, skip it in the sidebar, and continue loading others.

4. **Health checks**: Each plugin optionally exposes a `healthCheck()`. The `/health` endpoint aggregates these. Unhealthy plugins get a warning badge in the nav.

Process isolation is overkill for 4-5 trusted, locally-running plugins. Error boundaries + scoped error handlers provide sufficient protection with minimal complexity.

---

## 4. Plugin Lifecycle Management

### Patterns Studied

#### Strapi Lifecycle
```
register() → bootstrap() → [running] → destroy()
```
- `register()`: Before DB/routing, for declaring what the plugin provides
- `bootstrap()`: After all plugins register, for initialization that needs other plugins
- `destroy()`: Cleanup on shutdown

#### Fastify/Avvio Lifecycle
```
[build DAG] → [load plugins in topological order] → [ready] → [listen] → [close]
```
- Avvio manages the async plugin loading queue
- Plugins loaded in dependency order (DAG)
- `onReady` hook fires when all plugins loaded
- `onClose` hook fires for cleanup

#### Backstage Lifecycle
```
[discover modules] → [initialize all modules for plugin] → [initialize plugin] → [ready]
```
- All modules extending a plugin initialize before the plugin itself
- Extension points are populated by modules before plugin code runs

#### VS Code Activation Model
```
[inactive] → [activation event fires] → activate() → [active] → deactivate()
```
- Lazy loading: extensions only load when needed
- `activationEvents` declare triggers (on command, on language, on file pattern)
- `deactivate()` for cleanup

### Plugin Dependency Resolution

All studied systems that support inter-plugin dependencies use topological sort of a DAG:
1. Build a directed graph: plugin A depends on B = edge B → A
2. Detect cycles (error if found — circular deps are forbidden)
3. Sort topologically: initialize in order so dependencies are ready first
4. Kahn's Algorithm (BFS-based) is simplest to implement and debug

### Recommended Lifecycle for Dev Toolkit

```
Phase 1: Discovery
  Scan plugins/ directory
  Load and validate manifests
  Build dependency graph
  
Phase 2: Initialization (topological order)
  For each plugin (in dependency order):
    Try: plugin.onInit(context)
    Catch: log error, mark as failed, continue

Phase 3: Registration
  Register healthy plugins' routes with the server
  Register healthy plugins' components with the frontend shell
  Build navigation from healthy plugins' nav entries

Phase 4: Ready
  Start listening on configured port
  Log available plugins and their health

Phase 5: Shutdown (reverse order)
  For each plugin (reverse dependency order):
    plugin.onDestroy()
```

**Hot reload** (dev mode only):
- Use Vite HMR for frontend components — plugin component changes reflect instantly
- Use `chokidar` or Vite's server watcher for backend route changes — re-register affected plugin's routes
- Do NOT re-run `onInit` on hot reload — only swap the route handlers and components

---

## 5. Frontend Plugin Patterns

### Patterns Studied

#### Micro-Frontends (Module Federation, Single-SPA)

**Module Federation** (Webpack 5 / Vite plugin):
- Separate builds per micro-frontend, loaded at runtime via `remoteEntry.js`
- Shared dependencies (React, etc.) loaded once
- Cross-bundler support as of 2026 (Vite, Webpack, Rollup, Rspack)
- **Verdict for Dev Toolkit**: Massive overkill. Module Federation solves organizational scale problems (different teams, different deploy cycles). We have 4-5 plugins in a monorepo.

**Single-SPA**:
- Framework-agnostic micro-frontend router
- Each "application" independently mounts/unmounts
- Supports mixed frameworks (React + Vue + Angular)
- **Verdict**: Same as above. Designed for multi-team, multi-framework. We're single-framework.

#### Slot/Extension Point Pattern (Backstage)

Backstage's composability system:
- Pages define named "slots" (inputs) that accept specific extension types
- Plugins fill slots by providing extensions matching the input contract
- Extension blueprints (PageBlueprint, EntityCardBlueprint) enforce consistency
- Route references decouple navigation from URL paths

**Verdict**: The slot pattern is relevant if plugins need to embed into each other's UIs. For our use case (each plugin gets its own full page), we only need the navigation slot pattern (sidebar entries).

#### Shared Component Registry

Backstage `@backstage/core-components` provides a shared UI library. Plugins use the same button, table, and card components. The registry is just a well-known npm package.

**Verdict**: Highly relevant. A shared component library ensures visual consistency across plugins.

#### iframe Isolation

Each plugin renders in its own iframe:
- Complete DOM isolation
- Separate error domains
- Communication via `postMessage`
- **Verdict**: Poor DX, breaks shared styling, adds latency. Not appropriate for a cohesive local tool.

### Recommended Frontend Architecture for Dev Toolkit

**Single React app with route-based code splitting:**

```
Shell (always loaded)
├── Sidebar (nav entries from all plugins)
├── Header (breadcrumb, tool switcher)
└── <Routes>
    ├── /markdown  → <ErrorBoundary><Suspense><MarkdownBrowser /></Suspense></ErrorBoundary>
    ├── /json      → <ErrorBoundary><Suspense><JsonTable /></Suspense></ErrorBoundary>
    ├── /agents    → <ErrorBoundary><Suspense><AgentBuilder /></Suspense></ErrorBoundary>
    └── /gateway   → <ErrorBoundary><Suspense><PermissionsGateway /></Suspense></ErrorBoundary>
```

Each plugin's frontend component is lazy-loaded (`React.lazy` or Vite dynamic import). The shell provides:
- **Sidebar navigation** — populated from plugin manifests
- **Error boundary per plugin** — crash isolation
- **Suspense per plugin** — loading states
- **Shared component library** — consistent UI across plugins
- **Shared state** (if needed) — React context or lightweight store

This is simpler than Backstage's full extension system but follows the same principles: plugins provide components, the shell provides the frame.

---

## 6. Plugin Configuration Declaration

### Patterns Studied

| System | Declaration Method | What's Declared |
|--------|--------------------|-----------------|
| **VS Code** | `package.json` contributes field | Commands, views, menus, keybindings, config schema |
| **Grafana** | `plugin.json` manifest | Name, type, version, dependencies, includes |
| **Backstage** | TypeScript `createFrontendPlugin()` | Plugin ID, extensions, routes, external routes |
| **Strapi** | JS/TS export object | Routes, controllers, services, config schema |
| **Fastify** | Function signature | Implicit (routes registered imperatively) |
| **Nuxt** | Filesystem convention | Implicit (file location determines behavior) |

### Analysis

**JSON manifests** (`plugin.json`, `package.json`): Static, parseable without executing code. Great for tooling (IDE support, validation). But limited — can't express dynamic behavior.

**TypeScript interfaces**: Type-safe, IDE-autocomplete, can express complex contracts. Requires importing and executing code to validate. Best for monorepo plugins where types are shared.

**Decorator-based**: `@Plugin({ routes: [...] })` — clean syntax but requires build tooling or runtime reflection. Less common in the Node/React ecosystem.

### Recommended Configuration for Dev Toolkit

**TypeScript export satisfying a typed interface:**

Each plugin's `index.ts` default-exports an object satisfying `DevToolkitPlugin`:

```typescript
// plugins/markdown-browser/index.ts
import { definePlugin } from '@dev-toolkit/core';

export default definePlugin({
  id: 'markdown-browser',
  name: 'Markdown Browser',
  version: '0.1.0',
  nav: {
    label: 'Markdown',
    icon: 'file-text',
    path: '/markdown',
    order: 1,
  },
  dependencies: [],
  routes: (router) => {
    router.get('/api/markdown/files', listMarkdownFiles);
    router.get('/api/markdown/files/:path', getMarkdownFile);
  },
  component: () => import('./components/MarkdownBrowser'),
  healthCheck: async () => ({ status: 'ok' }),
});
```

**Why TypeScript over JSON manifest:**
- Type safety and autocompletion during development
- Can express functions (routes, component loaders, health checks)
- `definePlugin` helper provides validation and typing
- No separate schema/validation layer needed — TypeScript IS the schema
- For a monorepo with 4-5 plugins, the simplicity wins over tooling-parseable JSON

---

## 7. Comparison Matrix

| Criterion | Backstage | Fastify | Strapi | VS Code | Grafana | Homebridge |
|-----------|-----------|---------|--------|---------|---------|------------|
| **Discovery** | npm packages + app config | `fastify-autoload` filesystem scan | Convention dirs | Marketplace / `package.json` | Plugin catalog + `plugin.json` | npm `homebridge-` prefix |
| **Contract** | TypeScript API (`createPlugin`) | Function signature | Export object | `package.json` manifest | `plugin.json` + `module.ts` | TypeScript interface |
| **Isolation** | Error boundaries (FE), scoped modules (BE) | Encapsulated scopes (DAG) | Namespace isolation | Process per extension host | Process isolation (Go backend) | Per-accessory |
| **Dependencies** | Route refs + utility APIs | Parent-child DAG | Plugin API getters | Extension dependencies array | `plugin.json` dependencies | None |
| **Hot Reload** | Webpack HMR | Restart (no native HMR) | Restart | Extension host restart | Frontend HMR, backend restart | Restart |
| **Frontend** | React extensions + slot-filling | N/A (backend only) | React admin panel | Webview panels | React panels | Config UI |
| **Complexity** | Very High | Low | Medium | High | Medium | Low |
| **Best For** | Large platform with many plugins | Backend microservices | CMS with admin UI | IDE integration | Dashboards | IoT devices |

### Relevance to Dev Toolkit

| System | What to Borrow | What to Skip |
|--------|----------------|--------------|
| **Backstage** | Route refs for cross-plugin nav, error boundary per plugin, extension pattern | Full extension point system (overkill), npm-package-per-plugin model |
| **Fastify** | Encapsulated plugin scopes, decorator pattern for shared services, autoload convention | DAG encapsulation complexity (unnecessary for 4-5 plugins) |
| **Strapi** | `register`/`bootstrap`/`destroy` lifecycle, structured route/controller/service pattern | Content type system, admin panel API |
| **VS Code** | Lazy activation, declarative capabilities | Extension marketplace, language server protocol |
| **Grafana** | Plugin manifest for metadata, health checks | Go backend, gRPC protocol |
| **Homebridge** | Dynamic registration/unregistration | Platform/accessory model (IoT-specific) |

---

## 8. Recommended Approach

### Architecture Summary

For the Dev Toolkit's specific needs (4-5 plugins, web-based, localhost, single developer), the recommended architecture combines patterns from multiple systems while keeping complexity minimal.

### Core Design Principles

1. **Convention + Contract**: Plugins discovered by filesystem convention (`plugins/` directory), but must satisfy a TypeScript interface
2. **Typed Manifest via Code**: No separate JSON manifest — the TypeScript export IS the manifest
3. **Layered Isolation**: React error boundaries (frontend) + scoped error handlers (backend) + try/catch on init
4. **Simple Lifecycle**: `onInit` → running → `onDestroy`, with topological sort for dependency ordering
5. **Vite-Native**: Use Vite for both dev server (HMR) and build. No separate bundling step.

### Plugin Structure

```
plugins/
├── markdown-browser/
│   ├── index.ts              # Plugin manifest (default export satisfying DevToolkitPlugin)
│   ├── routes.ts             # Backend route handlers
│   └── components/
│       └── MarkdownBrowser.tsx  # Frontend component(s)
├── json-table/
│   ├── index.ts
│   ├── routes.ts
│   └── components/
│       └── JsonTable.tsx
├── agent-builder/
│   ├── index.ts
│   ├── routes.ts
│   └── components/
│       └── AgentBuilder.tsx
└── permissions-gateway/
    ├── index.ts
    ├── routes.ts
    └── components/
        └── PermissionsGateway.tsx
```

### Stack Recommendation

Given the plugin patterns analyzed:

- **Runtime**: Node.js with Fastify (plugin encapsulation is native, autoload for discovery)
- **Frontend**: React with Vite (HMR, lazy loading, code splitting are native)
- **Plugin contract**: TypeScript interface with `definePlugin()` helper
- **Discovery**: `@fastify/autoload`-inspired directory scanning of `plugins/`
- **Lifecycle**: Strapi-inspired `onInit`/`onDestroy` with topological dependency resolution
- **Isolation**: React error boundaries (FE) + Fastify scoped error handlers (BE)
- **Hot reload**: Vite HMR for frontend, Vite server restart for backend changes
- **Navigation**: Backstage-inspired declarative nav entries + route path prefix per plugin

### Why Fastify + Vite + React

1. **Fastify** has the best plugin model for our backend needs — encapsulation, autoload, decorators for shared services (DB connections, file watchers), typed with TypeScript
2. **Vite** provides instant HMR, native ESM, and is the de facto standard for React dev in 2026
3. **React** is the most pragmatic choice — largest ecosystem, error boundaries are native, lazy loading is native, the team (Claudio project) is already in a JS/TS stack
4. The combination avoids the complexity of micro-frontends (Module Federation, Single-SPA) while providing all the plugin capabilities needed

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Plugin discovery | Filesystem scan of `plugins/` | Drop-in convenience, no central registry to edit |
| Plugin contract | TypeScript interface | Type safety, IDE support, functions expressible (routes, components) |
| Plugin manifest | Code export, not JSON file | Can express route handlers and component loaders; TS provides validation |
| Frontend delivery | Single React SPA with code splitting | Simpler than micro-frontends, sufficient for 4-5 plugins |
| Plugin isolation (FE) | React Error Boundaries | Native React, zero overhead, per-plugin crash containment |
| Plugin isolation (BE) | Fastify scoped error handlers | Native Fastify, per-plugin error domains |
| Inter-plugin deps | Topological sort of declared dependencies | Simple, covers the Agent Builder → Markdown Editor case |
| Hot reload | Vite HMR (FE) + server restart (BE) | Vite HMR is instant; backend route changes are rare |
| Configuration | None needed (localhost, no auth) | Keep it simple; env vars for port only |

### Risks and Open Questions

1. **Fastify + Vite integration**: Need to verify that Fastify can serve the Vite dev server and API routes simultaneously. Vite's `createServer` middleware mode should work with Fastify's `register` for static serving, but needs validation.

2. **Full-stack hot reload**: Vite HMR handles frontend well, but backend route handler changes require either:
   - Server restart (simple, acceptable for local dev)
   - Custom HMR protocol for route handlers (complex, likely not worth it)

3. **Shared services**: Plugins like Agent Builder may need access to shared services (file system watchers, data stores). The Fastify decorator pattern handles this well — register shared services at the root scope, plugins inherit access.

4. **Plugin testing**: Each plugin should be testable in isolation. The `definePlugin` contract makes this straightforward — mock the `PluginContext`, call `onInit`, test routes with `supertest` or Fastify's `inject`.

5. **Form factor validation**: This research assumes the web server form factor. The TypeScript plugin interface is form-factor agnostic enough that the same backend routes could be surfaced via CLI, and the component loading pattern could work in a VS Code webview if the form factor changes later.

---

## Sources

### Backstage
- [Architecture Overview](https://backstage.io/docs/overview/architecture-overview/)
- [Frontend Plugins](https://backstage.io/docs/frontend-system/architecture/plugins/)
- [Frontend Extensions](https://backstage.io/docs/frontend-system/architecture/extensions/)
- [Backend Extension Points](https://backstage.io/docs/backend-system/architecture/extension-points/)
- [Frontend Routes](https://backstage.io/docs/frontend-system/architecture/routes/)
- [Common Extension Blueprints](https://backstage.io/docs/frontend-system/building-plugins/common-extension-blueprints/)

### Fastify
- [Plugins Reference](https://fastify.dev/docs/latest/Reference/Plugins/)
- [Plugins Guide](https://fastify.dev/docs/latest/Guides/Plugins-Guide/)
- [Encapsulation](https://fastify.dev/docs/latest/Reference/Encapsulation/)
- [Complete Guide to Fastify Plugin System (Nearform)](https://nearform.com/digital-community/the-complete-guide-to-fastify-plugin-system/)
- [fastify-autoload](https://github.com/fastify/fastify-autoload)

### Grafana
- [Anatomy of a Plugin](https://grafana.com/developers/plugin-tools/key-concepts/anatomy-of-a-plugin)
- [Plugin System (DeepWiki)](https://deepwiki.com/grafana/grafana/11-plugin-system)

### Strapi
- [Server API for Plugins](https://docs.strapi.io/cms/plugins-development/server-api)
- [Admin Panel API](https://docs.strapi.io/cms/plugins-development/admin-panel-api)
- [Plugin Structure](https://docs.strapi.io/dev-docs/plugins/development/plugin-structure)

### VS Code
- [Extension Anatomy](https://code.visualstudio.com/api/get-started/extension-anatomy)
- [Contribution Points](https://code.visualstudio.com/api/references/contribution-points)
- [Activation Events](https://code.visualstudio.com/api/references/activation-events)

### Homebridge
- [DynamicPlatformPlugin](https://developers.homebridge.io/homebridge/interfaces/DynamicPlatformPlugin.html)
- [Accessory and Platform Plugins (DeepWiki)](https://deepwiki.com/homebridge/homebridge/4.3-accessory-and-platform-plugins)

### Nuxt
- [Auto-imports](https://nuxt.com/docs/guide/concepts/auto-imports)
- [Plugins Directory](https://nuxt.com/docs/guide/directory-structure/plugins/)

### Gatsby
- [Gatsby Lifecycle APIs](https://www.gatsbyjs.com/docs/conceptual/gatsby-lifecycle-apis/)
- [Gatsby Node APIs](https://www.gatsbyjs.com/docs/reference/config-files/gatsby-node/)

### Micro-Frontends
- [Module Federation](https://module-federation.io/)
- [Single-SPA Overview](https://single-spa.js.org/docs/microfrontends-concept/)
- [Micro-Frontends: Still Worth It? (Feature-Sliced Design)](https://feature-sliced.design/blog/micro-frontend-architecture)

### Vite
- [HMR API](https://vite.dev/guide/api-hmr)
- [HMR hotUpdate Plugin Hook](https://vite.dev/changes/hotupdate-hook)

### Plugin Isolation
- [Designing Secure Plugin Architectures (CyberPath)](https://cyberpath-hq.com/blog/designing-secure-plugin-architectures/)
- [React Error Boundaries (Legacy Docs)](https://legacy.reactjs.org/docs/error-boundaries.html)
- [React Error Boundaries for Graceful Handling](https://oneuptime.com/blog/post/2026-01-15-react-error-boundaries/view)
