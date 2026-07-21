# WGSL Audit Swarm — Aggregate Report (2026-07-21)

4-lane read-only swarm over **1314 shaders** in `public/shaders/`. Lane reports in this directory.

## Workgroup question (the headline)

**Yes — 16×16×1 is the norm: 1258/1314 files (~96%).** Deviations:
- 54 × `(8,8,1)` — plain per-pixel effects, no shared memory; dispatched correctly, harmless.
- 2 × `(64,1,1)` — `boids.wgsl`, `kimi_flock_symphony.wgsl` (see CRITICAL below).
- 1 × `(256,1,1)` — template. 1 × `(16,16,4)` — `deep-workgroup-multi-effect-blend` (intentional, uses exactly 16384 B workgroup storage = 100% of the 16 KB limit, gated by `requiresDeepWorkgroup` device check).
- Dispatch is per-shader (`getWorkgroupSize` + `Math.ceil(w/wg.x)`), so non-16×16 sizes are dispatched correctly **when parsed correctly**.

## 🔴 Critical

1. **`boids.wgsl` + `kimi_flock_symphony.wgsl` are structurally broken (Lanes B+D, confirmed twice):**
   - `parseWorkgroupSize` (ShaderCompilation.ts:27) returns the **first** `@workgroup_size` in file → sees `(64,1,1) update_boids`, but pipeline runs entry `main` (16×16) → dispatch covers only ~25% of frame width with 16× Y overdraw.
   - `update_boids` entry is **never dispatched** (renderer runs only `main`) → flocking sim is dead code; state kept in `extraBuffer` (256 floats) but sims need 32K/98K floats. Both render a static corner blob.
   - Same first-`@compute` flaw in WASM parser (`wasm_internal.cpp:28`).
2. **68 ungated writes to reserved `extraBuffer[0..4]` across 30 files** (Lane C) — stomps historyHead/reserved slots. Worst: gen-ghost-flame, elastic-chromatic, gen-cybernetic-mycelium-neural-web, gen-neural-bioluminescence-matrix, gen-showcase-nebula-core, gen-sierpinski-tetrahedron, gen-worley-cellular-noise.
3. **`dataTextureB` writes clobber `dataTextureC` feedback** (Lane D): frame.ts copies A→C then B→C, so shaders writing A+B and reading C get B's debug channels as sim state. Affected: liquid-touch, gen-belousov-zhabotinsky, gen-acid-lissajous. Needs fleet-wide grep (bindings 7+8 store while sampling 9).
4. **4 naga-invalid generative shaders** (Lane A): gen-ethereal-cyber-plasma-void-dragon (nested fn / missing `}`), gen-radiant-cyber-plasma-astro-griffin (`let length` shadows builtin), gen-sentient-cyber-chrono-void-serpent (i32≥u32 compare), gen-sentient-aether-plasma-nebula-moth (`color` vs `col` typo).

## 🟡 Notable

- `kaleidoscope.wgsl:89` — reads **time** (`zoom_config.x`) as audio level; grows forever, progressively destroys image.
- `quantum-foam.wgsl:191` — consumes all of zoom_config as 4 extra sliders; rotation = 2t² accelerating strobe, mouse silently bound to parallax/threshold/chroma.
- `tornado-vortex.wgsl:197` — premultiplies rgb by ≈0 alpha but final blit ignores alpha → near-black outside funnel. `anaglyph-3d` — genuine NaN: pow(negative, gamma).
- 538 unguarded risky divisions / 312 files (top denoms: `min`, `k`, `aspect`, `dot`, `density`).
- 220 files store without bounds guard (WebGPU discards OOB stores — wasted invocations, LOW); 184 2D shaders lack gid guard.
- RMW races: pixel-sand (particle write-write + writeTexture holes), physarum family (trail RMW at computed coords).
- NaN hazards: sand-dunes `pow(t-60, neg)` / `log(t)`, normalize(mouse−pos).
- Parallel slot mode never refreshes dataTextureC → feedback shaders frozen in parallel slots.

## ✅ Clean bill

- naga: 1310/1314 pass. Bindgroup checker: 1309 compatible (1 false positive = include-only `_hash_library.wgsl`).
- textureSample in non-uniform control flow: 0. f16: 0. GLSL-isms: 0. Non-canonical bindings (>13 / nonzero group): 0.
- Barriers: all workgroupBarriers in uniform control flow. Unbounded loops: 0. Workgroup storage: nothing over limit.
- Workgroup convention gate: 0 violations repo-wide (all 3-arg literals).

## Recommended fix order

1. Fix 4 naga-invalid shaders (mechanical, each ~1 line). ✅ `fix-1-naga.md`
2. boids/kimi_flock_symphony: dispatch `update_boids` + fix parser to match workgroup size by entry point, or rework state off extraBuffer. ✅ `fix-2-boids.md` (single-pass feedback sim + entry-aware parser)
3. Extend `bindgroup_checker.py` to flag literal `extraBuffer[0..4] =` writes → catches the whole 🔴 class at gate time. ✅ `fix-3-extrabuffer.md`
4. dataTextureB/C feedback contract: decide semantics, fix frame.ts copy order or shader usage. ✅ `fix-4-datac-feedback.md` (B then A; A wins; parallel C refresh)
5. kaleidoscope/quantum-foam/tornado-vortex one-liners. ✅ `fix-5-oneliners.md`
6. Guided-filter `/count` → `max(count,1.0)` template fix (clears ~8 files); optional mechanical gid-guard insertion for 220 files. ✅ guided family in fix-5; gid-guard still optional backlog

Reports: lane-a-naga.{md,json}, lane-b-workgroups.{md,json} (+guards), lane-c-patterns.md (+7 JSON artifacts, 2 scan scripts), lane-d-deepread.md.  
Fix reports: fix-1-naga.md … fix-5-oneliners.md.
