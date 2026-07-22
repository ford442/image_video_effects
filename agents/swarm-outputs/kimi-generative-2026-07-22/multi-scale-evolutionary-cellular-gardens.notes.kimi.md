# Notes: multi-scale-evolutionary-cellular-gardens (Algorithmist upgrade)

**Role:** Algorithmist
**Date:** 2026-07-22
**Shader:** `public/shaders/multi-scale-evolutionary-cellular-gardens.wgsl`
**Definition:** `shader_definitions/generative/multi-scale-evolutionary-cellular-gardens.json`

## Key changes

- **8-neighbor diffusion:** Upgraded the 4-neighbor von Neumann sampling to a full 8-neighbor Moore neighborhood with distance-correct weights (`W_ORTHO = 1.0`, `W_DIAG = 0.70710678`, normalized by `W_SUM = 6.82842712`). Species (s1, s2) and resource averages are now weighted; colony fronts diffuse visibly smoother.
- **Diffusion pull:** Added a gentle relaxation term `newS += (avgS - s) * 0.12` for both species so the weighted neighborhood actually shapes the fronts (Laplacian-style smoothing), not just the resource intake.
- **Colony-border bioluminescence (Worley-style accent):** Counts s1/s2 dominance flips across all 8 neighbors (`border = flips * 0.125`), gates it by local life density, and adds a restrained cyan-green glow line (`vec3(0.25, 0.95, 0.75)` scaled ~0.18 + bass * 0.12) with a slow pulse. Border also feeds alpha and depth slightly.
- **Real slider wiring (boilerplate removed):** Deleted `applyGenerativePrimaryControls` (generic intensity/speed/contrast remap). Each slider now drives a real sim constant:
  - `zoom_params.x` (Mutation Pressure) → mutation rate scale + per-epoch rule drift amplitude/frequency (`hash12`-seeded epoch bias on growth1/growth2).
  - `zoom_params.y` (Species Competition) → predation coefficient (`0.05 + 0.75 * p + bass * 0.25`).
  - `zoom_params.z` (Resource Fertility) → resource regeneration rate (`0.004 + 0.028 * p`).
  - `zoom_params.w` (Mouse Nurturing Power) → nurture radius (`mix(0.06, 0.30, p)`) AND strength (`mix(0.15, 1.0, p)`).
- **Rule evolution made explicit:** Slow per-epoch drift (`epoch = floor(time * (0.15 + pMutation * 0.6))`) biases growth1 up and growth2 down alternately, so the garden's fundamental behavior visibly shifts over time while staying coherent — previously-unused `time` and `hash12` are now load-bearing.
- **Final grade:** Direct `acesToneMap(colGlow * 1.15)` replaces the boilerplate control helper.
- **Sim-state contract preserved:** `dataTextureA` still written as `(newS1, newS2, newRes, 0.0)`, `dataTextureC` readback layout and update ordering unchanged; `writeTexture` + `writeDepthTexture` written every frame; canonical 13-binding layout and `@workgroup_size(16, 16, 1)` intact.

## Line count delta

- Before: 124 lines
- After: 174 lines (+50, within the +50 to +90 target; at the 174–214 range floor)

## JSON

- Added `updatedParams` (indices 0–3, names/defaults/min/max/step exactly per brief) and `"updated": true`. No other JSON fields touched; param ids/defaults/mappings preserved (saved-preset contract).

## QA flags

- **Gate:** `python3 scripts/wgsl_precommit_gate.py --files public/shaders/multi-scale-evolutionary-cellular-gardens.wgsl` → exit 0, naga OK, bindgroup compatible, 0 warnings.
- **Eyeballed constants (verify on real GPU):**
  - Diffusion pull factor `0.12` — may need tuning if fronts look over-smoothed or flickery.
  - Border glow intensity `0.18 + bass * 0.12` and glow gate thresholds (`smoothstep(0.2, 0.6, border)`, `smoothstep(0.05, 0.25, s1+s2)`) — restraint is subjective; confirm it reads as a thin accent line, not a wash.
  - Epoch drift amplitudes (`0.02` / `0.015`) and epoch rate (`0.15 + p * 0.6`) — check rule evolution is perceptible but not chaotic at high Mutation Pressure.
  - Competition ceiling `0.8` at max slider + bass — confirm species don't fully die out at slider extremes.
- **Visual QA deferred:** this VM has no GPU adapter (WebGPU unavailable, Canvas2D fallback renders black), so all visual/simulation-behavior verification must happen on a real GPU. Validation here was static only (naga + bindgroup + workgroup gate).
