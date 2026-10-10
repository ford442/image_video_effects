# Graph Lab (experimental)

An in-app workspace for authoring [Tier C multipass graphs](MULTIPASS_GRAPH.md): compose nodes from the WGSL entries in the catalog, see their dependencies, copy barriers and pass cost, see validator errors **before** anything runs, run the draft in the live renderer, and export a shader definition the existing registry build already understands.

It adds no graph schema, no bind-group bindings and no execution path. The graph is the renderer's own `MultipassGraphDef`; the errors are the frame planner's own; running goes through the same planner, pass budgets, truncation and color-writer rules as a shipped graph. TS/WebGPU only — the frozen C++ WASM backend is untouched.

## Turning it on

Add `?graphlab` to the URL (`?graphlab=0` turns it off). The choice is remembered in `localStorage` (`vj_graphlab_enabled`). A **Graph Lab** button appears at the bottom left; the workspace is a lazy `graph-lab` chunk, so nothing but that button ships in `main.js`.

The Lab is a side panel, not a tab: switching tabs unmounts the canvas and destroys the renderer, and the Lab needs the live renderer.

## Workflow

1. **Start.** *Start from…* copies a shipped graph (saved under `<id>-lab`, so exporting never silently replaces it), *Import* takes a shader-definition JSON (or a bare `{ maxPassesPerFrame, nodes }`), *New* starts empty. The draft is autosaved to `localStorage`.
2. **Compose.** Nodes are listed in execution order; the array order *is* the order the passes run in. Add a node by searching entries; reorder, duplicate or remove with the buttons. For the selected node you can set:
   - its entry (a WGSL file stem under `public/shaders/`);
   - reads `read, dataA, dataB, dataC` and writes `color, dataA, dataB` — the roles with defined behaviour (see [Texture roles](MULTIPASS_GRAPH.md#texture-roles));
   - `repeat` (1–64);
   - `scalable` + `minScale` (per-node resolution scaling);
   - the graph's `maxPassesPerFrame` ceiling.

   Roles outside that set that arrive in an imported graph are kept as they are and shown dashed.
3. **Read the analysis.**
   - *Diagnostics* — every error and warning from `diagnoseGraph` with its code: `dependency`, `cycle`, `missing-entry`, `pass-budget`, … Repeated per-iteration messages are folded into one line.
   - *Dependencies* — each expanded dispatch, where each read comes from (`source image`, `previous frame`, `dataA → dataC (step#2)`, a node dispatch), and the copy barriers the planner inserts before it.
   - *Cost* — passes and copy barriers per node, and for each quality policy (battery / balanced / ultra / auto low-end, mobile, desktop) how many passes run, how many are cut, whether the display pass survives, and the frame budget. While running it adds per-node GPU ms.
4. **Run.** *Run in slot N* registers the draft as a runtime graph and binds it to the active slot. Edits apply live as long as the graph validates; if an edit makes it invalid, the last valid graph keeps running and the error stays on screen. The live line shows the planner's report (`live: 4 / 5 passes · 1 truncated (cap 4)`). *Stop*, closing the Lab, or the slot being taken over by another shader releases it; the previous shader comes back unless you already picked another one.
5. **Export.** *Download* or *Copy* the definition. Export is blocked while any error diagnostic exists, if the id is not a valid catalog id, collides with an existing shader, or is the reserved `graphlab-draft`.

Run is disabled (with the reason on hover) for an empty graph, a graph with errors, and sim-ring graphs.

## Installing an export

1. Save the JSON at the path the Lab shows, `shader_definitions/<category>/<id>.json`. The folder is the catalog category.
2. `node scripts/buildMultipassRegistry.js` (also part of `npm start` and `npm run build`) copies `multipass.graph` verbatim into `GRAPH_REGISTRY`. Nothing is translated: the exported graph is the draft's graph.
3. `node scripts/generate_shader_lists.js` (same scripts) lists it in the catalog. `url` is the first node's WGSL, or — for a graph imported from a definition — the original `url` while it still names a node entry.

Things the export tells you about:

- **Catalog shaders used as entries disappear from the lists.** `generate_shader_lists.js` treats every graph `entry` that is not the graph's own id as a *secondary* and skips a catalog shader with that id. The export warns per entry.
- **Drift audit.** Entries without their own definition show up in `audit_catalog_consistency.py`; refresh the baseline with `python3 scripts/audit_catalog_consistency.py --ensure-lists --write-baseline`.
- **Params.** A graph started from scratch exports no `params`, so the four `zoom_params` sliders are not listed; add them by hand if the entries read them. A graph started from a shipped one keeps its definition fields exactly as they were.
- A graph started from scratch gets `description`, `features`, `tags` and `requiresRgba32Float` (when it uses `dataA/B/C`); an imported or forked definition is exported unchanged apart from its graph.

## How running works

`src/renderer/runtimeGraphs.ts` is an overlay on the generated registry (see [Runtime graphs](MULTIPASS_GRAPH.md#runtime-graphs)). The Lab:

1. registers a fresh copy of the draft's graph as `graphlab-draft` (`RendererManager.setRuntimeGraph`, which also sends a `setRuntimeGraph` command to the render worker, which has its own registry copy);
2. compiles the first entry's WGSL under `graphlab-draft` (the planner only schedules slots that have a pipeline) and every entry not yet compiled;
3. binds the slot with `setSlotShader`.

Each frame the planner resolves `graphlab-draft` like any other graph. Fresh graph objects are essential: plans are memoised per object.

## Limits in v1

- **Sim-ring graphs** (`simState` / `simIndex` roles, `dispatch: "simState"`, `simRing` field) are view-only: they are shown, validated and exported unchanged, but not edited or run. They need the group-1 ring armed from a definition.
- One running draft at a time, in the active slot.
- No undo/redo, no free-form canvas, no editing of `params` or WGSL.
- Entries come from the shader catalog, the entries of registered graphs and Tier B chain passes. An entry that exists as a file but in none of those can be typed only while the catalog is still loading.

## Tests

```bash
npm test -- --watchAll=false --ci src/graphLab src/components/graphLab src/renderer/multipassGraph src/renderer/runtimeGraphs src/renderer/worker
SKIP_WASM_BUILD=1 npm run build && npm run test:engine2 -- tests/graph-lab.swiftshader.spec.ts
```

The e2e registers a draft of the shipped `predator-prey-ecology` step → render graph in both render threads and asserts the planner's report, the pass budgets (battery cap, frame budget of one pass keeping the display pass), the refusal of a broken draft, and pixels read back through the renderer. `test:engine2` is not part of CI.
