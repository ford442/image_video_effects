# gen-luminescent-chrono-fluid-astrolabe — Optimizer notes (Batch 36, #330)

206 → 296 lines (+90). Gate: ✅ naga OK, bindgroup compatible, no extraBuffer violations.

## Contract fixes (were broken)
- **Uniform truth restored**: was reading time from `config.z` (=resW!) and resolution
  from `config.xy` (=time/rippleCount!), mouse from `zoom_config.xy`, and "audio" from
  `zoom_config.w` (mouseDown). Now: `config.x`=time, `config.zw`=res, `zoom_config.yz`
  =mouse_uv (y=0 top, unflipped), `zoom_config.w`=mouseDown. Struct comments canonical.
- **Missing entry bounds guard** added (`pixel >= res → return`).
- **`dataTextureA` was never written** → now written every frame; temporal smoothing
  reads `dataTextureC` history via `textureLoad` (mix 0.03–0.06, mids-modulated).
- **Depth was flat 0.0** → real raymarch hit depth, near-is-one: `1 − t/MAX_DIST`.
- **Alpha hardcoded 1.0** → semantic: 0.85 on hit / 0.05 background + glow/shock terms, ≤0.97.
- **Dead slider bug**: `num_rings = i32(zoom_params.x)` with the Intensity slider (0–1)
  meant 0 rings rendered. Sliders rewired (see below); ring count is now a named
  constant `NUM_RINGS = 5`.
- Removed `applyGenerativePrimaryControls` boilerplate (misused uniforms, double-applied
  generic mappings); sliders now drive real constants directly.
- Fixed illegal `vec2.xxx` swizzle in `noise3D` (naga-latent) → `vec3(2.0) * f`.

## Slider wiring (index order, all LIVE)
- **x Intensity** → emission/glow gain `mix(0.35, 1.7, x)` (rings, core, dust, halo).
- **y Speed** → animation rate `mix(0.15, 2.4, y)` multiplying time (rotation + fluid).
- **z Scale** → ring radius scale `mix(0.65, 1.45, z)` **and** fluid-noise LOD bias
  `detailFreq mix(1.4, 3.2, z)` — one slider, geometry + detail scale.
- **w Mouse Influence** → gravity-well strength `w * 1.4` (bounded by 1/(d²+1) falloff).

## Performance techniques
- **Coarse→refined SDF**: `map()` first evaluates rings+core *without* the 8-hash
  `noise3D` displacement; if coarse distance > `FLUID_CULL_DIST` (1.5) it returns
  immediately. Far marching steps (the majority) pay zero noise cost; displacement
  (≤ ~0.6 units) provably can't matter beyond the cull radius.
- **Bounding-sphere early out**: analytic ray-vs-sphere (r = 3.05·ringScale + 0.6);
  rays that miss skip the whole 80-step loop (background dust only).
- **Branchless ring min**: `select` instead of per-ring `if` for d/matId updates.
- Bounded budget: `MAX_STEPS=80`, `STEP_RELAX=0.85` (fluid SDF isn't Lipschitz-1),
  `MAX_DIST=22` (was 100 — camera at z=−8, scene radius ≤ ~5).
- Background dust noise evaluated only on miss pixels (single octave, cached audio).

## Integration
- Audio: `plasmaBuffer[0].xyz` (bass→core pulse/dust, treble→ring realignment wobble,
  mids→temporal mix) + guarded engine FFT bins 1–4 (`extraBuffer[6..9]`,
  `arrayLength` guard) pumping the core halo. No hash-based fake spectrum.
- Spring-smoothed mouse in `extraBuffer[133..138]`, single-writer guard
  (`gid.x==0u && gid.y==0u` + `arrayLength`), init flag at [137], dt clamp at [138].
- Click shockwaves: `min(u32(u.config.y), 50u)`-guarded ripple loop, age window
  0–1.4 s, exponentially decaying shell — finite, spatially local.
- HDR pipeline: HDR accumulate → temporal smooth → `acesTone` → presentation;
  same tonemapped RGBA written to `writeTexture` and `dataTextureA`.

## Perf estimate
Worst case (hit pixel near surface): ~2×(5 tori + core) coarse+refined per step,
typically ≤ 30 steps after culling + 4-tap normal → well under 0.5 ms/frame at
1080p on a modest discrete GPU. Background/miss pixels are ~1 noise eval + exp.
**Comfortably 60fps at 1080p.**

## JSON
`updatedParams` byte-exact. Additive only: `features` populated (8 truthful strings).
