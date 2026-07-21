# Lane B — Workgroup Size & Dispatch Audit (2026-07-21)

Scope: `public/shaders/*.wgsl` (1314 files), dispatch path in `src/renderer`,
gate scripts in `scripts/`. Read-only audit; no shader files modified.

## TL;DR

**16×16 is the healthy norm** (1258/1314 files, ~96%). The 54 `(8,8,1)` shaders are
plain per-pixel effects — smaller tiles, no shared memory, dispatched correctly by the
renderer; not a bug, just a style/perf deviation. **Two live catalog shaders are broken
by a parser/dispatch mismatch** (`boids.wgsl`, `kimi_flock_symphony.wgsl`). No workgroup
memory overruns; one shader sits exactly *at* the 16 KB limit. No barrier misuse found.

## 1. `getWorkgroupSize` parsing — gaps found

Implementation: `parseWorkgroupSize()` in `src/renderer/ShaderCompilation.ts:27-46`,
cached per shader id in `WebGPUShaderManager` (`src/renderer/webgpu/pipeline.ts:54`),
consumed by `frame.ts:636` and `GraphRunner.ts:88` as
`dispatchWorkgroups(ceil(scaledW/wg.x), ceil(scaledH/wg.y))`.

Handles correctly: 2-arg and 3-arg literal forms (regex captures x,y, ignores z),
arbitrary whitespace/newlines between `@compute` and `@workgroup_size` (two-pass
fallback), missing attribute (warns, defaults 8×8).

**Gaps:**

| # | Gap | Severity | Affected |
|---|-----|----------|----------|
| P1 | **First-`@compute`-wins**: with multiple entry points, the parser returns the *first* `@workgroup_size` in the file, not the one attached to `fn main` — but the pipeline is built with `entryPoint: 'main'` (`ShaderCompilation.ts:190`). Parsed size ≠ actual pipeline workgroup size → wrong dispatch grid. | **HIGH** | `boids.wgsl`, `kimi_flock_symphony.wgsl` (both in live catalog: `artistic.json`, `generative.json`) |
| P2 | Single-arg form `@workgroup_size(64)` doesn't match the two-capture regex → silent 8×8 default. | Latent (no current file uses it) | — |
| P3 | Non-literal/override forms (`@workgroup_size(WG_X)`) → 8×8 default. | Latent (none in repo) | — |
| P4 | Z dimension dropped from the map (`{x, y}` only). Harmless today: dispatch z is always 1, which is correct for the one z=4 shader (its z=4 is *intra*-workgroup). | Info | `deep-workgroup-multi-effect-blend.wgsl` |
| P5 | The WASM renderer has its own parser (`wasm_renderer/wasm_internal.cpp:28-67`) with the same first-`@compute` flaw (P1) — it finds the first `@compute` then the first `@workgroup_size` after it. It *does* handle the 1-arg form (y=1). Same two shaders affected on the WASM path. | **HIGH** | same as P1 |

### P1 impact quantified (e.g. canvas W=1920, H=1080)

`boids.wgsl` / `kimi_flock_symphony.wgsl` declare `@workgroup_size(64,1,1) update_boids`
first and `@workgroup_size(16,16,1) main` second. Parser returns `{64,1}`; the pipeline
runs `main` (16×16). Dispatch = `ceil(1920/64)=30` × `ceil(1080/1)=1080` workgroups:

- **X: 30 × 16 = 480 threads < 1920 px → only the left ~25% of the frame is rendered.**
- Y: 1080 × 16 = 17280 threads ≫ 1080 → 16× wasted invocations (OOB stores discarded).

Additionally, the `update_boids` simulation kernel is **never dispatched** (renderer only
ever runs entry point `main`), so the flock never integrates — despite the in-file comment
claiming the kernel "is dispatched as a 1D range". The boids render from stale/initial
`extraBuffer` contents. Both files need either reordering (`main` first) + removal of the
undispatchable kernel, or a parser that selects the `main` entry's attribute.

## 2. The 54 `(8,8,1)` shaders and 4 odd-size shaders

- **54 × (8,8,1)**: all are simple per-pixel image/generative effects (no
  `var<workgroup>`, no barriers, no 1D indexing). No technical justification found —
  likely authored against the old renderer default (`getWorkgroupSize` fallback is 8×8).
  Dispatch is **correct** for them (parser reads 8,8 → ceil grid matches). Verdict:
  *accidental but harmless*; 16×16 would be marginally more efficient on most GPUs.
- **`_template_workgroup_atomics.wgsl` (256,1,1)**: justified 1D reduction template;
  entry point is `computeParticleHistogram`, not `main`, and it's not in any shader-list
  JSON (templates excluded) → not loadable by the catalog. Fine as documentation.
- **`boids.wgsl` / `kimi_flock_symphony.wgsl` (64,1,1)**: the 1D size itself is
  justified for a particle kernel, but see P1 — the kernel is unreachable and it poisons
  the parsed dispatch size for `main`. **Effectively broken.**
