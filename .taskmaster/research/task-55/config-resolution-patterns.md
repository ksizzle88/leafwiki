# Configuration Resolution & Multi-Layer Merge Patterns

Research for Issue #60 (Agent Builder) — Task #55 (Dev Toolkit Core Framework)

## Table of Contents

1. [Claude Code's Config Resolution](#1-claude-codes-config-resolution)
2. [Git Config Resolution](#2-git-config-resolution)
3. [Terraform Variable Resolution](#3-terraform-variable-resolution)
4. [Docker Compose Merge Semantics](#4-docker-compose-merge-semantics)
5. [ESLint Flat Config Cascade](#5-eslint-flat-config-cascade)
6. [Cosmiconfig (Node.js Convention)](#6-cosmiconfig-nodejs-convention)
7. [Pydantic Settings (Python)](#7-pydantic-settings-python)
8. [CSS Cascade & Specificity](#8-css-cascade--specificity)
9. [Deep Merge Libraries](#9-deep-merge-libraries)
10. [Schema Validation Libraries](#10-schema-validation-libraries)
11. [Provenance Tracking Approaches](#11-provenance-tracking-approaches)
12. [Comparison Matrix](#12-comparison-matrix)
13. [Recommended Design for Agent Builder](#13-recommended-design-for-agent-builder)

---

## 1. Claude Code's Config Resolution

**Source**: [Claude Code Settings Documentation](https://code.claude.com/docs/en/settings)

### Precedence Order (Highest → Lowest)

1. **Managed/Enterprise settings** (immutable, cannot be overridden)
   - Server-managed (Anthropic servers)
   - MDM/OS-level policies (macOS plist, Windows registry)
   - `managed-settings.json` file
2. **Command-line arguments** (temporary session overrides)
3. **Local project settings** (`.claude/settings.local.json`) — personal, gitignored
4. **Shared project settings** (`.claude/settings.json`) — team-shared, committed
5. **User/Global settings** (`~/.claude/settings.json`) — personal, all projects

### Merge Strategy: Hybrid (Type-Dependent)

Claude Code uses **three distinct merge strategies** based on the value type:

| Value Type | Strategy | Example |
|---|---|---|
| **Scalars** | Last-write-wins (highest precedence replaces) | `"model": "claude-opus-4-6"` |
| **Objects** | Deep merge (recursive merge of nested keys) | `sandbox.filesystem.*` keys merge |
| **Arrays** | Concatenate + deduplicate | `permissions.allow` arrays append |

### Array-Valued Settings That Concatenate

These specific keys use append semantics (NOT replace):
- `permissions.allow`, `permissions.ask`, `permissions.deny`
- `permissions.additionalDirectories`
- `sandbox.filesystem.allowWrite`, `sandbox.filesystem.denyWrite`, `sandbox.filesystem.denyRead`
- `sandbox.network.allowedDomains`, `sandbox.network.allowUnixSockets`
- `allowedMcpServers`, `deniedMcpServers`
- `allowedHttpHookUrls`, `httpHookAllowedEnvVars`
- `availableModels`

### CLAUDE.md Resolution

CLAUDE.md files are concatenated (not merged) in precedence order:
1. Project-level: `.claude/CLAUDE.md` or `CLAUDE.md` at project root
2. User-level: `~/.claude/CLAUDE.md`

### Provenance Visibility

Claude Code provides the `/status` command to show which settings sources are active, displaying labels like:
- `Enterprise managed settings (remote)`
- `Enterprise managed settings (file)`
- User/project source indicators

### Key Insight for Agent Builder

Claude Code's approach is the **most directly relevant** model. The Agent Builder must replicate this exact resolution order and merge behavior because it needs to show users what Claude Code will actually see. The hybrid merge strategy (scalars replace, objects deep-merge, specific arrays concatenate) is non-trivial and must be faithfully implemented.

---

## 2. Git Config Resolution

**Source**: [git-config documentation](https://git-scm.com/docs/git-config)

### Precedence Order (Highest → Lowest)

1. **Worktree** (`$GIT_DIR/config.worktree`) — most specific
2. **Local** (`$GIT_DIR/config`) — per-repository
3. **Global** (`~/.gitconfig` or `$XDG_CONFIG_HOME/git/config`) — per-user
4. **System** (`$(prefix)/etc/gitconfig`) — machine-wide

### Merge Strategy: Last-Write-Wins

All values use scalar replacement. Git does not deep-merge objects or concatenate arrays. Multi-valued keys (like `remote.*.fetch`) are **separate entries**, not merged arrays.

### Provenance Visibility

```bash
git config --show-origin --list
# Shows BOTH the value AND the file it came from:
# file:/home/user/.gitconfig    user.name=Alice
# file:.git/config              user.email=alice@work.com
```

This is the gold standard for provenance tracking. The `--show-origin` flag immediately answers "where does this come from?"

### Applicable Pattern for Agent Builder

The `--show-origin` concept maps directly to the Agent Builder's "Resolved Config View" requirement. Each resolved value should be annotable with its source file.

---

## 3. Terraform Variable Resolution

**Source**: [Terraform Input Variables](https://developer.hashicorp.com/terraform/language/values/variables)

### Precedence Order (Highest → Lowest)

1. **CLI flags** (`-var` and `-var-file`, order-dependent)
2. **Environment variables** (`TF_VAR_*`)
3. **Auto-loaded files** (`*.auto.tfvars`, lexical order)
4. **Default file** (`terraform.tfvars`)
5. **Variable block defaults** (`default = ...` in `.tf` files)

### Merge Strategy: Scalar Replacement Only

Terraform uses strict scalar replacement. Even complex variable types (maps, lists) are entirely replaced by higher-precedence sources — no merging.

### Validation Pattern

Terraform validates variables using `validation` blocks with custom conditions:

```hcl
variable "image_id" {
  type        = string
  validation {
    condition     = can(regex("^ami-", var.image_id))
    error_message = "Must be a valid AMI ID."
  }
}
```

Variables can be marked `sensitive = true` to redact them from output.

### Applicable Pattern for Agent Builder

- The **validation block** pattern is useful for agent definition validation
- The **sensitive variable** concept applies to credentials/tokens in config
- The clear, documented precedence order is easy for users to reason about

---

## 4. Docker Compose Merge Semantics

**Source**: [Docker Compose Merge Reference](https://docs.docker.com/reference/compose-file/merge/)

### Merge Strategy: Context-Dependent

Docker Compose uses the most sophisticated merge semantics of any tool studied:

| Data Type | Strategy | Details |
|---|---|---|
| **YAML mappings** | Deep merge | Add missing entries, merge conflicting |
| **YAML sequences** (default) | Append | Values from override file appended |
| **Shell commands** (`command`, `entrypoint`, `healthcheck.test`) | Replace | Latest definition wins entirely |
| **Unique resources** (`ports`, `volumes`, `secrets`) | Smart merge | Merge entries sharing a unique key; append new |
| **Key-value pairs** (`environment`, `labels`) | Key-level merge | Same key → override; new key → add |

### Escape Hatches

Docker Compose provides two YAML tags for overriding the default merge:

- **`!reset`**: Clears a value back to its default (equivalent to "unset")
  ```yaml
  # Override file: clear the ports list entirely
  services:
    web:
      ports: !reset []
  ```

- **`!override`**: Fully replaces an attribute, bypassing merge logic
  ```yaml
  # Override file: replace volumes entirely instead of appending
  services:
    web:
      volumes: !override
        - ./new-vol:/data
  ```

### Applicable Pattern for Agent Builder

The **`!reset` and `!override` tags** solve a critical problem: how does a local layer "unset" something from a project layer? The Agent Builder should support an equivalent mechanism, potentially using a sentinel value like `null` or a `!unset` marker.

The **smart merge by unique key** pattern is relevant for merging MCP server configs (keyed by server name), hook configs (keyed by event name), and agent definitions (keyed by agent name).

---

## 5. ESLint Flat Config Cascade

**Source**: [ESLint Blog: Flat Config](https://eslint.org/blog/2022/08/new-config-system-part-2/)

### Design Philosophy

ESLint moved from directory-based cascading (`.eslintrc` at multiple directory levels) to a **single array of config objects** in one file (`eslint.config.js`). Each config object includes a `files` glob pattern and rules.

### Merge Strategy: Array-Position Precedence

```javascript
export default [
  // Base config (lowest precedence)
  { rules: { "no-console": "error" } },
  
  // TypeScript override (higher precedence — later in array)
  { files: ["**/*.ts"], rules: { "no-console": "warn" } },
  
  // Test override (highest precedence — last in array)
  { files: ["**/*.test.*"], rules: { "no-console": "off" } }
];
```

For a file matching multiple config objects, ESLint merges them top-to-bottom (last wins).

### Recent Addition: `extends` (2025)

ESLint re-added `extends` inside flat config via `defineConfig()`:

```javascript
import { defineConfig } from "eslint";
export default defineConfig([
  { extends: ["eslint:recommended"] },
  { rules: { "no-console": "warn" } }
]);
```

### Applicable Pattern for Agent Builder

The flat config model is elegant: **one array, position determines precedence**. This could work for the Agent Builder's internal representation — resolve all config layers into an ordered array, then merge top-to-bottom.

---

## 6. Cosmiconfig (Node.js Convention)

**Source**: [cosmiconfig on GitHub](https://github.com/cosmiconfig/cosmiconfig)

### Search Strategy

Cosmiconfig searches **up the directory tree** for configuration in standardized locations:
1. `package.json` property
2. `.myapprc` (JSON, YAML, JS, TS variants)
3. `.config/myapprc`
4. `myapp.config.js`

### Layered Config via `$import`

```json
{
  "$import": "./base-config.json",
  "rules": {
    "override-rule": true
  }
}
```

Multiple imports processed in declaration order; last entry wins for conflicts.

### Applicable Pattern for Agent Builder

Cosmiconfig's **directory-tree-walking** pattern is how the Agent Builder should discover config files. Walk from `$CWD` upward through parent directories, collecting config files at each level, then merge them in precedence order.

---

## 7. Pydantic Settings (Python)

**Source**: [Pydantic Settings Documentation](https://docs.pydantic.dev/latest/concepts/pydantic_settings/)

### Source Ordering

Pydantic Settings uses the `settings_customise_sources()` method to define source precedence:

```python
class Settings(BaseSettings):
    @classmethod
    def settings_customise_sources(cls, settings_cls, **kwargs):
        return (
            env_settings,          # Highest precedence
            dotenv_settings,       # .env files
            json_settings,         # JSON config files
            init_settings,         # Constructor args (lowest)
        )
```

### Merge Strategy

- Scalars: first source that provides a value wins
- Nested models: deep-merged
- Environment variables with nested prefix (e.g., `MYAPP__DB__HOST`) override specific nested fields

### Schema Validation

Pydantic validates the **merged result** automatically because settings are modeled as typed Python classes. If the merged output violates type constraints, validation fails with a clear error.

### Applicable Pattern for Agent Builder

The **validate-after-merge** pattern is critical. Individual layers may be incomplete (missing required fields), but the final merged result must be valid. Pydantic proves this works well in practice.

---

## 8. CSS Cascade & Specificity

### The CSS Model as a Config Analogy

The CSS cascade provides a well-understood mental model for layered configuration:

| CSS Concept | Config Analogy |
|---|---|
| Specificity (selector weight) | Source priority (managed > local > project > user) |
| `!important` | Managed/enterprise settings (cannot be overridden) |
| Inheritance | Default values inherited from parent/global scope |
| `unset` / `revert` | Removing a value set by a lower-precedence layer |
| Computed value | The final resolved/effective value after cascade |
| DevTools "Styles" panel | The "Resolved Config View" in Agent Builder |

### Key Insight: DevTools as UX Inspiration

Browser DevTools show cascaded CSS with **strikethrough** for overridden values and annotations showing the source file/line. This is exactly the UX the Agent Builder needs:

```
model: "claude-opus-4-6"          ← .claude/settings.json:3
~~model: "claude-sonnet-4-6"~~    ← ~/.claude/settings.json:2 (overridden)
```

### The "unset" Problem

CSS provides `unset`, `revert`, and `revert-layer` keywords that let a more-specific rule explicitly remove an inherited value. The Agent Builder needs an equivalent for the case where:
- Project `settings.json` adds a permission
- Local `settings.local.json` wants to remove it

---

## 9. Deep Merge Libraries

### JavaScript/TypeScript Options

| Library | Strategy | Array Handling | Performance | Notes |
|---|---|---|---|---|
| **deepmerge** (TehShrike) | Recursive clone + merge | Configurable via `customMerge` | Moderate | Most popular, configurable |
| **@fastify/deepmerge** | Recursive merge | Configurable | Fast | Fastest benchmark |
| **deepmerge-ts** | Smart merge | Type-aware | Fast | TypeScript-first |
| **lodash.merge** | In-place recursive | Concatenate | Moderate | Well-known, but mutates target |
| **merge-deep** | Recursive | Concatenate | Moderate | Simple API |

### Custom Merge Strategies (deepmerge)

```javascript
import deepmerge from 'deepmerge';

const result = deepmerge(base, override, {
  // Custom array merge: concatenate + deduplicate
  arrayMerge: (target, source, options) => {
    return [...new Set([...target, ...source])];
  },
  
  // Custom merge per key
  customMerge: (key) => {
    if (key === 'permissions') {
      return (a, b) => ({
        allow: [...new Set([...(a.allow || []), ...(b.allow || [])])],
        deny: [...new Set([...(a.deny || []), ...(b.deny || [])])]
      });
    }
  }
});
```

### Recommendation for Agent Builder

Use **deepmerge-ts** (TypeScript-first, good perf) with custom merge strategies per key. The Agent Builder needs per-key merge strategy configuration because Claude Code uses different strategies for different keys (scalars replace, specific arrays concatenate, objects deep-merge).

---

## 10. Schema Validation Libraries

### Comparison for Config Validation

| Library | Language | Strengths | Weaknesses |
|---|---|---|---|
| **Zod** | TypeScript | Type inference, `.merge()`, `.partial()`, composable | Runtime-only |
| **AJV + JSON Schema** | JS/TS | Standard format, shareable schemas, fast | Verbose, weak TS inference |
| **ajv-ts** | TypeScript | Zod-like API with JSON Schema output | Newer, smaller community |
| **Pydantic** | Python | Validate-after-merge, type coercion, nested models | Python only |

### Validate Merged Result, Not Individual Layers

Individual config layers are often **incomplete** (a local override may only set one key). Validation must happen on the **final merged result**, not on individual files.

Pattern:
```typescript
// Per-layer schema: all fields optional
const LayerSchema = ConfigSchema.partial();

// Merged result schema: required fields enforced
const ResolvedSchema = ConfigSchema.required({ model: true, permissions: true });

// Process
const layers = files.map(f => LayerSchema.parse(readJson(f)));
const merged = mergeLayers(layers);
const resolved = ResolvedSchema.parse(merged);  // Validate completeness
```

### Recommendation for Agent Builder

Use **Zod** for the TypeScript CLI and web UI:
- Define a `ConfigLayerSchema` (partial, for individual files)
- Define a `ResolvedConfigSchema` (strict, for the merged output)
- Use `.merge()` to compose schemas from sub-schemas (permissions, hooks, agents, etc.)
- Convert to JSON Schema via `zod-to-json-schema` for documentation/sharing

---

## 11. Provenance Tracking Approaches

### The Core Problem

The Agent Builder's "Resolved Config View" must answer: **"Where does this value come from?"** This requires tracking the source file and path for every value in the merged result.

### Existing Implementations

| System | Approach | API |
|---|---|---|
| **Git** (`--show-origin`) | Annotates each value with source file | `file:/path → key=value` |
| **ASP.NET Core** (`GetDebugView()`) | IConfigurationRoot debug dump with provider names | `key = value (Provider)` |
| **Spring Boot** (`/actuator/env`) | Property sources list with origin tracking | `{ value, origin: "file:line" }` |
| **Apple Pkl** (proposed) | Capture source sections + stack frames | Not yet implemented |
| **CSS DevTools** | Strikethrough overridden values + source file:line | Visual in browser |

### Recommended Implementation: Provenance Map

Instead of modifying the merged config object, maintain a **parallel provenance map**:

```typescript
interface ProvenanceEntry {
  value: unknown;              // The value at this path
  source: string;              // File path (e.g., "~/.claude/settings.json")
  sourceType: ConfigScope;     // "managed" | "user" | "project" | "local"
  path: string;                // JSON path (e.g., "permissions.allow[2]")
  overrides?: ProvenanceEntry[]; // Values this entry overrode (for strikethrough display)
}

type ProvenanceMap = Map<string, ProvenanceEntry>;
```

### Building the Provenance Map

During the merge process, record provenance for each key:

```typescript
function mergeWithProvenance(
  layers: Array<{ config: object; source: string; sourceType: ConfigScope }>,
  mergeStrategy: MergeStrategyMap
): { resolved: ResolvedConfig; provenance: ProvenanceMap } {
  const provenance = new Map<string, ProvenanceEntry>();
  
  for (const layer of layers) {  // Iterate lowest → highest precedence
    for (const [path, value] of flattenObject(layer.config)) {
      const existing = provenance.get(path);
      const entry: ProvenanceEntry = {
        value,
        source: layer.source,
        sourceType: layer.sourceType,
        path,
        overrides: existing ? [existing, ...(existing.overrides || [])] : undefined
      };
      provenance.set(path, entry);
    }
  }
  
  // Also handle array concatenation provenance
  // For concatenated arrays, each element tracks its source
  
  return { resolved: buildFromProvenance(provenance), provenance };
}
```

### Provenance Display Formats

**CLI** (`agent-builder resolve settings`):
```
model: claude-opus-4-6                  [.claude/settings.json]
  ↳ overrides: claude-sonnet-4-6        [~/.claude/settings.json]
permissions.allow:
  - Bash(git:*)                         [.claude/settings.json]
  - Bash(npm:*)                         [.claude/settings.json]  
  - WebSearch                           [.claude/settings.local.json]
env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"  [.claude/settings.json]
```

**Web UI** (Dev Toolkit Plugin):
- Color-coded badges per source (green=project, blue=user, purple=local, red=managed)
- Strikethrough for overridden values (CSS DevTools style)
- Click a value to jump to source file:line

---

## 12. Comparison Matrix

### Merge Strategy Comparison

| System | Scalar | Object | Array | Unset/Reset | Provenance |
|---|---|---|---|---|---|
| **Claude Code** | Replace | Deep merge | Concat+dedup (specific keys) | No | `/status` (partial) |
| **Git config** | Replace | N/A | N/A (multi-value) | `--unset` | `--show-origin` |
| **Terraform** | Replace | Replace | Replace | N/A | N/A |
| **Docker Compose** | Replace | Deep merge | Append (most), Replace (commands), Smart (ports) | `!reset`, `!override` | N/A |
| **ESLint flat** | Replace | Shallow merge per config object | Replace | N/A | N/A |
| **Cosmiconfig** | N/A (finds first) | N/A | N/A | N/A | N/A |
| **Pydantic Settings** | First source wins | Deep merge | Replace | N/A | N/A |
| **CSS** | Specificity-based | N/A | N/A | `unset`, `revert` | DevTools |

### Key Observations

1. **No tool does everything** — each makes tradeoffs between simplicity and power
2. **Claude Code's hybrid merge** (scalars replace, objects deep-merge, specific arrays concat) is the most complex strategy studied
3. **Provenance tracking** is rare — only Git and CSS DevTools do it well
4. **Unset/reset** is only supported by Docker Compose (`!reset`) and CSS (`unset`/`revert`)
5. **Validate-after-merge** is only done by Pydantic natively

---

## 13. Recommended Design for Agent Builder

### Config Resolution Engine Architecture

```
┌─────────────────────────────────────────────┐
│           Config Resolution Engine           │
├─────────────┬─────────────┬─────────────────┤
│  Discovery  │   Merge     │   Validation    │
│  (find      │   (combine  │   (verify       │
│   files)    │    layers)  │    merged       │
│             │             │    result)      │
├─────────────┼─────────────┼─────────────────┤
│  Provenance │  Strategy   │   Schema        │
│  Tracker    │  Registry   │   Registry      │
└─────────────┴─────────────┴─────────────────┘
```

### 1. Discovery Phase

Follow Claude Code's resolution order. Walk the filesystem to find:

```typescript
interface ConfigLayer {
  source: string;           // Absolute file path
  sourceType: ConfigScope;  // "managed" | "user" | "project" | "local"
  priority: number;         // 0=lowest (user), 3=highest (managed)
  content: unknown;         // Parsed file content
}

// Discovery order (lowest → highest priority):
// 1. ~/.claude/settings.json          (user)
// 2. .claude/settings.json            (project)
// 3. .claude/settings.local.json      (local)
// 4. managed-settings.json            (managed, if exists)
```

### 2. Merge Phase: Strategy Registry

Because Claude Code uses **different merge strategies for different keys**, the merge engine needs a per-key strategy registry:

```typescript
type MergeStrategy = 'replace' | 'deep-merge' | 'concat-dedup' | 'smart-keyed';

const CLAUDE_MERGE_STRATEGIES: Record<string, MergeStrategy> = {
  // Scalars — replace
  'model': 'replace',
  'statusLine': 'replace',
  
  // Objects — deep merge
  'sandbox': 'deep-merge',
  'hooks': 'deep-merge',
  'env': 'deep-merge',
  
  // Arrays — concat + deduplicate
  'permissions.allow': 'concat-dedup',
  'permissions.deny': 'concat-dedup',
  'permissions.ask': 'concat-dedup',
  'sandbox.filesystem.allowWrite': 'concat-dedup',
  'sandbox.filesystem.denyWrite': 'concat-dedup',
  'sandbox.network.allowedDomains': 'concat-dedup',
  'allowedMcpServers': 'concat-dedup',
  'deniedMcpServers': 'concat-dedup',
  
  // Smart keyed merge (by server name, agent name, etc.)
  'mcpServers': 'smart-keyed',
};

// Default: 'replace' for unknown keys
```

### 3. Provenance Tracking

Maintain a provenance map alongside the merged result:

```typescript
interface ResolvedConfig {
  config: Record<string, unknown>;
  provenance: Map<string, ProvenanceEntry>;
}

interface ProvenanceEntry {
  value: unknown;
  source: string;              // File path
  sourceType: ConfigScope;
  jsonPath: string;            // e.g., "permissions.allow[3]"
  overriddenBy?: ProvenanceEntry;  // What overrode this (chain)
  contributedFrom?: string[];     // For concat arrays: which sources contributed
}
```

### 4. Validation Phase

Use Zod with two schema tiers:

```typescript
// Layer schema: everything optional (individual files can be partial)
const ConfigLayerSchema = z.object({
  permissions: z.object({
    allow: z.array(z.string()),
    deny: z.array(z.string()),
  }).partial().optional(),
  model: z.string().optional(),
  env: z.record(z.string()).optional(),
  hooks: z.record(z.unknown()).optional(),
  // ...
}).partial();

// Resolved schema: validate the merged result has required fields
const ResolvedConfigSchema = ConfigLayerSchema.extend({
  // Add required-after-merge constraints here
});
```

### 5. Unset/Reset Support

Support a sentinel value to "unset" a key from a higher-precedence layer:

```json
// .claude/settings.local.json
{
  "permissions": {
    "allow": {
      "$unset": ["Bash(curl:*)"]  
    }
  }
}
```

This follows Docker Compose's `!reset` pattern. Implementation: during merge, process `$unset` arrays to remove matching entries from the concatenated result.

**Note**: This is an Agent Builder feature, not a Claude Code feature. It helps users understand the effect of removing something without actually editing the project file.

### 6. CLI Output Formats

```bash
# Show resolved config with provenance
agent-builder resolve settings
# Output: annotated JSON with source comments

# Show where a specific value comes from  
agent-builder resolve settings --key permissions.allow
# Output: list of all sources that contributed to this key

# Show as DOT graph (for the dependency graph feature)
agent-builder graph
# Output: DOT format showing agent → command → hook relationships

# Diff current vs compiled
agent-builder diff
# Output: unified diff of current state vs resolved output
```

### 7. Agent Definition Resolution

Agent definitions (`.claude/agents/*.md`) need their own resolution:

```
~/.claude/agents/researcher.md          (user-level agent)
.claude/agents/researcher.md            (project-level agent, overrides user)
```

For agents, the merge strategy should be **replace** (the more specific definition entirely replaces the less specific one), because markdown agent definitions are not meaningfully mergeable.

For the resolved view, show:
- Which agents are active and from which source
- Which agents are overridden (user-level agent hidden by project-level)
- Which commands reference which agents
- Which hooks fire for which events

### Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Merge library | `deepmerge-ts` with custom strategies | TypeScript-first, configurable per-key |
| Schema validation | Zod (partial for layers, strict for resolved) | TypeScript integration, composable schemas |
| Provenance storage | Parallel Map alongside resolved config | Keeps the resolved config clean/serializable |
| Unset mechanism | `$unset` sentinel in override layers | Follows Docker Compose's `!reset` pattern |
| Array merge default | Replace (only Claude Code's specific keys concat) | Match Claude Code's actual behavior |
| Agent definition merge | Replace (whole file) | Markdown not meaningfully mergeable |
| Config discovery | Filesystem walk + hardcoded paths | Match Claude Code's exact resolution paths |

### Risks and Open Questions

1. **Claude Code's merge behavior may change** — The hybrid merge strategy (scalars/objects/arrays) is undocumented in some edge cases. The Agent Builder should include a "merge strategy version" to handle future changes.

2. **MCP server config resolution** — MCP configs live in different files (`.mcp.json`, `~/.claude.json`). The Agent Builder should resolve these alongside settings.json.

3. **Performance** — For the "< 1 second resolved output" requirement, the merge + validation + provenance tracking must be fast. `deepmerge-ts` and Zod are both fast enough for small config trees.

4. **CLAUDE.md merging** — CLAUDE.md files are concatenated, not merged. The Agent Builder should display them as a sequence of sections with source annotations, not attempt to merge the markdown content.

---

## Sources

- [Claude Code Settings Documentation](https://code.claude.com/docs/en/settings)
- [Git config documentation](https://git-scm.com/docs/git-config)
- [Terraform Input Variables](https://developer.hashicorp.com/terraform/language/values/variables)
- [Docker Compose Merge Reference](https://docs.docker.com/reference/compose-file/merge/)
- [ESLint Flat Config Introduction](https://eslint.org/blog/2022/08/new-config-system-part-2/)
- [ESLint: Evolving Flat Config with extends](https://eslint.org/blog/2025/03/flat-config-extends-define-config-global-ignores/)
- [cosmiconfig on GitHub](https://github.com/cosmiconfig/cosmiconfig)
- [Pydantic Settings Documentation](https://docs.pydantic.dev/latest/concepts/pydantic_settings/)
- [deepmerge on npm](https://www.npmjs.com/package/deepmerge)
- [deepmerge-ts on npm](https://www.npmjs.com/package/deepmerge-ts)
- [@fastify/deepmerge on GitHub](https://github.com/fastify/deepmerge)
- [Zod on GitHub](https://github.com/colinhacks/zod)
- [zod-to-json-schema on npm](https://www.npmjs.com/package/zod-to-json-schema)
- [ASP.NET Core: Debugging Configuration Values](https://andrewlock.net/debugging-configuration-values-in-aspnetcore/)
- [Apple Pkl: Value Provenance Tracking (Issue #1197)](https://github.com/apple/pkl/issues/1197)
- [CSS Cascade and Specificity (MDN)](https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Cascade/Introduction)
