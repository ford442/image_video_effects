# gen-bioluminescent-cyber-aether-void-seahorse — Algorithmist b35 notes

**Lines:** 153 → 320 (+167). Over the suggested +50–90 envelope — justified
per b32 precedent (COÖRDINATOR_REVIEW retained 235–259-line drafts when
required geometry demanded it): this shader was a skeletal raymarcher missing
the canonical header entirely, and the SDF anatomy + normals + warped-noise
shading are the upgrade itself, not decoration.

## Contract repairs (was non-compliant)

- **Uniforms struct was non-canonical** (`resolution, time, frame, view_matrix,
  proj_matrix, camera_pos`) → replaced with exact canonical
  `config, zoom_config, zoom_params, ripples`; all `u.time` reads → `u.config.x`.
- Added mandatory resolution bounds guard on `global_invocation_id`.
- Now writes `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame
  (previously only `writeTexture`).
- Alpha was hardcoded 1.0 → semantic (hit mask + luminance contribution).
- Depth was absent → generated relief depth (`1 - t/maxDist` on hit, nebula
  relief on miss).

## Techniques integrated (algorithmic depth domain)

1. **SDF smooth-union anatomy** — kept the original bent-spine warp and the
   4-iteration abs-fold fractal tail verbatim in spirit, then composed a real
   creature around them: bent ellipsoid body + belly, head, two-sphere tapered
   snout capsule chain, coronet ridge, all `smin`-blended; plus a wavering
   **dorsal-fin membrane** (thin shell clipped to a body-region disc, mids
   modulate undulation frequency).
2. **Orbit trap on the fractal tail** — min |p| tracked across the fold
   iterations; combined with fin-membrane distance into one filament-proximity
   field → cyan bioluminescent threads along the curl (multi-scale micro
   detail riding the macro SDF).
3. **Domain-warped FBM** (value-noise FBM with smooth trilinear interpolation,
   replacing the old non-interpolated hash "fbm") — used for macro surface
   bands + micro surface breakup on hit, and for the quantum-reef void nebula
   on miss. Time enters only as a smooth third noise axis → temporal coherence.
4. **Tetrahedral SDF normals + 3-point lighting + Fresnel rim + treble-pumped
   specular** — the "cyber" sheen is now geometric, not a sin(time) color lerp.
5. **Temporal history** — 12% blend with `dataTextureC` (display history),
   state written to `dataTextureA` each frame.
6. **Ripple pulses + bounded mouse** — guarded ripple loop
   (`min(u32(u.config.y), 50u)`), finite 2.5 s exponentially-decaying rings,
   spatially local; mouse orbits the camera within ±0.6 rad (no y-flip);
   mouse-hold adds a bounded Gaussian aether glow at the cursor.

## Slider rewiring (all 4 live, updatedParams untouched / byte-exact)

- p1 `zoom_params.x` **Bioluminescent Shift** — was a +0.01 brightness hack →
  now phases the IQ cosine emission palette (surface bands + nebula + rings).
- p2 `zoom_params.y` **Audio Reactivity** — scales the full bass/mids/treble
  vector (body breathing, fin frequency, emission pump, trap glow, glints).
- p3 `zoom_params.z` **Void Intensity** — was a global brightness multiply →
  now controls void nebula gain/contrast (deeper, darker void at high values).
- p4 `zoom_params.w` **Evolution Speed** — kept as the time multiplier.

## Perf estimate

map() ≈ 6 sphere/ellipsoid evals + fin shell + 4-iter fold. Called ≤64×
(march, 0.9 step relaxation, early hit/far exits) + 4× (tetrahedral normal).
Warped FBM (≈4 fbm ≈ 16 vnoise) runs once per pixel on the taken branch only.
Ballpark: ~2× the cost of the old shader, comparable to
gen-glacial-aether-quantum-cavern (b32 reference). Comfortable at 1080p on
real GPUs; bounded loops throughout.

## Gate

`wgsl_precommit_gate.py --files …` → **2/2 passed** (naga OK, bindgroup
compatible, 0 extraBuffer violations). JSON: additive features/description
only; `updatedParams` verified byte-exact.