- **`deep-workgroup-multi-effect-blend.wgsl` (16,16,4)**: deliberate, well-engineered
  (z-lanes, bounds kept uniform around the barrier). Correctly gated: catalog entry
  carries `requiresDeepWorkgroup: true`; device side checks
  `maxComputeInvocationsPerWorkgroup >= 1024` (`device.ts:131-137`,
  `useShaderCatalogLoad.ts:72`, `RendererManager.ts:258`). Dispatch via {x:16,y:16} is
  correct (z stays 1 workgroup).

### Bounds guards

With the standard ceil dispatch, the last row/column of workgroups always has
out-of-range threads. 1126 of 1310 dispatched 2D shaders have an explicit early-return
guard; **184 do not** (full list in `lane-b-guards.json`, incl. `boids.wgsl`,
`neon-pulse-edge.wgsl` (8,8), `aurora-rift*.wgsl`, `crt-tv.wgsl`,
`gen-audio-spirograph.wgsl`). Per WebGPU spec, OOB `textureStore` is discarded and OOB
`textureLoad` returns 0, so this is **not corruption** — it is wasted work and reliance
on robustness behavior. Severity LOW repo-wide. (For `boids.wgsl` the missing guard
combines with P1's 16× y-overdispatch — still safe, just 16× waste.)

## 3. Workgroup memory (limit 16384 B)

No file exceeds the limit. One file is exactly at it:

| File | Bytes | % of 16 KB |
|---|---|---|
| `deep-workgroup-multi-effect-blend.wgsl` | **16384** | **100% — at limit, zero headroom** |
| `_template_workgroup_atomics.wgsl` (template) | 6144 | 37.5% |
| `bitonic-sort.wgsl` | 5440 | 33.2% |
| `focal-pixelate.wgsl`, `temporal-halation-freeze.wgsl`, `neon-edge-diffusion.wgsl`, `pyramid-downsample-pass1.wgsl`, `radial-hex-lens.wgsl` | 5184 | 31.6% |
| `scanline-sorting.wgsl` | 4100 | 25.0% |
| `spec-cooperative-edge-linking.wgsl` | 2048 | 12.5% |
| `_template_shared_memory.wgsl` (template) | 1296 | 7.9% |
| `spec-histogram-equalize.wgsl` | 1024 | 6.3% |
| `tone-histogram-apply.wgsl` | 24 | 0.1% |

Note: estimates use WGSL stride rules (`vec3<f32>` array elements occupy 16 B).
`deep-workgroup-multi-effect-blend` passes validation (`<=` limit) but any future field
addition to `shared_tile` breaks it.

## 4. Barriers

- All `workgroupBarrier()` calls across the 10 barrier-using shaders are in **uniform
  control flow** (the one heuristic hit in `_template_workgroup_atomics.wgsl` was
  verified a false positive — barriers sit after, not inside, the `if (lid.x < …)`
  blocks; enclosing loop trip counts are const-derived and uniform).
- `deep-workgroup-multi-effect-blend.wgsl` is exemplary: OOB threads still reach the
  barrier, only the final store is predicated.
- No `storageBarrier()` is used anywhere; none is required (no shader does
  cross-invocation storage-buffer handshakes within a workgroup; workgroup-memory
  producers/consumers are correctly paired with `workgroupBarrier()`).

## 5. Gate scripts

- `scripts/test_workgroup_gate.py`: **all 6 tests pass.**
- `check_workgroup_size_convention` (`scripts/bindgroup_checker.py:103`) run over all
  1314 shaders: **0 violations** — every `@workgroup_size` in the repo is a 3-arg
  literal. The convention (3 explicit dims) is fully enforced de facto.
- Gap in the gate: it checks *arg count* only. It does **not** check the P1 condition
  (multiple `@compute` entry points with differing sizes / entry point not named
  `main`). Adding a "first workgroup_size must belong to `fn main`" (or "single entry
  point") rule to `bindgroup_checker.py` would have caught both broken shaders.

## 6. Recommended fixes (not applied — read-only audit)

1. **P1 (high):** fix `parseWorkgroupSize` to match the attribute attached to
   `fn main` specifically, e.g. `/@compute\s+@workgroup_size\(\s*(\d+)\s*,\s*(\d+)[^)]*\)\s*fn\s+main\b/`,
   with current behavior as fallback. Mirror the fix in `wasm_internal.cpp`.
2. **`boids.wgsl`, `kimi_flock_symphony.wgsl`:** even with the parser fixed, their
   `update_boids` kernels are never dispatched — the sim is dead code at runtime.
   Either move the update into `main` (grid-stride over boids) or split into a
   two-pass graph. Currently both render a static left-quarter-broken image.
3. Add a gate rule: one `@compute` entry point per catalog shader, named `main`.
4. Consider normalizing the 54 `(8,8,1)` shaders to `(16,16,1)` (cosmetic).

## Artifacts

- `reports/audit-2026-07-21/lane-b-workgroups.md` — this report
- `reports/audit-2026-07-21/lane-b-workgroups.json` — machine-readable findings
  (histogram, multi-entry list, parser mismatches, corrected memory table)
- `reports/audit-2026-07-21/lane-b-guards.json` — guarded/unguarded shader lists
- `reports/audit-2026-07-21/lane_b_scan.py` — the scanner (reproducible)
