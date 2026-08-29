# image_video_effects — 2026-08-29 dispatch

**Status:** #1126 (stop second WebGPU devices) shipped + merged + closed; the 08-24 red CI gate is green again. Today = **#1180 TS/C++ workgroup fallback + empty-placeholder packing parity**. Plan updated, PR #1193 open.

## Mode declaration

**User Idea mode.** Noah ran a fresh **2026-08-26 progress audit** that closed the entire 2026-08-21 set (#1123–#1129) and opened a new one (#1179–#1185); per standing precedent that set is the live Ideas source. Picked **#1180** — the only labeled `bug`, foundation-tagged, parts A+B fully headless-self-verifiable, and it closes the last dispatch/upload divergence left by the #1107 → #1126 device-discipline arc. Foundation is healthy → **not Fix First**.

## Context from prior sessions

- **Last week's focus #1126 SHIPPED + MERGED + CLOSED.** Verified on `main` @ `a27a627`: `src/utils/adoptedGpuDevice.ts` landed; `src/utils/requestPixelocityDevice.ts` **deleted** (the stronger of the two options the plan allowed); `RendererManager.getDevice()` at `:305`, facade **353 LOC**; `depthEstimation/loader.ts:28` carries the "Never call requestAdapter() here — the renderer owns the sole adapter/device" contract comment. A full `src/**` grep returns **zero** live `requestAdapter`/`requestDevice` call sites outside `webgpuBootProbe.ts` (sole owner) and `webgpuDevicePolicy.ts` (the ladder it calls).
- **The 2026-08-24 hygiene pass's RED CI gate has cleared.** `python3 scripts/audit_dead_sliders.py` (the exact unfiltered CI invocation) now exits **0** — 1191 definitions scanned, **0 new**, 28 known. `audit_extrabuffer.py` also passes (1380 files, 0 new, 93 known-baselined, 32 dynamic-index flagged). Fix First was assessed against this and explicitly not triggered.
- **New live backlog.** The 2026-08-26 audit closed #1123–#1129 wholesale. Only **8 issues open**: #1179 (TypeScript the WASM glue), **#1180** (today's focus), #1181 (gpu-chores live catalog), #1182 (audio/VJ 2.0, author-tagged `future`), #1183 (naga-WASM, gated on #1080), **#1184** (contract hygiene — today's Copilot track), #1185 (thumbnails, GPU-gated), #1080 (WASM promotion, GPU-gated + human decision).
- **Every #1180 claim re-verified in tree.** TS `ShaderCompilation.ts:68-69` returns `{x:8,y:8}` while C++ `wasm_internal.cpp:54-55` returns 16×16; `ShaderCompilation.workgroup.test.ts:77-79` asserts the wrong value as intent; the workgroup histogram across `public/shaders/*.wgsl` is exactly **1359 × 16×16×1, 26 × 8×8×1, 1 × 256×1×1, 1 × 16×16×4**; `resources.cpp:166` builds the 1×1 `emptyTexture_` from the un-reset depth `texDesc` (r32float, 4 B/px) while `:179` uploads `bytesPerRow = 16`.
- **The A/B track split is author-sanctioned.** #1184's "Out of scope" explicitly hands the 8×8 workgroup migration to #1180, so today's two tracks cannot collide by construction.
- **Content stream running in parallel** (Jules + generative swarm): merges through #1189, open draft PRs #1174/#1190/#1191/#1192 and non-draft plan PR #1177. It churns `public/shaders/**` and `shader_plans/**` — the 26-file workgroup migration should be rebased late and gated per file.

**Context gaps (flagged, not hidden):**
- `recent_chats` / `conversation_search` **unavailable** in this headless scheduled run. Context is reconstructed from the repo tree, `weekly_plan.md`, `.swarm-state.md`, live audit-script runs, and GitHub issue/PR state — not from any conversation history.
- **Jest count carried, not measured.** `node_modules` is absent on this VM and plain `npm ci` is still blocked by the `sharp` postinstall behind the proxy (`npm ci --ignore-scripts` is the workaround). `.swarm-state.md` 08-23 saw 84 suites / 551; the 08-24 hygiene pass saw 84 suites / 560. kimi re-establishes the baseline on iteration 0.
- **No GPU adapter on this VM**, and the emscripten build is blocked by #848 — so #1180 **part C's acceptance is GPU-gated**. Parts A and B are fully headless. #1185, #1080, and #1181's validation are likewise GPU-blocked and deliberately not today's pick.
- **`public/shader-manifest-unified.json` is build-generated, not committed**, so #1184's count check must run post-`npm run build:manifest`.

## weekly_plan.md changes (written to the file, PR #1193)

- **Done** — added a 2026-08-29 entry for #1126 with the grep-level evidence above.
- **Backlog** — the 2026-08-24 "CI gate RED" item is struck through and marked resolved with the fresh audit output; added the 2026-08-26 audit set as the live backlog; added a quantified #1184 catalog-drift item (README says 1,291; manifest/definitions/WGSL are 1,347 / 1,360 / 1,382).
- **Ideas** — #1126 marked `[x]` with verification; the whole 08-21 set marked superseded with a forward-map to successors; #1179–#1185 + #1080 seeded; **#1180 marked `[in progress — 2026-08-29]`**.
- **Today's focus** — replaced with the #1180 block (objective, allow/deny file lists, per-iteration verification); the 08-22 block archived into a `<details>`.
- **Last run** — appended the 2026-08-29 entry and closed out the 08-22 entry's `Outcome:` from `pending` to shipped.
- **Bug fix** — an unclosed `<details>` from the 2026-08-01 archive was swallowing Ideas/Backlog/Done/Last run into a collapsible; closed it. Also retired a stale `[in progress — 2026-08-15]` marker on #1107.

## Today's focus

**#1180 — Engine: TS/C++ workgroup fallback + empty-placeholder packing parity.** Three concrete divergences in compile / dispatch / upload, plus the anti-drift contract that stops them recurring:

- **(A)** TS defaults an unparsed shader to 8×8 while C++ defaults to 16×16. Canonical 2D dispatch is 16×16×1, so on TS such a shader **under-dispatches — three quarters of the frame never runs** — while the same shader is correct under WASM. The existing unit test asserts the 8×8 value, so the wrong behavior is encoded as intent and must be changed with it.
- **(B)** 26 leftover `@workgroup_size(8,8,1)` catalog shaders migrate to 16×16×1 (workgroup size and bounds guards only — no shader-math rewrites). The 1D helpers and `src/gpuChores/` 8×8 downsample kernels are explicitly carved out.
- **(C)** The C++ 1×1 `emptyTexture_` is allocated r32float (4 B/px) but uploaded with `bytesPerRow = 16` — a WebGPU validation error on first WASM init on a real GPU, invisible to headless CI.
- **Anti-drift is the real deliverable.** `src/contracts/` is already the established SoT pattern (`uniforms_layout.json`, `webgpu_limits.json`, `webgpu_optional_features.json`, `wasm_exports.json`) with `scripts/verify-device-policy-sync.js` already diffing TS ↔ `device.cpp` ↔ JSON. The fallback constant belongs in a new contract JSON validated by that same script, exactly as the issue asks.

---

# Dispatch

## A. kimi-cli swarm task — the main event

```
You are working in the Pixelocity repo (ford442/image_video_effects): a React 19 + TypeScript
web app that runs 1,300+ WGSL WebGPU compute shaders in real time, with a parallel C++ renderer
compiled to WASM via Emscripten/emdawnwebgpu. Build system is Create React App via CRACO.

## Objective

Close the three remaining TypeScript-vs-C++ divergences in the compile / dispatch / upload path,
and lock the fix behind a machine-checked contract so the two implementations cannot drift again.

## Why this matters

The canonical 2D compute dispatch in this engine is 16x16x1. When a shader's @workgroup_size
cannot be parsed, TypeScript falls back to 8x8 while C++ falls back to 16x16. The renderer
computes its dispatch counts from that fallback, so on the TypeScript path an unparsed shader
under-dispatches: only a quarter of the workgroups are launched and three quarters of the frame
never runs. The same shader is correct under WASM. This is a silent, per-shader correctness bug,
and the existing unit test asserts the wrong value, so it currently reads as intentional.

Separately, the C++ renderer allocates a 1x1 placeholder texture as r32float but uploads it as if
it were 16 bytes wide. That is a WebGPU validation error the first time the WASM renderer
initializes on a real GPU. Headless CI cannot catch it.

## Work items

1. ANTI-DRIFT CONTRACT (do this first — it is the deliverable that outlives the fix)
   Create `src/contracts/workgroup_dispatch.json` as the single source of truth. It must carry at
   minimum: the canonical default `{ "x": 16, "y": 16, "z": 1 }` used when a shader's workgroup
   size cannot be parsed; the documented 1D-helper exceptions; and an explicit carve-out noting
   that `src/gpuChores/` kernels are not catalog FX and are exempt.
   Model the file's shape on the existing `src/contracts/webgpu_optional_features.json` and
   `src/contracts/webgpu_limits.json` — READ them, do not edit them.
   Then extend `scripts/verify-device-policy-sync.js` so `npm run verify:device-policy` fails if
   the TypeScript fallback, the C++ fallback, and this JSON ever disagree. That script already
   diffs `webgpu_limits.json` against the TS policy and `wasm_renderer/device.cpp`; follow the
   same pattern. EXTEND it only — do not weaken or restructure the existing limits, optional-
   feature, or exports checks.

2. FIX THE TYPESCRIPT FALLBACK
   `src/renderer/ShaderCompilation.ts` around line 68-69 currently logs
   "Could not parse workgroup_size from shader, defaulting to 8x8" and returns { x: 8, y: 8 }.
   Change it to the canonical 16x16, sourced from the contract JSON rather than a literal.
   `src/renderer/ShaderCompilation.workgroup.test.ts` around line 77-79 asserts the 8x8 fallback.
   That assertion is the encoded wrong intent — UPDATE IT to 16x16. Add a regression test that
   fails if the TS fallback diverges from the contract JSON.
   C++ `wasm_renderer/wasm_internal.cpp` around line 54-55 already defaults to 16x16 and is
   correct; touch it only if it must read from the contract.

3. MIGRATE THE 26 LEFTOVER 8x8 CATALOG SHADERS
   Change `@workgroup_size(8, 8, 1)` to `@workgroup_size(16, 16, 1)` in exactly these files under
   `public/shaders/`, adding bounds guards where a shader still assumes an 8-wide tile:
     crt-tv-stipple, crystal-freeze, divine-light-gpt52, double-exposure, entropy-grid,
     gen-klein-bottle-walk, gen-luminous-fluid-chladni-resonator, gen-magnetic-field-warp,
     gen-neural-network-glow-synaptic-pulse, gen-quantum-superposition, halftone,
     hybrid-noise-kaleidoscope, kinetic_tiles, lighthouse-reveal, liquid-swirl, neon-pulse-edge,
     neon-pulse, pixel-rain, rgb-fluid, rgb-glitch-displacement, split-flap-display,
     vaporwave-horizon, voronoi-zoom-turbulence, voronoi, vortex-drag, vortex
   (all with a .wgsl extension). Workgroup size and guards ONLY — do not rewrite shader math,
   do not rename params, do not touch any other shader file.
   Leave the 1D helpers (@workgroup_size(64,1,1) / (256,1,1)) and the one 16x16x4 shader alone.
   Leave `src/gpuChores/shaders.ts`'s 8x8 downsample kernels alone — they are not catalog FX.

4. FIX THE C++ EMPTY-PLACEHOLDER PACKING
   In `wasm_renderer/resources.cpp`, `CreateResources()`: around line 156 the depth targets set
   `texDesc.format = WGPUTextureFormat_R32Float`, and around line 166 `emptyTexture_` is created
   from that same descriptor WITHOUT resetting the format — so the 1x1 placeholder is r32float
   (4 bytes per pixel). But around line 179 the upload sets
   `emptyDataLayout.bytesPerRow = sizeof(float) * 4` (16 bytes) and writes four floats.
   Set `texDesc.format` AND `texDesc.usage` explicitly for the empty texture instead of
   inheriting the depth descriptor, and make the upload match: one r32 float, bytesPerRow = 4.
   Match what TypeScript already does correctly in `src/renderer/webgpu/resources.ts` (format
   'r32float', writeTexture with a single-element Float32Array and bytesPerRow 4). Leave a comment
   saying r32float was chosen deliberately to match TS. Add a focused colocated test on the
   TypeScript side pinning the r32float placeholder pack — the TS code is already correct, so
   that test is a regression lock, not a fix.

## Files you may touch

- src/renderer/ShaderCompilation.ts
- src/renderer/ShaderCompilation.workgroup.test.ts   (the 8x8 assertion MUST be updated)
- src/contracts/workgroup_dispatch.json              (new)
- scripts/verify-device-policy-sync.js               (extend only)
- the 26 public/shaders/*.wgsl files listed above    (workgroup size + bounds guards only)
- wasm_renderer/resources.cpp                        (the emptyTexture_ block only, ~lines 164-183)
- wasm_renderer/wasm_internal.cpp                    (only if the C++ default must read the contract)
- src/renderer/webgpu/resources.ts                   (test-only addition; the code is already correct)
- docs/BINDING_CONTRACT.md                           (the canonical-dispatch note)

Read-only reference, DO NOT EDIT: src/contracts/webgpu_optional_features.json,
src/contracts/webgpu_limits.json, wasm_renderer/device.cpp.

## Files you must NOT touch

- The adapter ladder and boot probe: src/renderer/webgpuDevicePolicy.ts,
  src/renderer/webgpuBootProbe.ts, src/components/WebGpuProbeFailureOverlay.tsx. Frozen.
- The device single-source-of-truth that just landed: src/utils/adoptedGpuDevice.ts and
  RendererManager.getDevice(). Do not re-plumb it.
- src/gpuChores/** — its 8x8 kernels are correct by design and explicitly carved out.
- src/renderer/UniformBuffer.ts — immutable uniform packing.
- wasm_renderer/device.cpp, and the compatibleSurface=nullptr / TimedWaitAny /
  canvas alphaMode:'opaque' + preferred-format double-configure paths. These are healthy.
  Do not "simplify" them.
- storage_manager/** (Python backend).
- scripts/audit_*.py, .github/workflows/**, README.md, reports/**, and the catalog/manifest
  scripts. A separate track owns those today — staying off them prevents a collision.
- Any public/shaders/*.wgsl outside the 26 listed, and all of shader_plans/**. A content
  generation stream is actively merging into those directories right now.

Do not add a WGSL parser dependency (a separate ticket owns that). Do not change the default
renderer backend, the feedback copy order, or the limits JSON.

## How to verify yourself, every iteration

Run these and fix what breaks before moving on:

  npm ci --ignore-scripts        # plain `npm ci` fails: the sharp postinstall is proxy-blocked
  npx tsc --noEmit                                   # must be clean
  CI=true npx craco test --watchAll=false            # must be green
  SKIP_WASM_BUILD=1 npm run build                    # must print "Compiled successfully"
  npm run verify:device-policy                       # THE key gate — see below
  npm run verify:uniforms
  npm run verify:dependency-boundaries
  npm run audit:extrabuffer                          # expect: 0 new, 93 known
  npm run audit:dead-sliders                         # expect: 0 new, 28 known
  python3 scripts/wgsl_precommit_gate.py --files <each changed .wgsl>   # green on all 26

`verify:device-policy` is the gate that proves the anti-drift contract actually works. Sanity-check
it: temporarily hand-edit the TypeScript fallback away from the JSON value and confirm the script
FAILS. If it still passes, your contract check is not wired up. Revert the edit afterward.

On iteration 0, before changing anything, record the baseline Jest suite/test counts. Do not trust
a carried number — measure it.

If the emscripten toolchain is unavailable in your environment (`npm run wasm:build` fails on
`--use-port=emdawnwebgpu`, a known pre-existing issue), still make the C++ edit. Keep it minimal,
review it by eye against the TypeScript equivalent, and record in your save-state that the C++
change is UNCOMPILED and needs a workstation build.

## Save-state

At every iteration boundary, append to `.swarm-state.md` under a heading
`# Swarm Save-State — TS/C++ workgroup + packing parity (#1180)`:
the iteration number, files touched, the exact verification command output (suite/test counts,
build result, gate pass/fail), what is left, and any decision you made that a reviewer would
want to challenge. Be honest about what is unverified — especially the C++ part, whose real
acceptance requires a discrete GPU. Someone must be able to pause and resume from this file alone.

## Definition of done

- TS and C++ unparsed-workgroup fallbacks are both 16x16, both derived from the contract JSON,
  and `verify:device-policy` fails if they ever diverge.
- The workgroup unit test asserts 16x16.
- Zero `@workgroup_size(8, 8` remaining in public/shaders/ (or a documented allowlist for any
  file you deliberately left, with the reason).
- The WASM empty-placeholder upload bytesPerRow matches its allocated format.
- All verification commands above are green.
- No change to the adapter ladder, limits JSON, feedback copy order, or default backend.
```

## B. GitHub issue — draft now, for Copilot later

Decoupled from every file kimi-cli touches: this is `scripts/` + `.github/` + `README.md` + `reports/` only, and explicitly stays off `verify-device-policy-sync.js` and all of `public/shaders/`. It expands #1184's B track.

**Title:** `Catalog count SoT: make README/manifest/definitions agree, alias legacy underscore IDs, whitelist graph parents`

**Context / motivation**

Pixelocity's shader catalog has four disagreeing counts. As of the 2026-08-26 audit: the unified manifest carries 1,347 IDs, `shader_definitions/**/*.json` has 1,360 files, `public/shaders/*.wgsl` has 1,382 files, and `README.md` advertises 1,291 in four separate places. Agents regenerate catalogs and claim 1,333 / 1,345 / 1,291 depending on which artifact they read. That ambiguity is the mechanism by which duplicate IDs and dead sliders enter the tree unnoticed — it is a prerequisite for the active focus area of authoring new WGSL compute shaders at volume, and for multi-slot shader stacking, which resolves shaders by ID.

Three related catalog-integrity defects travel with it: 22 legacy IDs use underscores (`aurora_borealis`, `gen_mandelbulb_3d`, `kimi_flock_symphony`, …) while new IDs use hyphens, so saved URLs and stored presets can 404 silently; 13 ID-vs-filename mismatches are reported as errors when most are legitimate multipass graph parents (`ripple-tank` → `ripple-tank-step`); and the extraBuffer audit's 93 baselined entries are one flat list mixing engine-owned FFT-zone writes with genuine shader bugs, so the baseline cannot be safely shrunk.

**Proposed approach — first pass, expand before handing to Copilot**

1. Add `npm run verify:catalog-counts` (or extend `verify:shader-list-urls`) asserting that the README's advertised total, the unified manifest's `_meta` count, and the unique-ID count over `shader_definitions/**/*.json` agree. Note `public/shader-manifest-unified.json` is build-generated by `scripts/build-unified-manifest.ts`, not committed — so the check must run after `npm run build:manifest`. Wire it into CI.
2. Make the README total generated rather than hand-maintained, so it cannot drift again.
3. Emit a generated alias map for the 22 underscore IDs, canonicalizing hyphens for new IDs. Alias only — do **not** mass-rename files, which would break VPS storage keys.
4. Teach the hygiene script to whitelist `multipass.graph` entries so graph parents stop being reported as ID-vs-filename errors, and confirm the 13 known cases fall out of the report.
5. Split `reports/extrabuffer_write_audit_baseline.json` into `engine-owned` and `shader-bug` sections with a documented reason per group. Do not blind-rewrite the 93 known FFT-zone owners — many are engine-documented audio behavior.
6. Triage the 32 unresolved dynamic-index extraBuffer writes: for each, either prove the index stays within the safe `[133..255]` window or record it as needing a bounded-slot rewrite. Comment-level triage is acceptable; the rewrites themselves are out of scope.

**Acceptance criteria — rough, refine during expansion**

- A CI check fails when README / manifest / definitions unique-ID counts disagree.
- The README total is generated, not hand-written.
- The 22 underscore IDs are documented as aliases, not silent duplicates; no file renames.
- Graph-parent ID≠filename cases are no longer reported as errors.
- The extraBuffer baseline distinguishes engine-owned from shader-bug entries.
- The 32 dynamic-index writes each carry a triage verdict.
- `audit:dead-sliders` and `audit:extrabuffer` still exit 0.
- No changes to `src/`, `wasm_renderer/`, `public/shaders/`, device init, feedback order, or the WASM default.

**Open questions for Noah**

- Should the README total be injected by a build step, or should CI just fail and require a manual bump? The first is self-healing; the second keeps the README diffable.
- For the 22 underscore IDs: is the alias map read at runtime (so old share URLs resolve), or is it documentation only for now? Runtime resolution is more useful but touches `src/`, which would break this issue's decoupling.
- Is there a canonical count you consider authoritative today — manifest or definitions? They differ by 13, which is roughly the graph-parent population; worth confirming that is the whole explanation.
- Should the dynamic-index triage produce a machine-readable file the auditor consumes, or is a markdown report enough for now?

## C. Three chat-model prompts targeting the issue from B

### C1 — Gemini Pro (codebase + issue → implementation plan)

```
I'm going to give you a GitHub issue from a real codebase and I'd like you to produce a more
complete implementation plan than the issue currently contains.

THE CODEBASE: Pixelocity (github.com/ford442/image_video_effects) — a React 19 + TypeScript web
app that runs 1,300+ WGSL WebGPU compute shaders in real time. Build is Create React App via
CRACO. There is also a C++ renderer compiled to WASM (Emscripten/emdawnwebgpu) and a Python
FastAPI backend for shader/media storage. Shader metadata lives in `shader_definitions/**/*.json`,
shader source in `public/shaders/*.wgsl`, and a unified manifest is generated at build time by
`scripts/build-unified-manifest.ts` into `public/shader-manifest-unified.json` (generated, not
committed). Existing Node/Python tooling lives in `scripts/`, with npm aliases including
`verify:shader-list-urls`, `verify:uniforms`, `verify:device-policy`,
`verify:dependency-boundaries`, `audit:extrabuffer`, `audit:dead-sliders`, and `build:manifest`.
CI is GitHub Actions in `.github/workflows/ci.yml`.

[PASTE THE FULL ISSUE TEXT FROM SECTION B HERE]

What I want from you:

1. Identify the specific files and functions this touches. Name the scripts that already do
   adjacent work and would be extended rather than duplicated — I would rather grow
   `verify-shader-list-urls.mjs` than add a ninth verify script if that is the right call.
2. Spot dependencies the issue misses. In particular: what else reads shader IDs at runtime
   (share links, preset packs, saved VJ stacks, the ratings/storage backend) and would be
   affected by an ID alias map? What breaks if the manifest and definitions counts are
   reconciled by dropping entries rather than adding them?
3. Flag ordering constraints. The count check must run after the manifest build; are there other
   sequencing traps in the prebuild chain
   (`wasm:build` → `buildMultipassRegistry.js` → `generate_shader_lists.js` → `build:manifest`)?
4. Call out anything in the issue that is wrong, underspecified, or likely to cause a regression.
5. Produce a concrete step-by-step plan with a suggested commit breakdown, and sharpen the
   acceptance criteria into checkable assertions.

Be specific and skeptical. If a proposed step would be better done a different way, say so and
explain the tradeoff rather than just following the issue's framing.
```

### C2 — Kimi.com / K2 (stress-test + alternatives)

```
Stress-test the proposed approach in the GitHub issue below, then give me two genuine
alternatives and argue for the best one.

CONTEXT: Pixelocity is a React 19 + TypeScript WebGPU shader playground with 1,300+ WGSL compute
shaders. Shader metadata is in per-category JSON files; shader source is in a flat directory; a
unified manifest is generated at build time. Four different artifacts currently report four
different shader counts, and agents working on the repo keep citing whichever number they read
last. Multi-slot shader stacking and share links both resolve shaders by string ID, and some
legacy IDs use underscores while new ones use hyphens.

[PASTE THE FULL ISSUE TEXT FROM SECTION B HERE]

What I want:

1. Attack the proposed approach. Where does "add a CI check that the counts agree" fail in
   practice? What happens on a PR that legitimately adds a shader — does every contributor now
   hit a red build until they regenerate? Is a generated README total actually maintainable, or
   does it create merge conflicts on every content PR? The repo merges generative-shader PRs
   almost daily, so churn cost is a real objection, not a hypothetical one.
2. Interrogate the alias-map design. Aliases that exist only as documentation will drift.
   Aliases resolved at runtime require touching application source, which this issue is
   deliberately scoped away from. Is that scoping a mistake?
3. Give me two alternative designs. One should be meaningfully more minimal than the issue's
   plan; the other should be willing to spend more (including touching application source or
   changing the on-disk layout) if that buys a durable fix. Make them real alternatives, not
   restatements.
4. Pick one — the issue's plan or one of your alternatives — and defend it. Name the failure
   mode you are accepting, because every option here accepts one.

Be adversarial. I want the objections I have not thought of, not a summary of what I wrote.
```

### C3 — Grok.com (ecosystem currency check)

```
I want a current-ecosystem reality check on an approach before I build it.

THE STACK: React 19, TypeScript 5.4, Create React App via CRACO (deliberately NOT migrated to
Vite — that call has been made and re-affirmed), WGSL compute shaders on WebGPU, a C++ renderer
compiled to WASM via Emscripten with emdawnwebgpu, @xenova/transformers for in-browser depth
estimation, @mlc-ai/web-llm running Gemma-2-2b in-browser, hls.js, Playwright for browser
automation, GitHub Actions for CI, and a Python FastAPI backend. The catalog is 1,300+ WGSL
shaders with per-shader JSON metadata and a build-time generated unified manifest.

[PASTE THE FULL ISSUE TEXT FROM SECTION B HERE]

Questions:

1. Is hand-rolled Node/Python catalog-validation tooling still the sensible choice in 2026, or has
   something in the ecosystem made this a solved problem — schema-validation tooling, asset-manifest
   tooling, content-collection patterns from adjacent frameworks that would port cleanly to a CRA
   build? I am not looking for a framework migration, just whether I am rebuilding something that
   now exists off the shelf.
2. Is there current best practice for stable content IDs and alias/redirect maps in a static asset
   catalog — particularly for keeping old share URLs alive after an ID convention change?
3. Anything recent in the WebGPU / WGSL tooling space relevant to validating a large shader corpus
   in CI? The repo currently shells out to naga-cli. Has that ecosystem moved — is a WASM-compiled
   validator now practical to run in-process?
4. Any of the pinned stack choices here now actively problematic — CRA/CRACO's maintenance status
   in particular, given the deliberate decision not to move to Vite?

Cite what is actually current. If the existing approach is still right, say so plainly rather than
inventing a reason to change.
```

## D. Copilot Agent handoff

```
Implement the GitHub issue below in the Pixelocity repo (ford442/image_video_effects).

{{EXPANDED_ISSUE}}

Constraints — these are hard:

- Touch ONLY: scripts/, .github/workflows/, README.md, reports/, and package.json's scripts block.
- Do NOT touch: src/**, wasm_renderer/**, public/shaders/**, shader_definitions/**,
  shader_plans/**, storage_manager/**.
- Do NOT touch scripts/verify-device-policy-sync.js. Another change is actively extending it and
  you will collide.
- Do not rename any shader file or any shader ID. Aliases only.
- Do not add an npm dependency.

Verify before you open the PR:

  npm ci --ignore-scripts        # plain `npm ci` fails: the sharp postinstall is proxy-blocked
  SKIP_WASM_BUILD=1 npm run build
  npm run verify:shader-list-urls
  npm run verify:dependency-boundaries
  npm run audit:extrabuffer      # must still exit 0
  npm run audit:dead-sliders     # must still exit 0
  CI=true npx craco test --watchAll=false

Every acceptance criterion in the issue must be satisfied and demonstrated in the PR description
with the actual command output — not a claim that it passes. If a criterion turns out to be
wrong or impossible, say so explicitly in the PR rather than silently dropping it.

Open a PR for review. Do not merge.
```

## E. Claude Code — whole-stack pipeline task

Independent of kimi-cli's work: pipeline hygiene, not integration. The 2026-08-24 pass verified install → build → deploy dry-run → backend end-to-end and surfaced two items that were deliberately not fixed then. This run closes them out and re-checks the deploy manifest.

```
Whole-stack pipeline task for Pixelocity (ford442/image_video_effects): a React 19 + TypeScript
WebGPU shader app deployed by SFTP to DreamHost via Python scripts in scripts/, talking to a
Python FastAPI backend (storage_manager/) hosted on a VPS. CI is GitHub Actions.

A full hygiene pass ran on 2026-08-24 and found the pipeline healthy overall, but left two
findings deliberately unfixed because they needed sign-off, plus one deploy-manifest oddity.
Close them out.

## 1. Storage Manager CORS — decide and fix (the significant one)

`storage_manager/config.py` around lines 57-64 defines ALLOWED_ORIGINS as:
  localhost:3000, localhost:5173, test1.1ink.us, test.1ink.us, storage.1ink.us, and "*"

`storage_manager/app.py` around lines 44-50 configures Starlette's CORSMiddleware with
allow_credentials=True.

Two problems to verify from the source before changing anything:
  (a) `noahcohn.com` is absent, even though an older note claimed it was present and verified.
      Determine from git history whether it was removed or never there.
  (b) With "*" in allow_origins AND allow_credentials=True, Starlette reflects the request's
      actual Origin header rather than emitting a literal "*". Read the installed Starlette
      version's CORSMiddleware source and CONFIRM this behavior rather than assuming it — if it
      holds, any origin can make credentialed cross-site requests to this API.

Then: drop the "*" entry, add the real production origin(s), and add a regression test asserting
the allowlist is finite and contains no wildcard. Run the backend suite from the REPO ROOT —
`python -m pytest storage_manager/tests/ -q` — not from inside storage_manager/, because the tests
`import storage_manager.app` and that only resolves with the repo root on sys.path. Baseline is
95 passed, 1 warning.

Report what the origins were before and after. If you cannot determine the correct production
origin from the repo, say so and stop rather than guessing — a wrong CORS allowlist breaks the
live frontend.

## 2. Deploy manifest staleness

`.deploy_app_manifest.json` tracks only 40 of ~424 current build files (thumbnails, the wasm
bridge, and shader lists were never captured by a prior run), and carries 7 stale entries pointing
at now-removed hashed bundles (e.g. main.a6a3c33b.js, shader-lists/interactive.json,
shader-lists/liquid.json). `scripts/deploy_app_only.py` has no delete logic, so stale entries
accumulate forever.

Do a LOCAL-ONLY manifest diff — hash comparison against a fresh build, ZERO network calls, no
connection to DreamHost. Then decide and implement: either prune stale entries as part of the
normal manifest write, or add an explicit prune command. Explain which you chose and why.
Confirm by reading the code that `scripts/deploy_credentials.py` still reads secrets only from
env / .env.deploy / SSH key / TTY prompt, with nothing hardcoded.

## 3. Re-verify the pipeline end to end

  npm ci --ignore-scripts          # plain npm ci fails: sharp postinstall is proxy-blocked
  npx tsc --noEmit
  CI=true npx craco test --watchAll=false
  SKIP_WASM_BUILD=1 npm run build
  node scripts/generate_shader_lists.js     # must be deterministic — zero git diff afterward
  npm run verify:uniforms
  npm run verify:dependency-boundaries
  npm run verify:shader-list-urls
  npm run audit:extrabuffer
  npm run audit:dead-sliders
  npm audit --production
  python -m pytest storage_manager/tests/ -q

Compare against the 2026-08-24 baselines: 84 suites / 559 passed + 1 skipped; main.js 272.5 kB
gzipped; shader list generation deterministic; 95 backend tests passing; 4 high / 0 critical npm
advisories, all in the @xenova/transformers chain (adm-zip via onnxruntime-node, and sharp's
libvips CVEs), none with a fix available. Flag any drift from those numbers.

## Boundaries

Do NOT touch src/renderer/**, src/contracts/**, scripts/verify-device-policy-sync.js,
wasm_renderer/**, or public/shaders/** — separate tracks own all of those today.
Do NOT auto-fix the npm advisories: the only remediation is downgrading @xenova/transformers,
which breaks depth estimation. Report them; leave them.
Make NO network connection to DreamHost or the production VPS. Everything here is local.

Report a stage-by-stage verdict with real command output. If a stage passes, say so plainly; if
it fails, give the output rather than a summary.
```

## F. Jules wrap-up — fill the placeholders at end of day

```
You are wrapping up an autonomous agent's work session in the Pixelocity repo
(ford442/image_video_effects) and turning it into a clean, reviewable pull request.

## What was being built

The objective was GitHub issue #1180: close three TypeScript-vs-C++ divergences in the compile /
dispatch / upload path, and lock the fix behind a machine-checked contract so they cannot recur.

  (A) The TypeScript renderer defaulted an unparsed shader's @workgroup_size to 8x8 while the C++
      renderer defaulted to 16x16. Canonical dispatch is 16x16x1, so on TypeScript such a shader
      under-dispatched and three quarters of the frame never ran. The existing unit test asserted
      the wrong 8x8 value.
  (B) 26 catalog shaders still declared @workgroup_size(8, 8, 1) and were migrated to 16x16x1.
  (C) The C++ renderer allocated a 1x1 placeholder texture as r32float but uploaded it with
      bytesPerRow = 16, a WebGPU validation error on first WASM init on a real GPU.

The durable deliverable was `src/contracts/workgroup_dispatch.json`, validated by
`scripts/verify-device-policy-sync.js` so the TypeScript fallback, the C++ fallback, and the JSON
can never diverge again.

## Files changed

{{KIMI_CLI_FILES_CHANGED}}

## What the agent did

{{KIMI_CLI_SUMMARY}}

## Known issues noticed on a cursory review

{{KNOWN_ISSUES}}

## Your wrap-up checklist

1. Read the full diff before changing anything. Note anything that contradicts the objective above.
2. Read `.swarm-state.md` — the agent recorded its iteration log, verification output, and
   anything it left unverified. Treat its self-reported results as claims to check, not facts.
3. Run the formatter and the linter. Fix what they flag. Lint noise in untouched files is not
   yours to fix — stay in the diff.
4. Run the tests:  CI=true npx craco test --watchAll=false
   Fix every failure. If a test fails because the agent changed intended behavior, update the test
   to the NEW correct expectation and say so explicitly in the PR — do not delete, skip, or
   quarantine it. Note that `ShaderCompilation.workgroup.test.ts` SHOULD have changed from
   asserting 8x8 to asserting 16x16; that change is correct and intended.
5. Complete any TODO or stub the agent left behind. If one cannot be completed, convert it to a
   clearly worded TODO naming what is blocked and why.
6. Add unit tests for any new public function that lacks coverage — especially the contract
   loader and the `verify-device-policy-sync.js` extension.
7. Verify the anti-drift gate actually works: temporarily edit the TypeScript fallback away from
   the contract JSON value and confirm `npm run verify:device-policy` FAILS. Revert the edit. If
   it still passes, the contract check is not wired up and the PR's main deliverable is missing.
8. Update inline docs and `docs/BINDING_CONTRACT.md` if the canonical dispatch contract changed
   shape. Update the README only if a public command changed.
9. Run the full verification suite and paste the real output into the PR:

     npm ci --ignore-scripts     # plain `npm ci` fails: sharp postinstall is proxy-blocked
     npx tsc --noEmit
     CI=true npx craco test --watchAll=false
     SKIP_WASM_BUILD=1 npm run build
     npm run verify:device-policy
     npm run verify:uniforms
     npm run verify:dependency-boundaries
     npm run audit:extrabuffer
     npm run audit:dead-sliders
     python3 scripts/wgsl_precommit_gate.py --files <each changed .wgsl>

10. Confirm zero `@workgroup_size(8, 8` remain in `public/shaders/` — or that any deliberate
    exception is documented with its reason.
11. If `wasm_renderer/` changed, attempt `npm run wasm:build`. The emscripten toolchain is known
    to fail in some environments on `--use-port=emdawnwebgpu`. If it fails, say so in the PR and
    mark the C++ change as UNCOMPILED and needing a workstation build — do not claim it verified.

## Acceptance criteria

- [ ] Formatter and linter clean on the changed files
- [ ] Full test suite green; every changed assertion justified in the PR
- [ ] No TODOs or stubs left undocumented
- [ ] New public functions have unit tests
- [ ] `verify:device-policy` demonstrably fails when TS and the contract JSON disagree
- [ ] `SKIP_WASM_BUILD=1 npm run build` prints "Compiled successfully"
- [ ] `audit:extrabuffer` and `audit:dead-sliders` both still exit 0
- [ ] All 26 changed shaders pass the WGSL precommit gate
- [ ] Zero remaining 8x8 catalog shaders, or documented exceptions
- [ ] The C++ change's compilation status is stated honestly
- [ ] No changes to the adapter ladder, boot probe, `adoptedGpuDevice.ts`, `gpuChores/`,
      `UniformBuffer.ts`, the limits JSON, the feedback copy order, or the default backend

## Important

Open a pull request for Noah to review. DO NOT MERGE IT.

In the PR description, state plainly what is verified, what is unverified, and what you changed
versus what the agent left. If something is broken and you could not fix it, say that in the PR
rather than leaving it to be discovered in review. Part C's real acceptance requires a discrete
GPU and cannot be proven in CI — say so rather than implying otherwise.
```

## G. Review prompts

### G1 — review the kimi-cli diff, before Jules wraps it

```
Review this diff for performance and architectural drift. Do not restate what it does — I know
what it does. Tell me what is wrong with it.

CONTEXT: Pixelocity is a React 19 + TypeScript WebGPU shader playground running 1,300+ WGSL
compute shaders, with a parallel C++/WASM renderer that must stay behaviorally identical to the
TypeScript one. Canonical 2D compute dispatch is 16x16x1.

The diff's objective: (A) change the TypeScript fallback for an unparsed @workgroup_size from 8x8
to 16x16 (C++ already used 16x16, so the TypeScript path was under-dispatching three quarters of
every frame); (B) migrate 26 remaining 8x8 catalog shaders to 16x16x1; (C) fix a C++ 1x1
placeholder texture allocated as r32float but uploaded with bytesPerRow=16; and above all
(D) introduce `src/contracts/workgroup_dispatch.json` validated by
`scripts/verify-device-policy-sync.js` so the two implementations cannot silently diverge again.

[PASTE THE DIFF]

Specifically:

1. PERFORMANCE. Quadrupling the workgroup size per dispatch changes occupancy and shared-memory
   pressure. For each of the 26 migrated shaders, is the change actually safe — does any of them
   allocate a workgroup-shared array sized to an 8x8 tile, index into one assuming 8-wide, or
   rely on a barrier pattern that assumes 64 invocations? A shader that reads correctly but
   silently corrupts at 256 invocations is the failure mode I care most about.
2. BOUNDS. Where guards were added, are they correct at the image edges, and do they cost a
   branch in the hot loop that could have been avoided?
3. ARCHITECTURAL DRIFT. Does the contract JSON actually become the single source of truth, or is
   the 16x16 value still duplicated as a literal somewhere the verify script does not check?
   Trace every path that determines a dispatch size and tell me if any bypasses the contract.
4. THE C++ CHANGE. Compare it against the TypeScript equivalent in
   `src/renderer/webgpu/resources.ts`. Are format, usage, bytesPerRow, and the written data all
   mutually consistent? Does the fix accidentally depend on descriptor state set earlier in the
   function — the same class of bug it is meant to fix?
5. SCOPE. Flag anything touched beyond the stated objective, especially edits to the adapter
   ladder, boot probe, device adoption, gpuChores kernels, or shaders outside the 26.

Rank findings by severity. For each, give the concrete failure scenario — inputs or state, and
the resulting wrong behavior. If something looks wrong but you cannot prove it from the diff
alone, say which file you would need to see.
```

### G2 — review the Jules PR against the original objective

```
Review this pull request against both its original objective and the wrap-up checklist it was
supposed to satisfy. I want to know whether it is actually done, not whether it looks done.

ORIGINAL OBJECTIVE (GitHub issue #1180, Pixelocity — a React 19 + TypeScript WebGPU shader app
with a parallel C++/WASM renderer):
  (A) TypeScript and C++ unparsed-@workgroup_size fallbacks must both be 16x16, with the unit test
      updated from its previous 8x8 assertion. Canonical dispatch is 16x16x1; the old TypeScript
      8x8 fallback caused three quarters of each frame to go undispatched.
  (B) The 26 remaining @workgroup_size(8, 8, 1) catalog shaders migrate to 16x16x1, with bounds
      guards where needed — workgroup size only, no shader-math rewrites.
  (C) The C++ 1x1 empty placeholder texture's upload bytesPerRow must match its allocated format
      (it was allocated r32float, 4 bytes per pixel, but uploaded as 16).
  (D) A new `src/contracts/workgroup_dispatch.json`, validated by
      `scripts/verify-device-policy-sync.js`, must make future divergence impossible.
  Out of scope, and must be untouched: the adapter ladder, boot probe, `adoptedGpuDevice.ts` /
  `RendererManager.getDevice()`, `src/gpuChores/**`, `UniformBuffer.ts`, `wasm_renderer/device.cpp`,
  the limits JSON, the feedback copy order, the default renderer backend, `storage_manager/**`,
  `scripts/audit_*.py`, `.github/workflows/**`, `README.md`, and any shader outside the 26.

WRAP-UP CHECKLIST it claimed to satisfy: formatter and linter clean; full test suite green with
every changed assertion justified; no undocumented TODOs or stubs; unit tests for new public
functions; a demonstration that `verify:device-policy` FAILS when the TypeScript fallback and the
contract JSON disagree; `SKIP_WASM_BUILD=1 npm run build` compiling; `audit:extrabuffer` and
`audit:dead-sliders` both exiting 0; all 26 shaders passing the WGSL precommit gate; zero
remaining 8x8 catalog shaders or documented exceptions; and an honest statement of the C++
change's compilation status.

[PASTE THE PR DIFF AND DESCRIPTION]

Answer these:

1. Is each of A, B, C, D actually delivered? Name what is missing or only partially done.
2. Is D real? The anti-drift contract is the deliverable that outlives this PR. If the verify
   script does not genuinely fail on divergence — or if the 16x16 value is still hardcoded on
   some path the script never inspects — then this PR fixed a bug and left the drift mechanism
   intact. Check this properly rather than trusting the PR description.
3. Does any claimed verification lack evidence? Distinguish pasted command output from assertions
   that something passes. Flag any claim about the C++ change being verified, since its real
   acceptance requires a discrete GPU and cannot be established in CI.
4. Was anything out of scope touched? Check the exclusion list above file by file.
5. Did any test get weakened, skipped, or deleted rather than updated? The workgroup test SHOULD
   have changed from 8x8 to 16x16 — that one is correct. Any other test change needs a
   justification, and its absence is a finding.
6. What would you send back before merging? Give a short, ordered list — blocking items first,
   then things that can land as follow-ups.
```

## Suggested timeline

| Offset | Track |
|---|---|
| **T+0:00** | Kick off **A** (kimi-cli, #1180). Let it establish its iteration-0 baseline before you walk away — `npm ci --ignore-scripts` first, since plain `npm ci` still fails on the `sharp` postinstall. |
| **T+0:15** | File issue **B** from the draft above. |
| **T+0:20 – T+1:20** | Expansion: run **C1/C2/C3** while kimi iterates. Fold the answers into issue B. C2's churn-cost objection is the one most likely to change the design. |
| **T+1:30** | Hand the expanded issue to Copilot via **D**. |
| **Mid-day** | Run **E** (Claude Code whole-stack). The CORS decision in stage 1 needs your call — it may stop and ask, which is correct behavior. |
| **T+—** | When kimi finishes, run **G1** on its raw diff before Jules touches it. |
| **End of day** | Fill the three placeholders and run **F** (Jules). Then **G2** on the resulting PR. Jules opens the PR; it does not merge. |

## Open questions

- **Part C cannot be accepted in this environment.** The C++ empty-placeholder fix needs a real GPU and a working emscripten build (blocked by #848 on the cloud VM). Expect kimi to land it uncompiled and flagged; the actual proof is a WASM init on your workstation. Worth doing before the PR merges rather than after.
- **Sequencing between tracks A and B.** They touch disjoint files by construction, but if #1184's Copilot work regenerates the extraBuffer or dead-slider baselines while kimi is editing 26 shaders, the baselines could capture a transient state. Workgroup-size changes should not add params or extraBuffer writes, so the risk is low — but let A land first if both are ready simultaneously.
- **The 26-shader migration will conflict with the content stream.** Draft PRs #1174/#1190/#1191/#1192 are live in `public/shaders/**` and `shader_plans/**`. Rebase the shader half of A late.
- **Whether any of the 26 shaders genuinely needs 8x8.** The issue assumes all are safe to migrate; G1 question 1 is specifically designed to catch a shader with an 8x8-sized workgroup-shared array. If one turns up, it becomes a documented allowlist entry rather than a migration.
- **Unverifiable this run:** the Jest baseline (carried from `.swarm-state.md`, not measured — no `node_modules` on this VM), and anything requiring conversation history, which was unavailable in this scheduled run.
