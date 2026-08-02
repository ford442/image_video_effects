# Swarm Output: scanline-drift (Batch 20, Optimizer)

## Line counts
- Before: 103 lines
- After: 155 lines (+52, within target 153–193 / +50 to +90)

## Slider mapping table (saved-preset contract — ids, defaults, roles unchanged)
| Index | JSON id | Name | WGSL binding | Drives |
|-------|---------|------|--------------|--------|
| 0 | zoomParam1 | Drift Speed (0.5) | `u.zoom_params.x` | `driftSpeed = x * 2.0 * (1.0 + bass * 0.2)` — sin-drift phase rate |
| 1 | zoomParam2 | Line Height (0.1) | `u.zoom_params.y` | `lineHeight = mix(0.001, 0.1, y)` — strip height |
| 2 | zoomParam3 | Jitter Amount (0.3) | `u.zoom_params.z` | `jitter = z * 0.1 * (1.0 + mids * 0.3)` — drift/jitter amplitude |
| 3 | zoomParam4 | Color Shift (0.2) | `u.zoom_params.w` | `colorShiftBase = w * 0.05` — r/b chromatic split (doubled during click tears) |

## Techniques implemented
1. **Spring-damper tracking band (priority 1):** critically-damped 1D spring on `mouse.y`, state in `extraBuffer[133]` (position) / `extraBuffer[134]` (velocity) only; fixed 60 Hz step, ~4 Hz settle omega; branchless first-frame snap (`stateZero`); raw `mouse.y` remains the spring target; `distY`/`mouseEffect` now track the eased `bandPos` so the jitter band glides vertically.
2. **mouse.x axis:** `edgeProx = smoothstep(0.15, 0.0, abs(mouse.x - fract(uv.x + offset)))` — horizontal proximity to each strip's displaced edge subtly boosts that strip's drift (`(stripRand - 0.5) * edgeProx * jitter * 1.2`), keeping "mouse-driven" honest in both axes.
3. **Click tracking tears:** ripple loop guarded by `min(u32(u.config.y), 50u)`; each live ripple (age ≤ 0.8s) slams a hard horizontal tear on strips near its click row (`rowMask` smoothstep 0.08, `decay²` one-shot spike, per-strip/per-click hashed direction) plus a brief colorShift doubling via `tearChroma`; `tearChroma` also feeds `effectIntensity`.
4. **Depth write normalized:** `vec4(depth, 0.0, 0.0, 1.0)` → `vec4(depth, 0.0, 0.0, 0.0)`.
5. **Header comment fix:** `Category: image` → `Category: retro-glitch` (comment-only); added 2026-07-31 upgrade note.
6. **Treble honesty:** previously-unused `treble` now drives a faint per-strip 12 Hz hash flicker on the drift offset.

## VERBATIM-preserved structures
- `hash11` helper (bit-exact)
- Strip construction: `stripId = floor(uv.y / lineHeight)`, `stripRand = hash11(stripId)`
- Sin-drift + mouse-jitter offset math (both original lines exact; new offsets added as separate lines after)
- Color separation (`rOffset/gOffset/bOffset`) and fract-wrapped r/g/b taps
- `lineDark` boundary smoothsteps
- 13-binding layout, `@workgroup_size(16, 16, 1)`, all three writes every frame, `dataTextureA` = DISPLAY color

## JSON changes
- Added ONLY `"updatedParams"` (4 entries, index 0–3, names/defaults/min/max/step exactly as brief) and `"updated": true` to `shader_definitions/retro-glitch/scanline-drift.json`. Validated with `json.load`.

## Deviations
- None. extraBuffer writes confined to [133..134]. No renames/re-defaults. No reserved-word identifiers.

## Gate result
```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/scanline-drift.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ public/shaders/scanline-drift.wgsl — naga OK, bindgroup compatible
```
