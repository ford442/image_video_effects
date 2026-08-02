# Completion: digital-haze (kimi, swarm b29)

## Changes

- **Wired the dead slider (priority 1):** `hazeDensity` is now `var` and scaled by
  `hazeDensity *= mix(0.4, 1.6, u.zoom_params.w)` — default 0.5 yields exactly 1.0
  (bit-identical to the previous hardcoded extinction). 'Haze Density' is real.
- **Sprung clear window:** raw mouse (`u.zoom_config.yz`) stays the spring target;
  the clear window follows a critically-damped spring (K=40, C=2*sqrt(K), fixed
  dt=1/60) persisted in `extraBuffer[133..136]` (pos.xy, vel.xy). All threads
  integrate one deterministic step; thread (0,0) writes back. Aspect correction kept.
- **Click clear pulses:** ripple loop guarded by `min(u32(u.config.y), 50u)`; each
  live ripple (age in (0, 1.5s)) punches a clear hole — mask reduced by
  `smoothstep(0.2, 0.0, rDist) * exp(-age * 2.0)` in an aspect-corrected ~0.2 radius.
- **Per-cell FFT static:** `noiseVal` modulated per pixel-cell by its own bin,
  `plasmaBuffer[(u32(cellHash * 8.0) % 8u) + 1u].x * 0.3` (`cellHash` from the
  quantized cell id), so the digital static flickers across the spectrum.
- **Header fix (comment-only):** 'Category: distortion' → 'Category: interactive-mouse'.

## Contracts preserved (CAUTION block)

- `SIGMA_T_HAZE` / `SIGMA_T_CLEAR` / `STEP_SIZE` constants verbatim.
- Beer-Lambert transmittance / optical-depth math verbatim.
- Volumetric composition (`inScattered + transmittedClear + transmittedHaze`) verbatim.
- Quantized-UV pixelation, green tint, volumetric alpha (`alpha = 1 - transmittance`) verbatim.
- `dataTextureA` stays DISPLAY color (`finalOut`); writes `writeTexture`,
  `writeDepthTexture`, `dataTextureA` every frame.
- Canonical 13-binding layout unchanged; `@workgroup_size(16, 16, 1)`; no binding 13.
- `extraBuffer` touched in `[133..136]` ONLY (within the [133..255] allowance).
- All 4 sliders exact: ids/names/defaults/min/max/step/mapping order unchanged
  (pixel_strength→x, clear_radius→y, noise_amount→z, haze_density→w); JSON updated
  verbatim from brief with additive `updatedParams` (index 0–3) + `updated: true`.
- Engine uniform truth respected: config=[time,rippleCount,resW,resH],
  zoom_config=[time,mouseX,mouseY,mouseDown].

## Metrics

- `public/shaders/digital-haze.wgsl`: 119 → **191 lines** (target 169–209, +72).
- `shader_definitions/interactive-mouse/digital-haze.json`: brief JSON applied verbatim.
- **naga:** `Validation successful` (clean, first pass).
- No other files touched; no git; precommit gate not run (coordinator's job).

## Coordinator closeout

- Final lines: **119 → 198 (+79)**. Added an explicit `[137]` initialization flag so top-left is a valid cursor target, and clamped jittered haze samples at image boundaries.
- `Haze Density` remains bit-exact at its default; new state is single-writer and confined to `[133..137]`.
- Final focused gate, dead-slider/strict-buffer audit, JSON/list parity, Jest, and production build: pass.
