# Agent Notes: neon-topology (Batch 18, Algorithmist)

**Date:** 2026-07-30
**Shader:** `public/shaders/neon-topology.wgsl`
**JSON:** `shader_definitions/visual-effects/neon-topology.json`

## Line count

- Before: 98 lines
- After: 150 lines (+52, within the +50 to +90 target; 148–188 range)

## What each slider now drives (JSON param order, unchanged)

| index | id | name | zoom_params | WGSL role |
|-------|----|------|-------------|-----------|
| 0 | density | Line Density | x | `contourLevels = x * 10 + 3 + bass*4` (unchanged) |
| 1 | height | Height Scale | y | `contourPhase = depth * mix(0.5, 2.0, y) * contourLevels` — stretches the contour field height (default 0.5 → factor 1.25, per brief) |
| 2 | mouse | Mouse Force | z | Mouse lens strength: `depth += lensMask * z * 0.25 * mouseDownBoost` (aspect-corrected smoothstep falloff, ~0.35 radius) |
| 3 | glow | Glow Strength | w | `intensity = w * 2.0 * bass_env(bass, mids)` — emission brightness (this mapping was previously on z) |

## Techniques implemented

1. **Mouse lens (priority 1):** The shader was tagged `mouse-driven` but never read the mouse. Now reads `u.zoom_config.yz`, builds an aspect-corrected `smoothstep(0.35, 0.0, dist)` mask (`mouseLensMask` helper), and bumps the sampled depth by `mouseMask * mouseForce * 0.25` (×1.5 while mouse is down via `zoom_config.w`). Contours visibly warp around the pointer. A faint rim ring traces the lens radius (`rim` term, scaled by Mouse Force).
2. **Honest sliders / dead-code removal:** y no longer feeds the alpha helper's edge threshold (now a `const EDGE_THRESHOLD = 0.07` = old default); w no longer drives hue. The hue shift moved to a slow constant drift `time * 0.15` (× TAU ≈ the old 1 rad/s drift; `+ PI` preserves the old default 0.5×TAU hue offset so the color identity survives). The dead `alpha` variable was removed; its useful terms (edge-preserve mask, phantom-line alpha) were folded explicitly into `finalAlpha`.
3. **Click contour quakes:** Loops `u.ripples[]` guarded by `min(u32(u.config.y), 50u)`. Each live ripple (age < 1.5s) adds a decaying, expanding sinusoidal depth ring (`sin(dist*24 - age*8) * exp(-dist*5) * exp(-age*2.5)`) into the depth field (`depth += quake * 0.1`), plus a `quakeGlow` term that feeds emission and alpha so the rings flash as they pass.

## Preserved VERBATIM (structure)

- Branchless contour construction: `fract` phase + `smoothstep(0.05, 0.0, contour)` lines + `step(0.95, fract(phase*0.2))` major step + `line * (1.0 + major * 0.6)`.
- `edgePreserveAlpha` 5-tap depth helper (byte-identical body).
- Phantom-contour audio term: `(depth + audioBass * 0.1) * contourLevels * 0.5` → `smoothstep(0.03, 0.0, fract(...)) * audioBass * 0.5`.
- 13-binding canonical layout, `@workgroup_size(16, 16, 1)`, all three stores every frame, `textureSampleLevel(..., 0.0)` for sampler reads, `dataTextureA` = DISPLAY color. `extraBuffer` untouched (no [133..255] usage needed).

## JSON changes

Added ONLY `updatedParams` (indices 0–3, matching existing names/defaults, min 0.0 / max 1.0 / step 0.01) and `"updated": true`, exactly as in the brief. No existing param renamed, re-defaulted, or reordered.

## Deviations

- **Default look:** Height Scale default 0.5 → factor 1.25 makes contours ~25% denser than before (mandated by the brief: `mix(0.5, 2.0, y)`). All other defaults reproduce the previous look (intensity 1.0, contour levels unchanged, hue offset preserved via `+ PI`).
- **writeDepthTexture** now stores the lens/quake-warped `depth` (the field the contours actually render) instead of the raw sample — keeps downstream depth consumers coherent with the displayed topology.
- Small additions beyond the brief's literal text: `mouseDownBoost` (×1.5 lens while pressed), lens `rim` ring, and `quakeGlow` in emission/alpha — all branchless and scaled by existing sliders/ripples only.

## Gate result

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/neon-topology.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | extraBuffer violations: 0
✅ public/shaders/neon-topology.wgsl — naga OK, bindgroup compatible
```

GREEN: naga + bindgroup + workgroup all pass. JSON also validated with `json.load`.
