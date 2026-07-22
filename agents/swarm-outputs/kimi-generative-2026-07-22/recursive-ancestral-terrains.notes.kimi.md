# recursive-ancestral-terrains — Algorithmist Notes (Kimi, 2026-07-22)

**Role:** Algorithmist
**Shader:** `public/shaders/recursive-ancestral-terrains.wgsl`
**Line count:** 124 → 182 (+58, within the +50 to +90 target; final 182 is inside the 174–214 band)
**Gate:** `scripts/wgsl_precommit_gate.py` — exit 0, naga OK, bindgroup compatible, 0 warnings.

## Key changes

- **Removed the generic `applyGenerativePrimaryControls` boilerplate helper.** All 4 sliders are now wired directly into this shader's own algorithm constants:
  - `p1` Lineage Blend → `blendWeight = 0.05 + p1 * 0.6` on the cross-generational trait-mixing term, plus the lineage-color mix (`0.25 + p1 * 0.3`) and a hue offset in the ancestry palette.
  - `p2` Mutation Rate → gain `mix(0.15, 1.35, p2)` on the combined audio + bass-wave mutation driver.
  - `p3` Terrain Roughness → `ridgeAmp = p3 * 0.55`, amplitude of the new ridged-fbm octave (fully dialed out at 0).
  - `p4` Historical Depth → temporal memory weight `0.05 + p4 * 0.45 (+ bass * 0.05)` toward the previous frame.
- **Ridged-fbm octave:** new `ridgedFbm()` (abs-folded `1.0 - abs(2n-1)`, squared for sharper crests). One octave per lineage layer (3 calls, distinct seeds 3.1 / 19.3 / 41.7, higher frequencies 6.0–9.1) added under the existing fbm terms, scaled by `ridgeAmp`.
- **IQ cosine palette ancestry strata:** new `cosinePalette()` (classic a+b·cos(τ(ct+d)), d = 0.00/0.33/0.67). `lineageDepth` is a weighted centroid of gen1/gen2/gen3; palette hue is blended at exactly 0.3 into the graded color so the original earthy grading stays dominant. Slow time drift (`u.config.x * 0.015`) keeps strata alive.
- **Spatial bass mutation waves:** slow radial wave (`sin(dist*9 - t*1.7)`, Gaussian falloff `exp(-dist*2.2)`, aspect-corrected) expanding from the mouse position — falls back to canvas center via `select` when `length(mouse) <= 0.001`. Multiplies bass into the local mutation rate so beats ripple lineage change across the terrain.
- **Preserved:** core 3-lineage mouse-selected fbm structure, chromatic ridge highlights (bass→R, treble→B), lineage color modulation, temporal feedback via `dataTextureC`, semantic alpha, ACES tone map on final output (kept after removing the boilerplate helper), canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, writes to `writeTexture` / `writeDepthTexture` / `dataTextureA` every frame.
- **JSON:** added `updatedParams` (indices 0–3) and `"updated": true` exactly per brief; all existing fields untouched (param ids/defaults/mappings unchanged — saved-preset contract respected).

## QA flags

- **No GPU on this VM** — naga validation and bindgroup compatibility pass, but visual QA is deferred to a real-GPU run. Verify: ridge crests are visible but not spiky at `roughness = 1` (`ridgeAmp` max 0.55 is eyeballed); bass wave ripple is legible without strobing (wave frequency 9.0, speed 1.7, falloff 2.2 eyeballed); strata tint stays subtle at 0.3 mix.
- `select(vec2(0.5), mouse, length(mouse) > 0.001)` assumes untouched mouse is (0,0); if the engine reports a different sentinel for "no mouse", adjust the fallback test.
- `height` can now slightly exceed [0,1] when `ridgeAmp` is large (ridged octave adds up to ~0.27 on top of fbm); downstream uses (`smoothstep` ridge, alpha `clamp`) tolerate this, and ACES handles the color side — but worth an eyeball on GPU.
- Historical Depth at max (temporalBlend ≈ 0.5 + bass·0.05) may visibly trail/smear during fast mouse sweeps — intended "memory" behavior, confirm it feels good.
