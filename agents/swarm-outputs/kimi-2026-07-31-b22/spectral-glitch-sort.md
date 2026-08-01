# Swarm Output: spectral-glitch-sort (Batch 22, Optimizer)

**Date:** 2026-07-31
**File:** `public/shaders/spectral-glitch-sort.wgsl`
**Lines:** 108 → 178 (+70, target 158–198 ✅)

## Slider map (saved-preset contract, unchanged ids/defaults)

| Index | Param | zoom_params | Wiring |
|-------|-------|-------------|--------|
| 0 | Sort Length (strength, default 0.3) | `.x` | `mix(0.0, 0.5, x) * (1.0 + bass * 0.4)` — max sort displacement |
| 1 | Luma Threshold (default 0.4) | `.y` | `smoothstep(threshold, threshold + 0.2, luma)` dispFactor floor |
| 2 | Direction (default 0 = 0 rad) | `.z` | `z * 6.28` base sort axis angle; tears perturb it additively |
| 3 | Digital Noise (default 0.2) | `.w` | branchless `mix(1.0, noiseVoiced * 2.0, w)` per-block modulation |

## Techniques applied

1. **Aspect-corrected mouse influence (Priority 1):** `aspect = dims.x / max(dims.y, 1.0)`; both `uv` and mouse scaled by `vec2(aspect, 1.0)` before `distance()` — influence zone is circular on wide canvases (was elliptical).
2. **Spring-damped epicenter (Priority 1):** critically-damped semi-implicit spring (`springK = 0.16`, `damping = 0.74`) eases raw cursor → `mousePos`; persistent state in `extraBuffer[133..136]` (pos.xy + vel.xy). First-frames snap guard (`time < 2.0`, zero-state check) avoids fly-in from origin.
3. **Click sort tears:** ripple loop guarded `min(u32(u.config.y), 50u)`; branchless live-window mask (~0.8s linear fade) + aspect-corrected radial falloff; per-click tear direction from `hash12(ripple.xy + ripple.z)`; accumulates `tearAngle` (rotates sort dir locally) and `tearBoost` (spikes `finalStrength` by `tearBoost * strength`).
4. **Per-block FFT voices:** `binIndex = (u32(blockUV.x * 8.0) % 8u) + 1u`; `plasmaBuffer[binIndex].x` voices each glitch-block column → `noiseVoiced = noiseVal * (1.0 + blockVoice * 1.5)` used in the noise modulation.
5. Alpha gains a small `clamp(tearBoost, 0.0, 1.0) * 0.1` term so tears read in the alpha channel.

## VERBATIM preserved (per CAUTION list)

- `getLuma` / `hash12` helpers — untouched.
- `dispFactor = smoothstep(threshold, threshold + 0.2, luma)` — untouched.
- dir/offset displacement: `let dir = vec2<f32>(cos(...), sin(...));` + `let offset = -dir * finalStrength * dispFactor;` — structure intact (angle arg now `sortAngle = angleParam + tearAngle`, per the click-tear requirement).
- Branchless chromatic aberration: `aberScale` smoothstep + r/b `mix` — untouched.
- Treble shimmer: `finalColor += vec3<f32>(0.05) * treble * noiseVal;` — untouched (uses raw `noiseVal`).
- 13-binding layout, `@workgroup_size(16, 16, 1)`, all three writes every frame, `textureSampleLevel(..., 0.0)`, `dataTextureA` = DISPLAY color.
- extraBuffer writes ONLY [133..136] (within [133..255]); [0..4] and [5..132] untouched.

## JSON changes

`shader_definitions/retro-glitch/spectral-glitch-sort.json`: added ONLY `updatedParams` (4 entries, index 0–3, names/defaults/min/max/step exactly per brief) + `"updated": true`. `params` block untouched. JSON validated with `json.load`.

## Deviations

- Noise-modulation line now uses `noiseVoiced` instead of `noiseVal` — this IS the brief's per-block-FFT-voices requirement (not in the CAUTION verbatim list).
- Alpha expression extended with the tear term (alpha not on the CAUTION verbatim list).

## Gate result

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/spectral-glitch-sort.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ naga OK, bindgroup compatible — GREEN, 0 warnings
```
