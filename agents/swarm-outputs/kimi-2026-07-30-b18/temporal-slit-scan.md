# Agent Notes — temporal-slit-scan (Batch 18, Role: Optimizer)

**Date:** 2026-07-30
**Files touched:**
- `public/shaders/temporal-slit-scan.wgsl` (rewritten/upgraded)
- `shader_definitions/post-processing/temporal-slit-scan.json` (added `updatedParams` + `"updated": true` only)

## Line count
- Before: **98** lines
- After: **160** lines (+62, within the +50…+90 target; brief target 148–188 ✅)

## Techniques implemented

### 1. Mouse scan pivot (Priority 1) — tent map
- Mouse position along the scan axis (`zoom_config.y/z`, selected branchlessly with `select(mouseUV.x, mouseUV.y, useVertical)`) becomes the pivot column/row that shows the **live current frame**.
- Age ramps away from the pivot in **both directions**: `tentAge = clamp(abs(scanPos - pivot) * 2.0, 0.0, 1.0)`.
- With no mouse input yet (`(0,0)` and not down), the classic fixed edge ramp (`rampAge = 1.0 - scanPos`) is used — blended via branchless `select(rampAge, tentAge, hasMouse)`, no `if`.
- Axis (param1) and Reverse (param3) apply to the pivot too, so they keep working on top.

### 2. Click temporal tears
- Ripple loop guarded with `min(u32(u.config.y), 50u)` exactly as mandated.
- Each live ripple (`0 ≤ age < 1.5s`) adds a radial tear: `smoothstep(0.35, 0.0, dist)` falloff with quadratic ease-out decay, contributing up to `TEAR_FRAMES = 3.0` extra history steps near the click point.
- Tear also adds a small alpha flash (`tear * 0.15`) so a fresh click reads as a time-rift.

### 3. Per-column spectral jitter
- Column index along the scan axis: `select(global_id.x, global_id.y, useVertical)`.
- FFT bin lookup: `plasmaBuffer[(scanCol % 8u) + 1u].x * mids`, clamped to ≤ **1.0 extra frame** (sub-frame cap) so the smear shimmers with the spectrum but stays smooth.

## Slider mapping (zoom_params, ids/defaults unchanged — saved-preset contract kept)
| Slider | zoom_params | Drives |
|---|---|---|
| Scan Axis (param1) | `.x` | horizontal vs vertical scan axis (also steers pivot + jitter column index) |
| Temporal Spread (param2) | `.y` | max history age 0→7 frames (still bass-widened ×(1+0.3·bass)) |
| Reverse (param3) | `.z` | flips scan direction AND the mouse pivot, branchless `select` |
| Original Blend (param4) | `.w` | mix of slit-scan output with live frame + alpha floor |

## Engine contracts preserved VERBATIM
- Binding 13 `historyTexture: texture_2d_array<f32>` declared exactly as-is.
- `let historyHead = u32(extraBuffer[4]);` — unchanged.
- `(historyHead + HISTORY_DEPTH - t_offset) % HISTORY_DEPTH` — unchanged.
- extraBuffer is **read-only** in this shader (no writes).
- All 13 canonical bindings + binding 13 kept, no renumbering; `@workgroup_size(16, 16, 1)`.
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame; all sampler reads use `textureSampleLevel(..., 0.0)`.
- Reverse flip converted from `if (doReverse)` to branchless `select(scanPos, 1.0 - scanPos, doReverse)` to fully honor the select() style.

## Deviations
- None from the brief. JSON: only `updatedParams` (verbatim from brief) and `"updated": true` appended; existing params untouched.

## Gate result
```
WGSL PRECOMMIT GATE
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | extraBuffer violations: 0
✅ public/shaders/temporal-slit-scan.wgsl — naga OK, bindgroup compatible
```
GREEN (naga + bindgroup + workgroup).
