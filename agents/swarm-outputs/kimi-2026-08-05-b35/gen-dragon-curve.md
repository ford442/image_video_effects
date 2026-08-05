# gen-dragon-curve — Visualist upgrade (batch 35, #318)

## Changes
- **Thin-film iridescence** fused into the existing HSV neon: cos-palette phase
  = fold order along the curve + normalized distance falloff + slow time drift
  (`thinFilm()` helper). Gives the line a dragon-scale / oil-slick sheen
  without touching the fractal math.
- **Two-temperature glow rig** (replaces the single neutral glow):
  - KEY: tight warm filament (`warmKey` ≈ 3200K-ish tint) hugging the line,
    HDR ≈ 3.6 peak before tonemap (bloom-ready).
  - FILL: broad cool halo 6× wider (`coolFill` ≈ 9000K-ish) — cheap volumetric
    glow approximation, shimmered by **guarded engine FFT bins 1–8**
    (`arrayLength(&extraBuffer) > 13u` guard).
  - **Dynamic temperature shift**: `treble − bass` steers both tints cooler/
    warmer in real time.
- **Split-tone grading** (`splitTone()` helper): cool indigo shadows → warm
  gold highlights, keyed on luma, applied in HDR before ACES.
- **Atmospheric depth haze**: far fragments (low `depth`) sink into a bounded
  cool fog tinted by the halo; suppressed on the hot core so the fractal stays
  legible.
- **Vibrance**: mids-driven saturation lift post-ACES, clamped.
- Feedback history read switched from `textureSampleLevel(dataTextureC, u_sampler,…)`
  to **non-filtering `textureLoad`** (rgba32float contract compliance).
- All 4 sliders keep their exact existing mappings (zoom / glow width / fold
  chromatic aberration / temporal feedback) via `u.zoom_params.x/y/z/w`.

## JSON
Additive only: description + `features` list updated. `updatedParams` array
byte-exact.

## Invariants
13-binding header verbatim, Uniforms struct unchanged, 16×16×1 workgroup,
writes writeTexture/writeDepthTexture/dataTextureA every frame, no banned
builtins, no extraBuffer writes. Alpha stays semantic (curveDensity-driven);
depth output unchanged (relief × scene depth).

## Perf estimate
Same O(maxSeg ≤ 512) segment loop dominates. Added cost: ~2 exp() + a few
vec3 mixes per pixel + one 8-iteration guarded FFT loop. ≈ +3–5% frame cost
vs. baseline. 178 → 238 lines.

## Gate
`wgsl_precommit_gate.py` — ✅ naga OK, bindgroup compatible, 0 extraBuffer
violations.
