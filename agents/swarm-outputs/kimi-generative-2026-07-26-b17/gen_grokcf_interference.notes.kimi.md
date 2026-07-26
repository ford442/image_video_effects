# Batch 17 Notes — gen_grokcf_interference (Cylindrical Drum Modes)

**Agent:** Kimi (Algorithmist) · **Date:** 2026-07-26

## Line delta

- **206 → 256 lines** (+50, inside target 256–296)
- JSON: `shader_definitions/generative/gen_grokcf_interference.json` written verbatim from the brief's fenced block (+37/−2 vs previous; ids/names/defaults/min/max/step/mapping untouched).

## Changes per technique

1. **Evicted `applyGenerativePrimaryControls` boilerplate (priority 1).** The shared
   intensity/speedPulse/contrast/mouseInfluence helper is gone. Slider x no longer
   fights double duty (modeScale AND boilerplate intensity) — **x drives `modeScale`
   only**. Final output is a plain `acesToneMap(finalColor * 1.1)` with no
   param-coupled brightness pulse.
2. **Honest COLOUR MODE (y).** `colourMode = clamp(u.zoom_params.y)` now feeds a real
   **hue rotation of the base colour**: `hue = fract(u_total*0.15 + time*0.04 + bass*0.08
   + colourMode)`, applied in `hsv2rgb` **before** the Chladni node-line mix, exactly as
   briefed. JSON id/name/default preserved for the saved-preset contract.
3. **Dead mouse code removed → mouse genuinely re-centres the drum.** Stale `rc`/`phic`
   (computed, never used) deleted. Now `drumCenter = 0.5 + (mouse - 0.5) * 0.45` shifts
   the polar mapping itself: `p = (uv - drumCenter) * 2.0`, so `r`/`phi` and the whole
   Bessel mode field follow the cursor.
4. **Membrane strikes (ripples loop).** Guarded `min(u32(u.config.y), 50u)`. Each live
   ripple `(uv, spawnTime, strength)` injects a decaying drum hit into `u_total`:
   localized Gaussian impulse × travelling wave packet `cos(d*22 − age*14)` × ring-down
   `exp(−age*3)`. Also accumulates `strikeGlow` (contact flash) that tints the impact
   zone hot white and boosts `blendAlpha` while the hit rings down.
5. **FFT cymatic weighting.** New `fftModeWeight(mode)` = `0.6 + 0.9 *
   plasmaBuffer[1u + (mode % 8u)].x` multiplies every drum mode, so each eigenmode
   family is driven by its matching FFT bin (truer cymatics) on top of the existing
   bass/mids/treble band weights.
6. **Refactor for clarity, same soul.** Inline HSV chain extracted to `hsv2rgb()`;
   A&S J0/J1 polynomial coefficients and tabulated zeros (2.4048, 5.5201, 3.8317,
   7.0156, 5.1356, 6.3802) preserved **verbatim**; J2/J3 recurrence untouched.
7. **Rim highlight.** Faint fixed-edge highlight at `r/R = 0.9` anchors the clamped
   boundary visually (u = 0 Dirichlet rim).

## Slider wiring (all 4 read, no dead sliders)

| Slider | Field | WGSL use |
|---|---|---|
| Mode Scale (0.4) | `zoom_params.x` | `modeScale = mix(0.5, 2.5, x)` — radial scale of polar frame only |
| Colour Mode (0.5) | `zoom_params.y` | `colourMode` → hue rotation added to displacement hue before Chladni mix |
| Node Sharpness (0.5) | `zoom_params.z` | `nodeSharp = mix(2.0, 30.0, z)` — Chladni node-line band width |
| Mode Count (0.6) | `zoom_params.w` | `modeCount = floor(w*6)+2` — gates (0,2)/(2,1)/(1,2)/(3,1) mode families |

## Binding compliance

- Canonical 13-binding layout (0–12) preserved, no additions/renumbering; no binding 13.
- `@workgroup_size(16, 16, 1)` kept.
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame.
- `dataTextureA = (u_total, r, phi/2π, blendAlpha)` — raw sim state, **never clamped/tonemapped**.
- `extraBuffer` declared but **never written** (no [0..132] violations; no [133..255] state needed).
- Sampler reads via `textureSampleLevel(..., 0.0)`; storage reads via direct indexing.
- No reserved-keyword identifiers.

## QA / gate results

- `wgsl_precommit_gate.py --files …` → **PASS, 0 warnings** (naga binary not installed in
  this VM → naga step skipped; bindgroup compatibility + workgroup convention both pass).
- `audit_extrabuffer.py --files …` → **AUDIT PASS** (0 new violations, 0 dynamic writes).
- `audit_dead_sliders.py --files gen_grokcf_interference` → **AUDIT PASS** (0 dead sliders).
- Flags: none. GPU visual check not possible in headless VM (no WebGPU adapter) — verified
  statically via gates + manual review.
