# gen-astro-kinetic-chrono-orrery — Optimizer pass (Batch 35, 2026-08-05)

199 → 285 lines (+86). Gate: ✅ naga OK, bindgroup compatible, 0 extraBuffer violations.

## Changes

**Contract repairs**
- `tan(E*0.5)` (not in WGSL) → clamped `sin/cos` quotient in `particlePosition`.
- Added the mandatory resolution bounds guard (was deriving dims from
  `textureDimensions(writeTexture)` with no guard).
- `dataTextureA` was never written → now written every frame with temporal
  history (kinetic trails, decay 0.88); presentation uses the smoothed HDR color.
- Depth was a copy of `readDepthTexture` (source depth) → real raymarch hit
  depth, near-is-one (`clamp(1.0 - (t - 0.5)/9.0, 0, 1)`), sky rays 0.
- Fixed misleading Uniforms comments (y = rippleCount, w = mouse_down).

**Performance (the big hoist)**
- The original `map()` recomputed, **per raymarch step**: 2 mouse-rotation
  matrices (4 trig) + 6 full Kepler body solves (each 6 Newton iterations with
  sin/cos, plus a tan/atan/sqrt chain). At up to 100 steps that is ~600 Kepler
  solves per pixel per frame.
- Now: body positions/radii/temps and both rotation matrices are computed
  **once per pixel** into `var<private>` caches (`g_bodies`, `g_bodyProps`,
  `g_rotXZ/g_rotYZ`); `map()` is just the central sphere + culled disk +
  N sphere distances. ~2 orders of magnitude less trig.
- Analytic bounding-sphere cull (r = 4.4): rays missing the scene skip the
  march entirely and go straight to the starfield; hitting rays start at the
  sphere entry point instead of the camera plane (saves ~4.6 units of marching).
- Accretion disk: coarse annular-slab SDF (`|y|, radial` bounds) gates the
  expensive density eval (exp + sin + hash); outside the slab the conservative
  slab distance keeps the march correct and fast.
- `MAX_DIST` 100 → 14 (scene fits in the bound sphere; the old value let rays
  wander 100 units).
- MAX_STEPS 100 → 96 bounded; near-miss glow integral is one `exp` per step.

**Sliders — were 3 of 4 DEAD, now all LIVE**
1. Complexity (1–10, default 4) → orbiting body count `clamp(round(c)+2, 3, 10)`
   (default 4 → 6 bodies = original look; hard-capped by the cache array).
2. Speed → simulation time rate (as before).
3. Glow Intensity (0–3) → near-miss bloom integral gain + bloom alpha.
4. Audio Reactivity (0–1) → global scale on bass/mids/treble and FFT drive
   (disk turbulence + star twinkle scale with it; 0 = fully static scene).

**Integration**
- Audio: canonical `plasmaBuffer[0].xyz` + guarded FFT bins 1–8
  (`arrayLength` guard, indices 5–12). No fake spectrum.
- HDR-ready: bloom and blackbody terms exceed 1.0 in rgba32float.
- Semantic alpha: surface density, bloom contribution, star brightness;
  deep space stays transparent (0).
- Named constants (`BOUND_RADIUS`, `MAX_BODIES`, `FOG_COLOR`, `GLOW_COLOR`).

## Perf estimate
Per pixel: ≤10 Kepler solves + ≤96 cheap SDF steps (mostly far fewer thanks to
the sphere-entry start and early surface exit), one exp per step. Estimated
5–10× faster than the original at 1080p; comfortably 60 fps on mid-range GPUs.

## JSON
`updatedParams` verified byte-exact vs HEAD. Only additive `features` list added.
