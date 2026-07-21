# Fix 2 — boids.wgsl & kimi_flock_symphony.wgsl flocking sims + workgroup parser

**Date:** 2026-07-21 · **Agent:** Fix Agent 2 · **Status:** ✅ Complete

## Root cause (confirmed)

Both shaders declared a 1D `@compute @workgroup_size(64, 1, 1) fn update_boids`
BEFORE `@compute @workgroup_size(16, 16, 1) fn main`. Two independent bugs
resulted:

1. **Dead sim kernel:** the renderer only ever dispatches entry point `main`
   (`ShaderCompilation.ts` → `createComputePipeline({ compute: { entryPoint: 'main' } })`),
   so `update_boids` never ran.
2. **Corrupted dispatch:** `parseWorkgroupSize` returned the FIRST
   `@workgroup_size` in the file → `{64, 1}` → `main` was dispatched
   `ceil(w/64) × ceil(h/1)`, covering ~1/4 of the frame width with 16× Y
   overdraw.
3. **Impossible state buffer:** boid state was kept in `extraBuffer` (binding
   10), a 256-float audio/FFT buffer — far too small for 8192/16384 boids.
   Net effect: both shaders rendered a static corner blob.

## New dataflow (single-pass feedback sim)

Both shaders restructured to the house feedback pattern (same as
`boids-rgba-ecosystem.wgsl`, `temporal-rgb-smear.wgsl`):

- **State storage:** one boid per texel in row 0 of the data-texture feedback
  channel. `rgba = (pos.x, pos.y, vel.x, vel.y)`; pos normalized 0–1 (toroidal
  world via `fract`), vel in normalized units/sec.
- **Read:** previous frame via `textureLoad(dataTextureC, vec2<i32>(i, 0), 0)`
  (binding 9).
- **Write:** new state via `textureStore(dataTextureA, vec2<i32>(i, 0), …)`
  (binding 7). Renderer copies A→C each frame
  (`src/renderer/webgpu/frame.ts` ~L542-556, gated by
  `analyzeShaderBindings` which correctly detects writesDataA + readsDataC).
- **Single entry point:** only `main` @ `workgroup_size(16, 16, 1)`.
  - *Phase 1 (sim):* first `BOID_COUNT` flattened invocations
    (`flat = gid.y * dim.x + gid.x < BOID_COUNT`) each integrate one boid:
    full O(N²) separation/alignment/cohesion over `dataTextureC`, plus
    mouse/ripple forces, then write new state to `dataTextureA`.
  - *Phase 2 (render):* ALL invocations read boid positions from
    `dataTextureC` and splat them with each shader's existing aesthetic.
- **First frame:** `stateInvalid()` detects NaN (`s.x != s.x`), out-of-range,
  or all-zero state → `seedBoid(i)` procedural hash seeding.
- `update_boids` entry point and all `extraBuffer` state misuse removed.
  Canonical 13-binding header kept verbatim.

## Boid counts

| Shader | Boids | Notes |
|---|---|---|
| `boids.wgsl` | **256** | Was 8192 declared / 2048 rendered. 256 fits one texel row at any sane width; O(N²) = 65K texel loads per sim invocation is fine at 256 sim invocations/frame. |
| `kimi_flock_symphony.wgsl` | **256** | Was 16384 declared / 2048 rendered. Per-boid hue is now derived deterministically from the boid index (constant "instrument voice"); per-boid energy from speed + bass, replacing the 6-float state record so it fits rgba. |

## Visual identity preserved

- **boids.wgsl:** alpha scattering, soft Gaussian particles, velocity-aligned
  motion blur, velocity-direction hue, HDR emission, Reinhard tone map,
  exponential-transmittance cumulative alpha, background inversion, mouse +
  ripple attractors, brightness seeking. Added toroidal wrap-aware splat
  distances so boids crossing edges render on both sides.
- **kimi_flock_symphony.wgsl:** musical/audio-reactive identity kept — reads
  audio bands from `plasmaBuffer[0]` (bass/mids/treble, the in-repo audio
  pattern): bass pumps top speed, wander agitation, and mouse-glow pulse;
  mids drive cohesion; treble sweeps color shift. Mouse spiral force, noise
  wander, HSL voices, HDR emission, transmittance alpha, vignette, and
  `applyGenerativePrimaryControls` all retained.

## Parser fix (entry-point-aware workgroup size)

- **`src/renderer/ShaderCompilation.ts` — `parseWorkgroupSize(wgsl, entryPoint = 'main')`:**
  now scans all `@compute @workgroup_size(x, y[, z]) fn <name>` declarations
  and returns the one belonging to the requested entry point (default `main`,
  the only entry point the renderer dispatches). Falls back to first match,
  then to the legacy loose match, then 8×8. Both call sites in
  `compileShader` now pass `'main'` explicitly.
- **`wasm_renderer/wasm_internal.cpp` — `ParseWorkgroupSize`:** new
  `FindWorkgroupSizeForEntry()` helper prefers the `@workgroup_size` attached
  to `fn main`; falls back to the first one after `@compute`. Source-only
  change — CI rebuilds the WASM artifacts (emcc not run here).

## Validation

- **WGSL gate:** `python3 scripts/wgsl_precommit_gate.py --files public/shaders/boids.wgsl public/shaders/kimi_flock_symphony.wgsl`
  → **exit 0** (2/2 passed: naga OK, bindgroup compatible, 0 workgroup errors/warnings).
- **Jest (targeted):** `--testPathPattern ShaderCompilation` → 2 suites, **17/17 passed**
  (incl. 7 new `parseWorkgroupSize` regression tests in
  `src/renderer/ShaderCompilation.workgroup.test.ts`: multi-entry shaders,
  prefix-name trap `main2`, explicit entry arg, first-match fallback,
  whitespace tolerance, 8×8 default).
- **Jest (full):** 48 suites, **328 passed / 1 skipped** — no regressions.
- **ESLint:** `src/renderer/ShaderCompilation.ts` + new test file → **exit 0**.

## Caveats

- No GPU in this VM — visual verification not possible here; correctness rests
  on naga validation, bindgroup checks, and the established feedback pattern.
- Fixed `DT = 0.016` integration step (assumes ~60 fps), consistent with other
  in-repo feedback sims.
- If frame width < 256 px, out-of-range boid texels are dropped by WebGPU
  bounds rules and those boids simply reseed/don't persist — graceful.
