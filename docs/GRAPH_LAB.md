# Graph Lab (experimental)

An in-app workspace for authoring [Tier C multipass graphs](MULTIPASS_GRAPH.md): compose nodes from the WGSL entries in the catalog, see their dependencies, copy barriers and pass cost, see validator errors **before** anything runs, run the draft in the live renderer, and export a shader definition the existing registry build already understands.

It adds no graph schema, no bind-group bindings and no execution path. The graph is the renderer's own `MultipassGraphDef`; the errors are the frame planner's own; running goes through the same planner, pass budgets, truncation and color-writer rules as a shipped graph. TS/WebGPU only — the frozen C++ WASM backend is untouched.

## Turning it on

Add `?graphlab` to the URL (`?graphlab=0` turns it off). The choice is remembered in `localStorage` (`vj_graphlab_enabled`). A **Graph Lab** button appears at the bottom left; the workspace is a lazy `graph-lab` chunk, so nothing but that button ships in `main.js`.

The Lab is a side panel, not a tab: switching tabs unmounts the canvas and destroys the renderer, and the Lab needs the live renderer.

## Workflow

1. **Start.** The Lab opens on a copy of the `wave-tank` flagship (`wave-tank-lab`), a graph that validates and runs. *Start from…* copies another shipped graph (saved under `<id>-lab`, so exporting never silently replaces it), *Import* takes a shader-definition JSON (or a bare `{ maxPassesPerFrame, nodes }`), *New* starts empty. The draft is autosaved to `localStorage`.
2. **Compose.** Nodes are listed in execution order; the array order *is* the order the passes run in. Add a node by searching entries; reorder, duplicate or remove with the buttons. For the selected node you can set:
   - its entry (a WGSL file stem under `public/shaders/`);
   - reads `read, dataA, dataB, dataC` and writes `color, dataA, dataB` — the roles with defined behaviour (see [Texture roles](MULTIPASS_GRAPH.md#texture-roles)); with the sim ring on, also reads `simState, simIndex` and writes `simState`;
   - `repeat` (1–64);
   - `scalable` + `minScale` (per-node resolution scaling);
   - its dispatch domain, `pixels` or `simState` (sim ring on only; a `simState` node cannot be scalable);
   - the graph's `maxPassesPerFrame` ceiling.

   The pass budget is the planner's: `min(graph.maxPassesPerFrame, policy.maxPassesPerFrame)`, shown per policy under *Cost*.

   Roles outside that set that arrive in an imported graph are kept as they are and shown dashed.
3. **Sim ring.** *Use the group-1 sim ring* writes the definition's `simRing` request (`stateCount` from the OOM ladder, 65,536 / 32,768 / 16,384 / 4,096; other `simRing` fields such as `agent` are kept). It cannot be switched off while a node still uses a sim role or a `simState` dispatch. The section states the contract: `simState` + its `simIndex` snapshot (16 B per element each), bound only to entries whose WGSL declares `@group(1)`, and that `?renderer=wasm` refuses the shader. See [How the sim ring is armed](#how-the-sim-ring-is-armed).
4. **Read the analysis.**
   - *Diagnostics* — every error and warning from `diagnoseGraph` with its code: `dependency`, `cycle`, `missing-entry`, `pass-budget`, … Repeated per-iteration messages are folded into one line.
   - *Dependencies* — each expanded dispatch, where each read comes from (`source image`, `previous frame`, `dataA → dataC (step#2)`, a node dispatch), and the copy barriers the planner inserts before it.
   - *Cost* — passes and copy barriers per node, and for each quality policy (battery / balanced / ultra / auto low-end, mobile, desktop) how many passes run, how many are cut, whether the display pass survives, and the frame budget. While running it adds per-node GPU ms.
5. **Run.** *Run in slot N* registers the draft as a runtime graph and binds it to the active slot. Edits apply live as long as the graph validates; if an edit makes it invalid, the last valid graph keeps running and the error stays on screen. The live line shows the planner's report (`live: 4 / 5 passes · 1 truncated (cap 4)`). *Stop*, closing the Lab, or the slot being taken over by another shader releases it; the previous shader comes back unless you already picked another one.
6. **Export.** *Download* or *Copy* the definition. Export is blocked while any error diagnostic exists, if the id is not a valid catalog id, collides with an existing shader, or is the reserved `graphlab-draft`.

Run is disabled (with the reason on hover) for an empty graph and a graph with errors; an invalid draft is never registered or compiled.

## v2: canvas, undo/redo, ports from the WGSL (#1451, slice 1)

### Node canvas

Above the node list is a [React Flow 12](https://reactflow.dev) canvas (`@xyflow/react`), its own lazy chunk `graph-lab-canvas` inside the lazy Lab, so neither `main.js` nor the Lab panel chunk carries it (`verify:bundle-size` lists both as lazy). *Expand* puts it over the stage, *Auto layout* forgets the stored positions.

- **Nodes** are the graph's nodes. The number is the execution order, which is still the node array order: dragging moves a node on the canvas and never reorders passes (use the list's ↑ ↓).
- **Ports** are the roles. A chip is plain when it is in the graph (and the WGSL agrees), struck through in orange when the graph has it but the WGSL never binds it, and dim when the WGSL binds it but the graph does not. Click a dim chip to add the role.
- **Edges** are derived, not stored: `graphEdges.ts` walks the planner's own `expandGraph` and connects each read to the node that last wrote that role. A `dataC` / `simIndex` read is drawn from the `dataA`/`dataB` / `simState` writer with the copy barrier as its label. A read only the previous frame satisfies is dashed and animated. A node that reads its own output (a `repeat` chain, a ping-pong sim) gets a `↺ role` tag instead of a loop. **source image** and **display** stand for `read` and `color`.
- **Drawing an edge** from an output port to an input port makes sure the source writes that role and the target reads it (`source image → node` adds `read`, `node → display` adds `color`). Deleting a selected node (Delete / Backspace) removes it.
- Positions live in the draft (`layout`, keyed by node id), follow a rename or a duplicate, and are never exported. The renderer never sees them.

Without `ResizeObserver` (jsdom) the canvas is not offered; the list view does everything the canvas does.

### Undo / redo

↶ ↷ in the toolbar, Ctrl/Cmd+Z and Ctrl/Cmd+Shift+Z (or Ctrl+Y) outside text fields, where the field's own undo applies. Every edit is a pure function returning a new draft, so history (`draftHistory.ts`) is a stack of up to 100 snapshots, with no patch library. Rapid edits to the same field (typing an id, a repeat count, the pass ceiling, export metadata) fold into one step. *New*, *Start from…* and *Import* are undoable too. The present draft is what is autosaved.

### Ports from the WGSL (naga reflection)

The Lab no longer guesses which entries use the sim ring. `tools/naga_wasm` has a third export, `wgsl_reflect`, which returns every `@group/@binding` global (resource kind, access, texture dimension) and, for each entry point, the bindings it reaches with naga's `GlobalUse` read/write flags. `portInference.ts` runs it on the include-expanded same-origin WGSL (`fetchShaderWgsl`, so `_prelude.wgsl`'s 13 bindings are expanded but only the used ones count) and maps bindings to roles: 1 → `read`, 2 → `color`, 7 → `dataA`, 8 → `dataB`, 9 → `dataC`, 13 → history ring, `@group(1)` 0 → `simState` (read and/or write), 1 → `simIndex`. One reflection per entry per page.

- The **Sim ring** section lists the draft's entries that declare `@group(1)`: the only entries the renderer arms and binds the ring for.
- **Node settings** shows the selected entry's WGSL ports, workgroup size, and port warnings. A sim role or `simState` dispatch on an entry without `@group(1)` is the case v1 could not see. The others are a role the graph reads or writes that the WGSL never binds. Warnings are advisory: the planner's diagnostics still gate Run and Export.
- **Adding a node** uses the inferred roles: what the WGSL reads and writes, minus `color` when another node already writes it, with a `simState` dispatch for a `simState` writer with a 1-D workgroup. A sim role arms the sim ring in the same undo step. An entry whose WGSL cannot be read gets the v1 defaults.
- A module that parses but does not validate under naga (see the `knownFailures` ratchet) reports its *declared* bindings and is tagged *declared only*.

### Draft v2

`GraphDraft` now carries `version: 2` and `layout`. It is stored under `graphlab.draft.v2`, and a v1 draft (`graphlab.draft.v1`) is upgraded on first load. `upgradeDraft` refuses a draft from a newer version rather than dropping its fields.

### Not in this slice

Drafts in project files (#1438) and device-loss restore (#1430) were listed on #1451 (now closed) and are not part of this slice. Inline WGSL / params editing, one draft per slot and "Save as shader" shipped with #1513 Part B: see [WGSL editor](#wgsl-editor-1513-part-b). Part B of that list (HDR `rgba16float`, `shader-f16`, `bgra8unorm-storage`, `featureLevel: 'compatibility'`, `float32-blendable`) shipped with rendering tier 2 (#1512, [DEVICE_FEATURES.md](DEVICE_FEATURES.md)).

## WGSL editor (#1513 Part B)

*WGSL editor* (below *Node settings*) edits one compute shader per slot, validates it with naga as you type and hot-swaps it into the slot. CodeMirror 6 is its own lazy chunk, `graph-lab-editor`, inside the lazy Lab (`verify:bundle-size` lists it); it and the naga artifact load the first time the section is opened.

### Writing a draft

A draft is plain catalog WGSL: `#include "_prelude.wgsl"` for the 13 bindings (never paste them; Save refuses a pasted header) and `@compute @workgroup_size(…) fn main(…)`. *Template* puts back the starter shader. Other `_`-libraries (`_hash.wgsl`, …) can be included too; they are fetched same-origin, the prelude comes from the bundle.

The sliders are a comment block, one pragma per slider, in order p1–p4 (`u.zoom_params.x…w`):

```wgsl
// @param speed 0 4 1 Speed
// @param warp  0 1 0.3
```

`name min max default [label]`. The label defaults to the humanized name (`warpAmount` → *Warp Amount*). A malformed pragma, `min ≥ max`, a default out of range, a duplicate or a fifth one is an error on its line. Comment pragmas, not a WGSL `const` block, so the sliders keep working while the code does not validate and nothing changes at runtime.

### Diagnostics

150 ms after the last keystroke the text is include-expanded with the build's own expander (`src/wasm/bridge/wgslInclude.ts`, the same code `fetchShaderWgsl` and `verify:naga-wasm` run) and validated by the committed naga-wasm (`src/utils/nagaWasm.ts`). `wgslSourceMap.ts` maps naga's line in the expanded module back to the user's line, so an error never lands on a prelude line: an error inside an included library is shown on its `#include` line as `in _lib.wgsl:N (included here): …`. A clean module must also reflect a `@compute fn main`. Errors show in the gutter (`@codemirror/lint`), underlined at naga's span, and the first one in the banner. A result that finishes after a newer keystroke is dropped. Measured on SwiftShader: ~160 ms from the last keystroke to the marker.

Autocomplete (`wgslCompletions.ts`) is generated from the prelude source: the 13 bindings with their `@group/@binding`, `u.config`, `u.zoom_config`, `u.zoom_params`, `u.ripples` and each `.x/.y/.z/.w` lane with the prelude's contract note, the `fn`s of every included library, the draft's own `@param`s as `u.zoom_params.*`, and WGSL keywords, types and builtins. A regenerated prelude changes the completions with it.

### Running

*Run WGSL in slot N* compiles the include-expanded module (no include is left for the GPU to resolve) through `RendererManager.loadShader` from a `blob:` URL, in either render thread, and binds the slot; the sliders drive `setSlotParams`. From then on every clean validate is hot-swapped (`WgslDraftRunner`, `runDraft.ts`):

- Each slot has two runtime ids, `graphlab-wgsl-<slot>-a|b`. The next text compiles under the one that is not bound, and the slot is switched only after that compile succeeds. An invalid edit (naga) never reaches the GPU; one naga accepts but the GPU rejects keeps the old pipeline too, with *the last good one keeps running*. Nothing is bound before the first good compile, so starting never shows a black frame.
- Texts typed while one compiles are queued latest-wins: the intermediate ones are never compiled.
- *Stop* or closing the Lab puts the previous shader back, unless the slot was taken by another shader meanwhile. Running a WGSL draft stops the graph draft in that slot and vice versa.

`fetchShaderWgsl` now treats a `text/html` answer as "not here": the Vite dev server answers a missing `./shaders/<id>.wgsl` with `index.html`, which would otherwise shadow the draft's `blob:` URL (and any shader only the caller URL serves).

### Drafts

One draft per slot (id, name, category, description, source), autosaved to `localStorage` (`graphlab.wgsl.v1`); the editor shows the active slot's. Text undo / redo is the editor's own (Ctrl/Cmd+Z inside it). Keys typed in the editor do not reach the app's window shortcuts (Space, `a`, `g`, `r`, digits). Drafts are not in project files: that waits for Part A's project-file schema v3.

### Save as shader

*Save as shader…* writes

- `public/shaders/<id>.wgsl`: the draft as typed, prelude-included, `@param` block and all;
- `shader_definitions/<category>/<id>.json`: `id`, `name`, `url`, `category`, `description`, `features`/`tags: ["graph-lab"]`, and `params` from the pragmas (`mapping: zoom_params.x…`).

It is enabled only when the current text has a clean naga result, the id is a valid catalog id that is not taken (nor a `graphlab-*` runtime id), and the prelude is included and not pasted. With the File System Access API (Chromium) you pick the repository folder (it must hold `public/shaders` and `shader_definitions`; existing files are never overwritten); elsewhere you get two downloads to move there. `npm start` / `npm run build` then list it like any other shader. The output passes `verify:shader-definitions`, `verify:naga-wasm`, `verify:wgsl-include` and `verify:prelude-migration` (`wgslSave.gates.test.ts` runs those checks on a saved sample). Saving is local only: a storage submit waits for the storage_manager upload-token receiver.

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

### How the sim ring is armed

The Lab adds no binding and no allocation path. A sim draft's `{ stateCount }` travels with the graph (`setRuntimeGraph(id, graph, simRing)`, to both realms), and the generated `resolveSimRingRequest` answers it for `graphlab-draft` and every entry of the draft. From there it is the shipped path: `WebGPURenderer.loadShader` compiles an entry, and only if its WGSL declares `@group(1)` does it get the two-layout pipeline and call `SimRing.ensure` with that request (OOM ladder, session cap). The frame planner binds group 1 only for those entries (`bindSimRing`). An entry without `@group(1)` keeps the group-0 pipeline whatever the toggle says; a `simState` dispatch of it runs over the element count once some group-1 entry has armed the ring, and is skipped (with a warning) until then.

`SimRing.ensure` runs on compile, so *Run* recompiles every entry of a sim draft (re-seeding the ring at `frame 0`), and so does a change of the element count while running. Other edits keep the ring running. The ring keeps its largest allocation for the session, like a shipped sim shader's.

## Limits

- **Sim ring:** an entry's `@group(1)` declaration is read from its WGSL (v2), but the ring is still a per-draft toggle; a draft whose entries never declare it runs without the ring (its `simState` dispatches are skipped). `?renderer=wasm` refuses sim-ring shaders (the C++ backend has one bind group).
- One running graph draft at a time, in the active slot; one running WGSL draft at a time.
- The WGSL editor edits a single-pass shader; it is not (yet) an entry of the graph draft.
- WGSL highlighting is a stream parser (no Lezer grammar, so no folding).
- Entries come from the shader catalog, the entries of registered graphs and Tier B chain passes. An entry that exists as a file but in none of those can be typed only while the catalog is still loading.

## Tests

```bash
npx vitest run src/graphLab src/components/graphLab src/renderer/multipassGraph src/renderer/runtimeGraphs src/renderer/worker
npm run build && npm run test:engine2 -- tests/graph-lab.swiftshader.spec.ts
```

WGSL editor: the debounce contract runs with fake timers and a stub validator (`wgslDiagnostics.test.ts`: the last keystroke's error is on the right user line at 300 ms), the line remap and messages with the real naga artifact (`wgslDiagnostics.naga.test.ts`), the hot-swap rules against a fake renderer (`runWgslDraft.test.ts`), the editor itself with real naga in jsdom (`WgslDraftSection.test.tsx`), and the saved files through the CI gate scripts (`wgslSave.gates.test.ts`). The e2e's *inline WGSL draft* test validates the template with naga in the browser, runs it in both render threads, types an error (marker on the right line, timed in the page), checks the same pipeline is still bound and the read-back frame is not blank, then fixes it and sees it hot-swapped.

Unit coverage for the issue's contract: an illegal read never reaches `loadShader` (`runDraft.test.ts`, `GraphLabPanel.test.tsx`); a Lab-edited `repeat` expands to the same frame-plan dispatches as the same `repeat` in JSON, and a sim-ring toggle on group-0 entries never sets `bindSimRing` (`runtimeGraphs.test.ts`).

The e2e registers a draft of the shipped `predator-prey-ecology` step → render graph in both render threads and asserts the planner's report, the pass budgets (battery cap, frame budget of one pass keeping the display pass), the refusal of a broken draft, and pixels read back through the renderer. `test:engine2` is not part of CI.
