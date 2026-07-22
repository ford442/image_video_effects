# molten-gold — Upgrade Notes (Kimi, role: Visualist)

**Date:** 2026-07-22 · **Brief:** swarm-tasks/kimi-generative-briefs-2026-07-22-b12/molten-gold.md

## Line delta

- Before: 165 lines → After: **234 lines** (**+69**, within the +50 to +90 target; inside the 215–255 range)

## Key changes

1. **True blackbody ramp** — replaced the ad-hoc `moltenGoldTemp` tint with a
   Tanner-Helland Planckian-locus `blackbodyColor(kelvin)` (deep red ~900K →
   gold-orange at the cited 1337.33K melt point → white-hot >4000K). Added
   `meltTemperature()` which maps the flow field to Kelvin (baseline
   `1337.33 * (0.55 + molten*0.75)`) plus bass and mouse-stir heat, and a
   Stefan-Boltzmann-flavored `pow(kelvin/1337.33, 3)` emissive falloff. The
   old fixed gold palette (goldBase/goldDark/goldHot) is gone; the whole
   image now derives from the physical ramp.
2. **Fresnel specular on flow ridges** — pseudo-normal from finite-difference
   gradient of the molten height field (2 extra 4-octave fBM taps at ±eps),
   Schlick fresnel vs. a view direction + Blinn spec lobe, masked by gradient
   magnitude so only ridge flanks shine. Specular slider (`zoom_params.z`)
   drives ridge normal strength and total fresnel gain; treble boosts it.
3. **Bass heat waves** — slow rippling thermal bands (`sin` band phase warped
   by low-freq fBM) whose amplitude/spatial frequency are driven by
   `plasmaBuffer[0].x`; the bands feed back into the fBM domain warp so they
   deform the flow, and they inject up to +420K into the temperature field.
4. **Glow clamp** — glow accumulation (incl. heatWave and bass terms) is
   `min(..., 1.2)` **before** multiplying by the blackbody tint
   (luma-echo-warp lesson).
5. **Slider rewiring** — all 4 existing params now drive shader-specific
   constants: `flow-speed` → flowSpeed + turbulence (unchanged mapping),
   `glow` → post-clamp glow gain 0.4–1.15, `specular` → fresnel ridge
   strength/gain, `highlight-freq` → spec lobe shininess 6–48 plus ripple
   shimmer frequency. No id/default renames (saved-preset contract kept).
6. Added mandatory bounds guard at entry; removed dead `audioReactive` const.

## Preserved

- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, writes to
  `writeTexture`/`dataTextureA`/`writeDepthTexture` every frame.
- Core fBM domain-warp algorithm, mouse claim pull, ripple shimmer, vignette,
  chromatic aberration, ACES tonemap, temporal feedback, semantic alpha.
- `textureSampleLevel(..., 0.0)` for sampler reads; no new/renumbered
  bindings; no reserved-word identifiers.

## QA

- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/molten-gold.wgsl`
  → **exit 0, naga OK, bindgroup compatible, 0 warnings**.
- JSON updated with `updatedParams` (index 0–3) + `"updated": true` exactly as
  in the brief; no other fields touched. `json.load` validates.
- ⚠️ **No GPU in this VM** — `navigator.gpu` unavailable, so visual QA (actual
  molten look, fresnel ridge readability, heat-wave motion feel) is deferred
  to a machine with WebGPU. Constants are conservative; if ridges read too
  weak on hardware, raise `ridgeStrength` range or the `0.55` normal scale.
