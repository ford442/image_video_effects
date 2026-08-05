# gen-prismatic-void-weaver-ouroboros — Optimizer notes (Batch 36, #331)

206 → 282 lines (+76). Gate: ✅ naga OK, bindgroup compatible, no extraBuffer violations.

## Contract fixes (were broken)
- **Fake audio source**: used `u.config.y` (rippleCount!) as "audio". Now band energy
  from `plasmaBuffer[0].xyz` × Audio Reactivity slider (clamped ≤ 2.0) + guarded
  engine FFT bins 1–8 average (`extraBuffer[6..13]`, `arrayLength` guard) as plasma
  shimmer. No hash-based fake spectrum.
- **Mouse y was flipped** (`voidCenter = (mx, -my, 0)`); per contract y=0 is TOP in
  both mouse_uv and pixel space → flip removed, void well now tracks the cursor truly.
- **`dataTextureA` never written** → written every frame; temporal smoothing reads
  `dataTextureC` history via `textureLoad` (mix 0.03–0.06, mids-modulated).
- **Depth flat 0.0** → real hit depth, near-is-one: `1 − dO/MAX_DIST`.
- **Alpha hardcoded 1.0** → semantic: 0.88 on hit / 0.05 background + void-glow
  luminance term, ≤ 0.97.
- **Twist Density slider was geometrically DEAD**: the twisted cross-section `q` was
  computed then discarded. fbm scale displacement is now evaluated in twisted space
  `vec3(q * 3.0, angle * 2.0)` — the twist visibly wraps the fractal scales.
- Fixed illegal `vec2.xxy` swizzle in `noise3` → `vec3(2.0) * f`.
- Removed `if (distToVoid > 0.0)` branch → branchless `max(length, 1e-3)` +
  `min(pull, 3.0)` clamp (bounded lensing, no divergence).

## Slider wiring (index order, all LIVE — names already shader-specific)
- **x Twist Density** (1–20) → cross-section twist rate, now live in geometry.
- **y Plasma Glow** (0.1–2) → void glow + plasma emission gain.
- **z Void Gravity** (0–5) → lensing strength; click adds a bounded ×1.8 surge
  (`step(0.5, mouseDown)`), still 1/d²-local and clamped.
- **w Audio Reactivity** (0–1) → scales band energy driving scale displacement
  amplitude and emission.

## Performance techniques
- **Coarse→refined SDF**: `mapScene()` evaluates the cheap torus+gravity field first;
  the 4-octave fbm (32 `sin`-hash evals) only runs when coarse distance ≤
  `FBM_CULL_DIST` (1.6) — beyond it the ≤0.53-unit displacement cannot matter.
  Far steps cost ~1 torus eval instead of torus + 32 hashes.
- **Bounding-sphere early out**: analytic ray-vs-sphere (r = 2.5 + 0.8 + 1.4); miss
  rays skip the 90-step march entirely (void-glow-only pixels).
- **Tetrahedron normals**: 4 SDF taps instead of the classic 6 (−33% on hit pixels).
- **Step clamp**: `min(dS * 0.8, MAX_STEP=1.2)` — bounded far marching; `STEP_RELAX`
  0.8 retained for the twisted, displaced (non-Lipschitz-1) SDF.
- Budget: `MAX_STEPS=90`, all loops bounded; single-writer spring state.

## Integration
- Spring-smoothed mouse in `extraBuffer[133..138]` (single-writer `gid==(0,0)` +
  `arrayLength` guard, init flag, dt clamp); void center follows smoothly.
- HDR pipeline: HDR accumulate → temporal smooth → `acesTone` → presentation; same
  RGBA to `writeTexture` + `dataTextureA`.
- Emission fbm on hit pixels only; void glow is a single `exp` for all pixels.

## Perf estimate
Miss pixels: ~2 torus evals + 1 exp. Hit pixels: ≤90 clamped steps with fbm only
inside the cull shell + 4-tap normal + 1 emission fbm. Estimated ≤0.6 ms/frame at
1080p on a modest discrete GPU. **Comfortably 60fps at 1080p.**

## JSON
`updatedParams` byte-exact. Additive only: `features` populated (8 truthful strings).
