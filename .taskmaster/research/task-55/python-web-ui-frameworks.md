# Python Web UI Frameworks for jtbl 2.0

**Research Date**: 2026-03-13
**Context**: Issue #58 (jtbl 2.0) needs a web UI framework for an interactive JSON exploration workbench. The design doc specifies Streamlit + Ace editor. This research evaluates alternatives.

---

## Requirements from the jtbl 2.0 Design Doc

| Requirement | Description |
|-------------|-------------|
| **Data table** | Interactive grid: sort, scroll, resize columns, click-to-inspect row |
| **JSON tree viewer** | Expandable/collapsible tree with breadcrumb navigation |
| **Code editor** | Syntax-highlighted, resizable editor for jq/CLI args (Ace specified) |
| **Live preview** | Type expression → see results update in real-time |
| **File input** | Load JSON from file path, upload, or paste |
| **Export** | Copy CLI command, download as CSV/JSON/Markdown |
| **Standalone mode** | `uv run jtbl-ui.py` launches a self-contained web app |
| **Plugin mode** | Embed inside the Dev Toolkit FastAPI server (Issue #55) |
| **Single-file packaging** | PEP 723 inline metadata, `uv run` with no setup |

The critical architectural question: the framework must work **both** as a standalone tool (`uv run jtbl-ui.py`) **and** as a plugin mounted inside a FastAPI application.

---

## Framework Comparison Table

| Criteria | Streamlit | NiceGUI | Panel (HoloViz) | Gradio | Solara | Reflex | Dash (Plotly) |
|---|---|---|---|---|---|---|---|
| **GitHub Stars** | ~40k | ~12k | ~5k | ~35k | ~2k | ~22k | ~22k |
| **Architecture** | Script re-run on interaction | WebSocket, no re-run | Bokeh server | Function→UI | Reactive (React-like) | Compiles to Next.js | Flask callbacks |
| **Data table** | st.dataframe (Arrow) + streamlit-aggrid | ui.aggrid (AG Grid built-in) | Tabulator widget | gr.Dataframe | DataFrame widget | rx.data_table | dash-ag-grid |
| **JSON tree viewer** | st.json (expandable, `expanded=N`) | ui.json_editor + ui.tree | JSON pane | gr.JSON | Custom needed | Custom needed | Custom needed |
| **Code editor** | streamlit-ace (community) | ui.codemirror (built-in) | Ace widget | gr.Code | Custom needed | rx.code_editor | Custom needed |
| **Live preview** | Re-runs on change (debounced) | WebSocket push, instant | Param watching | Event callbacks | Reactive state | State management | Callbacks |
| **FastAPI mount** | Experimental (v1.53+ ASGI) | ui.run_with(app) | pn.serve + FastAPI | gr.mount_gradio_app() | Built on FastAPI | Separate process | Separate process |
| **Single-file viable** | Yes (PEP 723) | Yes (PEP 723) | Yes but awkward | Yes (PEP 723) | Possible | No (compilation) | No (layout heavy) |
| **Install size** | ~80MB (streamlit + deps) | ~30MB | ~60MB | ~100MB | ~40MB | ~200MB+ | ~80MB |
| **Learning curve** | Very low | Low | Medium | Very low | Medium | High | Medium |
| **Maturity** | High (Snowflake-backed) | Medium (growing fast) | High (NumFOCUS) | High (Hugging Face) | Low | Medium | High (Plotly) |
| **Tailwind/CSS** | Limited (st.markdown hack) | Built-in Tailwind | Custom CSS | Limited | Custom CSS | Full Tailwind | Custom CSS |
| **Theming** | Built-in themes | Quasar themes + Tailwind | Bokeh themes | Built-in themes | ipywidgets themes | Full control | Plotly themes |

---

## Detailed Analysis

### 1. Streamlit — DESIGN DOC DEFAULT

**Strengths:**
- **Lowest barrier to entry**: Write a Python script, get a web app. The jtbl design doc already specifies Streamlit, and it's the right default for a "zero install, single file" tool.
- **st.dataframe**: Built on Apache Arrow, handles 10K+ rows with virtual scrolling. Column sorting, search, and download are built in.
- **streamlit-aggrid**: Community component wrapping AG Grid. Provides column resizing, filtering, cell editing, row selection, and virtual scrolling for large datasets. Only renders visible rows.
- **st.json**: Built-in expandable JSON viewer with configurable expansion depth (`expanded=2`). Sufficient for the row inspector and basic tree viewing.
- **streamlit-ace**: Community component providing Ace editor with syntax highlighting, resizable pane, and multi-line editing. Exactly what the design doc specifies.
- **PEP 723 compatible**: `uv run jtbl-ui.py` works out of the box. This is the design doc's packaging model.
- **Huge ecosystem**: 40K+ GitHub stars, Snowflake-backed development, extensive community components.
- **NEW: ASGI mount support (v1.53+)**: Experimental `st.App` provides an ASGI-compatible entry point. Can be mounted inside FastAPI via `api.mount("/jtbl", streamlit_app)`. This resolves the plugin integration concern.

**Weaknesses:**
- **Full re-run model**: Every interaction re-runs the entire script top-to-bottom. For jtbl, this means re-parsing JSON and re-running jq on every keystroke. Mitigated by `@st.cache_data` but still architecturally wasteful.
- **Limited layout control**: Sidebar + main area is good for jtbl's layout, but complex multi-pane layouts (e.g., resizable split views) require hacks.
- **Custom styling is hard**: No direct CSS access. Themes exist but are limited. The "match Dev Toolkit shell" requirement would be difficult.
- **ASGI mount is experimental**: The FastAPI mount capability (v1.53+) is new and may have rough edges. The Starlette migration is ongoing.
- **WebSocket overhead**: Each connected browser tab maintains a WebSocket + Python process. For a single-user dev tool this is fine, but it's architecturally heavy.
- **streamlit-ace maintenance**: The community component hasn't been updated recently. The alternative `streamlit-code-editor` (based on react-ace) is more actively maintained.

**Plugin integration (FastAPI):**
```python
# Streamlit 1.53+ experimental
from streamlit.starlette import App
from fastapi import FastAPI

streamlit_app = App("jtbl-ui.py")
api = FastAPI()
api.mount("/tools/jtbl", streamlit_app)
```
This is experimental but functional. Streamlit runs as an ASGI sub-application within FastAPI.

### 2. NiceGUI — STRONGEST ALTERNATIVE

**Strengths:**
- **No re-run model**: Uses WebSocket communication. UI updates are pushed to the browser without re-running the script. This is architecturally superior for the "type expression → see results" live preview requirement.
- **AG Grid built-in**: `ui.aggrid()` provides AG Grid integration out of the box — no community component needed. Supports column resizing, filtering, sorting, row selection.
- **CodeMirror built-in**: `ui.codemirror()` provides a code editor with syntax highlighting. CodeMirror is arguably better than Ace for modern use cases.
- **JSON editor built-in**: `ui.json_editor()` provides an interactive JSON tree viewer/editor. `ui.tree()` provides expandable tree navigation.
- **FastAPI native**: NiceGUI IS a FastAPI application. Mount via `ui.run_with(fastapi_app, mount_path="/tools/jtbl")`. This is production-ready, not experimental.
- **Tailwind CSS**: Built-in Tailwind support means theming to match the Dev Toolkit shell is straightforward.
- **Full layout control**: Flexbox/grid layouts, resizable panels, tabs, dialogs. The jtbl UI layout (sidebar + main area with tabs) maps cleanly.
- **PEP 723 compatible**: Can run as a single file via `uv run`.

**Weaknesses:**
- **Smaller community**: ~12K GitHub stars vs Streamlit's ~40K. Fewer tutorials, Stack Overflow answers, and third-party components.
- **AG Grid enterprise features unavailable**: Server-side pagination and some advanced AG Grid features require the enterprise license, which NiceGUI doesn't include.
- **mount_path issues reported**: Some users report problems when NiceGUI is mounted at a non-root path (resource loading from `/_nicegui/` ignores the prefix). This is a known issue that may affect the plugin use case.
- **Learning curve slightly higher**: While still Python-only, the component model (Vue.js-based Quasar under the hood) requires understanding event handlers and binding, unlike Streamlit's linear script model.
- **Design doc would need rewriting**: The jtbl design doc specifies Streamlit + Ace. Switching to NiceGUI means updating the design doc, changing component references, and adopting a different mental model.

**Plugin integration (FastAPI):**
```python
from nicegui import ui
from fastapi import FastAPI

app = FastAPI()

@ui.page("/tools/jtbl")
def jtbl_page():
    ui.label("jtbl 2.0")
    # ... full UI here

ui.run_with(app, mount_path="/tools/jtbl", storage_secret="dev-toolkit")
```
This is NiceGUI's primary integration pattern — mature and well-documented.

### 3. Panel (HoloViz) — STRONG BUT COMPLEX

**Strengths:**
- **Tabulator widget**: Best-in-class data table widget with sorting, filtering, editing, streaming, and virtual scrolling. Handles large datasets well.
- **FastAPI integration**: Native since Panel 1.5.0 via `add_application()`. Mature and documented.
- **Flexible layout**: Row/Column/GridSpec layouts with sizing modes. More layout control than Streamlit.
- **Jupyter compatible**: Works in notebooks and standalone. Good for data scientists.
- **NumFOCUS project**: Well-funded, stable governance.

**Weaknesses:**
- **Steeper learning curve**: Panel's Param-based reactive model is more complex than Streamlit's script model.
- **No built-in code editor**: Would need a custom Ace/CodeMirror integration.
- **JSON tree viewer**: No built-in JSON tree component. Would need a custom implementation.
- **Bokeh dependency**: Heavy dependency chain. The Bokeh server adds complexity.
- **Performance with many columns**: Known issues (GitHub #2327) with Tabulator slowing down with many columns.
- **Smaller community**: ~5K GitHub stars. Documentation can be sparse for advanced use cases.

**Verdict**: Panel excels at dashboards with complex data visualizations, but jtbl needs a code editor + JSON tree + data table combination that Panel doesn't provide out of the box.

### 4. Gradio — WRONG FIT

**Strengths:**
- **Simple function→UI model**: Define inputs and outputs, Gradio builds the UI.
- **gr.JSON**: Built-in JSON tree viewer.
- **gr.Dataframe**: Built-in data table.
- **FastAPI mount**: `gr.mount_gradio_app()` works for basic embedding.

**Weaknesses:**
- **ML-demo focused**: Gradio is designed for "input → model → output" demos, not interactive workbenches with live query editing.
- **Limited layout control**: The Blocks API helps, but complex layouts like jtbl's sidebar + tabbed main area + row inspector are awkward.
- **No code editor component**: Would need a custom component for the jq expression editor.
- **Web component embedding broken**: Known issue (#5161) — mounted Gradio apps can't be embedded as web components.
- **100MB+ install**: Heaviest of all options.

**Verdict**: Gradio is excellent for ML demos but wrong for an interactive data exploration workbench.

### 5. Solara — PROMISING BUT IMMATURE

**Strengths:**
- **React-like component model**: Pure Python implementation of React (via Reacton). No re-run model.
- **Built on FastAPI**: Native ASGI integration.
- **Jupyter + standalone**: Works in both contexts.

**Weaknesses:**
- **Small community**: ~2K GitHub stars. Limited documentation and examples.
- **No AG Grid or advanced table**: Basic DataFrame display only.
- **No code editor component**: Would need custom integration.
- **No JSON tree component**: Would need custom implementation.
- **Immature**: Too early for production use in a tool like jtbl.

**Verdict**: Watch for the future, but too immature today.

### 6. Reflex — WRONG ARCHITECTURE

**Strengths:**
- **Full-stack Python**: Compiles to Next.js. Full control over UI.
- **Great performance**: Sub-50ms reactivity, scales well.
- **Tailwind + full CSS**: Complete styling control.

**Weaknesses:**
- **Compilation step**: Requires compiling Python to JavaScript. Breaks the "zero install, `uv run`" requirement.
- **Heavy**: 200MB+ install size. Not single-file friendly.
- **Cannot be embedded**: Runs as a standalone Next.js app. No FastAPI mount capability.
- **Overkill**: Full-stack framework for what is essentially a data exploration widget.

**Verdict**: Wrong architecture entirely. Reflex is for building full web applications, not embeddable data tools.

### 7. Dash (Plotly) — VIABLE BUT HEAVY

**Strengths:**
- **dash-ag-grid**: Official AG Grid wrapper. Best AG Grid integration of any Python framework.
- **Mature**: 22K GitHub stars, Plotly-backed.
- **Strong data visualization**: If jtbl ever needs charts, Plotly integration is native.

**Weaknesses:**
- **Flask-based**: Synchronous, callback model. No native WebSocket.
- **Verbose**: Layout requires explicit HTML-like component trees. Not single-file friendly.
- **Cannot mount in FastAPI**: Runs its own Flask server. Would need a separate process for plugin mode.
- **Callbacks are complex**: The callback model for live preview (type → update) requires careful debouncing and state management.

**Verdict**: Dash is strong for enterprise dashboards but too heavy and too Flask-dependent for jtbl's requirements.

---

## The Plugin Question: Standalone vs Embedded

This is the critical architectural decision. jtbl must work in two modes:

### Mode 1: Standalone (`uv run jtbl-ui.py`)
All frameworks handle this well. PEP 723 metadata lists the framework as a dependency, `uv run` installs and launches it.

### Mode 2: Plugin (mounted inside Dev Toolkit FastAPI server)

| Framework | Mount Method | Maturity | Caveats |
|-----------|-------------|----------|---------|
| **Streamlit** | `api.mount("/jtbl", App("jtbl-ui.py"))` | Experimental (v1.53+) | ASGI support is new; Tornado→Starlette migration ongoing |
| **NiceGUI** | `ui.run_with(app, mount_path="/jtbl")` | Production-ready | Known issues with non-root mount paths and `/_nicegui/` resource loading |
| **Panel** | `add_application("/jtbl", panel_app)` | Production-ready (v1.5+) | Bokeh server adds complexity; WebSocket path configuration needed |
| **Gradio** | `gr.mount_gradio_app(app, demo, "/jtbl")` | Stable but limited | Web component embedding is broken; layout constraints |
| **Solara** | Native FastAPI | Theoretically clean | Immature; untested at scale |
| **Reflex** | Not possible | N/A | Compiles to standalone Next.js |
| **Dash** | Not possible (Flask) | N/A | Separate process required |

**Key insight**: Only Streamlit (experimental), NiceGUI (production), Panel (production), and Gradio (limited) can be mounted inside a FastAPI application. Of these, NiceGUI has the most natural FastAPI integration because it IS a FastAPI application.

---

## Performance for Data-Heavy UIs

### Data Table Rendering (10K+ rows)

| Framework | Component | Virtual Scrolling | Performance |
|-----------|-----------|-------------------|-------------|
| **Streamlit** | streamlit-aggrid | Yes (AG Grid) | Excellent — only renders visible rows |
| **Streamlit** | st.dataframe | Yes (Arrow) | Good — built-in, optimized for large DataFrames |
| **NiceGUI** | ui.aggrid | Yes (AG Grid) | Excellent — same AG Grid, but enterprise features locked |
| **Panel** | Tabulator | Yes | Good — but known slow with many columns |
| **Dash** | dash-ag-grid | Yes (AG Grid) | Excellent — official AG Grid wrapper |
| **Gradio** | gr.Dataframe | Limited | Adequate for small-medium datasets |

For jtbl's use case (JSON exploration, typically hundreds to low thousands of rows), all options are adequate. The AG Grid-based solutions (Streamlit-aggrid, NiceGUI, Dash) handle the 10K+ case best.

### Live Preview Latency (keystroke → table update)

| Framework | Mechanism | Typical Latency |
|-----------|-----------|-----------------|
| **Streamlit** | Full script re-run + cache | 200-500ms (with @st.cache_data) |
| **NiceGUI** | WebSocket push, incremental | 50-100ms |
| **Panel** | Param watching | 100-200ms |
| **Gradio** | Event callback | 100-300ms |

NiceGUI's WebSocket model provides the fastest perceived response because it doesn't re-run the entire script. For jtbl, where the user types a jq expression and expects to see results, this matters for UX quality.

---

## Recommendation

### Primary: Streamlit (maintain design doc default)

**Rationale:**
1. **Design doc already specifies Streamlit**: The jtbl 2.0 design doc explicitly calls out Streamlit + Ace. Changing frameworks means rewriting the design doc and the packaging model.
2. **PEP 723 + `uv run` is proven**: The single-file, zero-install model works perfectly with Streamlit.
3. **Component coverage is sufficient**: st.dataframe/streamlit-aggrid for tables, st.json for JSON tree, streamlit-ace for code editing.
4. **ASGI mount is coming**: Streamlit 1.53+ experimental ASGI support enables FastAPI plugin integration. By the time the Dev Toolkit (Issue #55) is ready, this should be more stable.
5. **Largest community**: More components, more documentation, more Stack Overflow answers.
6. **Lowest risk**: The design doc is written for Streamlit. Stick with it unless a blocking issue is found during implementation.

### Secondary: NiceGUI (if Streamlit becomes a hard blocker)

The design doc's Principle #4 says: "Revisit only if Streamlit becomes a hard blocker."

NiceGUI would be the replacement if:
- Streamlit's ASGI mount proves too unreliable for plugin mode
- The re-run model causes unacceptable latency for live jq preview
- The layout constraints prevent implementing the design doc's UI
- Custom theming to match the Dev Toolkit becomes a requirement

NiceGUI's advantages (no re-run, native FastAPI, built-in AG Grid + CodeMirror + JSON editor, Tailwind) make it the strongest alternative. Its main weakness is the smaller community.

### Not Recommended

| Framework | Reason |
|-----------|--------|
| **Panel** | Missing code editor and JSON tree; complex Bokeh dependency |
| **Gradio** | ML-demo focused; no code editor; broken web component embedding |
| **Solara** | Too immature; missing key components |
| **Reflex** | Cannot embed in FastAPI; requires compilation; breaks `uv run` model |
| **Dash** | Cannot mount in FastAPI; Flask-based; verbose layout model |

---

## Implementation Notes for the Planner

### If Using Streamlit (recommended)

1. **Code editor**: Use `streamlit-code-editor` (actively maintained) over `streamlit-ace` (stale). Both wrap Ace/react-ace.
2. **Data table**: Start with `st.dataframe` (built-in). Switch to `streamlit-aggrid` only if row selection or column resizing is needed.
3. **JSON tree**: `st.json(data, expanded=2)` covers the row inspector. For the Tree Explorer tab, a custom component or `st.json` with interactive path input may suffice.
4. **Live preview**: Use `@st.cache_data` aggressively. Cache the parsed JSON and jq results. Debounce the code editor input.
5. **Plugin mode**: Depend on Streamlit 1.53+ ASGI support. Build standalone first; add plugin mount later.
6. **PEP 723 deps**: `streamlit>=1.53`, `streamlit-code-editor>=0.1`, `pandas>=2.0`, `tabulate>=0.9`.

### If Switching to NiceGUI

1. **Code editor**: `ui.codemirror(language='json')` for jq expression editing.
2. **Data table**: `ui.aggrid()` with column definitions derived from projected rows.
3. **JSON tree**: `ui.json_editor()` for the Tree Explorer tab. `ui.tree()` for navigation.
4. **Live preview**: Bind code editor value change to a handler that re-runs jq and updates the table.
5. **Plugin mode**: `ui.run_with(fastapi_app, mount_path="/tools/jtbl")`.
6. **PEP 723 deps**: `nicegui>=2.0`, `pandas>=2.0`, `tabulate>=0.9`.

---

## Open Questions

1. **Streamlit ASGI stability**: How stable is the v1.53+ experimental ASGI mount? Should the planner build a fallback (iframe embedding) in case it doesn't work reliably?
2. **Ace vs CodeMirror**: The design doc specifies Ace. If using Streamlit, `streamlit-code-editor` (Ace) is available. If switching to NiceGUI, CodeMirror is built-in. Is there a jq-specific syntax mode for either?
3. **JSON tree interactivity**: The design doc specifies breadcrumb navigation and click-to-drill-in. Neither st.json nor ui.json_editor provides this out of the box. A custom component may be needed regardless of framework.
4. **Theming**: If the Dev Toolkit has a specific visual theme, NiceGUI (Tailwind) gives much more control than Streamlit (limited theming API).

---

## Sources

- [Streamlit docs: st.json](https://docs.streamlit.io/develop/api-reference/data/st.json)
- [Streamlit docs: embedding](https://docs.streamlit.io/deploy/streamlit-community-cloud/share-your-app/embed-your-app)
- [Streamlit 1.53 ASGI support](https://github.com/streamlit/streamlit/issues/13600)
- [Streamlit 2026 release notes](https://docs.streamlit.io/develop/quick-reference/release-notes/2026)
- [streamlit-aggrid](https://github.com/PablocFonseca/streamlit-aggrid)
- [streamlit-code-editor](https://github.com/bouzidanas/streamlit-code-editor)
- [streamlit-ace](https://github.com/okld/streamlit-ace)
- [NiceGUI documentation](https://nicegui.io/documentation)
- [NiceGUI AG Grid](https://nicegui.io/documentation/aggrid)
- [NiceGUI CodeMirror](https://nicegui.io/documentation/codemirror)
- [NiceGUI JSON editor](https://nicegui.io/documentation/json_editor)
- [NiceGUI FastAPI integration](https://github.com/zauberzeug/nicegui/blob/main/examples/fastapi/main.py)
- [NiceGUI root_path issue](https://github.com/zauberzeug/nicegui/issues/848)
- [Panel Tabulator](https://panel.holoviz.org/reference/widgets/Tabulator.html)
- [Panel FastAPI integration](https://panel.holoviz.org/how_to/integrations/FastAPI.html)
- [Gradio mount_gradio_app](https://www.gradio.app/docs/gradio/mount_gradio_app)
- [Gradio web component issue](https://github.com/gradio-app/gradio/issues/5161)
- [Solara](https://solara.dev/)
- [Reflex](https://reflex.dev/)
- [Dash AG Grid](https://dash.plotly.com/dash-ag-grid)
- [Streamlit vs NiceGUI comparison](https://www.bitdoze.com/streamlit-vs-nicegui/)
- [Python framework survey (Ploomber)](https://ploomber.io/blog/survey-python-frameworks/)
- [Streamlit vs Gradio (Squadbase)](https://www.squadbase.dev/en/blog/streamlit-vs-gradio-in-2025-a-framework-comparison-for-ai-apps)
