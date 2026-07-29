# Agent Notes: interactive-glitch-brush (Batch 17, Interactivist)

**Date:** 2026-07-30
**Shader:** `public/shaders/interactive-glitch-brush.wgsl`
**JSON:** `shader_definitions/interactive-mouse/interactive-glitch-brush.json`

## Line count

- Before: **95** lines
- After: **161** lines (**+66**, inside the +50..+90 target band; brief target 145–185 met)

## Gate result

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/interactive-glitch-brush.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | extraBuffer violations: 0
✅ public/shaders/interactive-glitch-brush.wgsl — naga OK, bindgroup compatible
```

(naga WAS available in this VM and passed; bindgroup + workgroup also green.)

## What each slider now drives

| Index | Param (id unchanged) | WGSL mapping (unchanged contract) | Visible effect |
|-------|----------------------|-----------------------------------|----------------|
| 0 (`zoom_params.x`) | Brush Size (`brush_size`) | `brushSize = x*0.3 + 0.05` | Radius of the spring-driven brush falloff AND the radius of every click grenade zone |
| 1 (`zoom_params.y`) | Glitch Intensity (`intensity`) | `intensity = clamp(y)` → `audioIntensity` | Amplitude of block displacement (scaled by bass/mids), i.e. how far glitch blocks smear |
| 2 (`zoom_params.z`) | Block Scale (`block_scale`) | `blockScale = z*50 + 5` | Size of the quantized glitch blocks (VERBATIM `blockUV` quantization) |
| 3 (`zoom_params.w`) | Color Split (`color_split`) | `colorSplit = clamp(w*0.1)` | Base chromatic tear distance; r/b tears independently modulated by treble bins 5 and 8 |

All four param ids, names, defaults, min/max/step, and mapping order preserved — saved-preset contract intact.

## Techniques implemented

1. **Spring-damper brush (priority 1):** Critically-damped spring (`stiffness=60`, `damping=2*sqrt(60)`, fixed `dt=0.016`) eases the brush position toward the cursor. State lives in `extraBuffer[133..136]` (pos.xy, vel.xy) — inside the [133..255] shader-state region. Includes a branchless first-touch snap (`snapF`) so the brush never glides in from (0,0), and parks in place when the mouse is invalid (`springGoal = mix(sPos, mousePos, validF)`). Brush mask is now a soft `smoothstep` falloff driven by the spring position, so smears feel painted.

2. **Click glitch grenades:** Ripple loop guarded with `min(u32(u.config.y), 50u)`. Each live ripple (age 0..1s, branchless `step(0.0,age)*step(age,1.0)`) spawns a decaying glitch zone of radius ~brushSize at its click point. Inside a grenade zone (`grenade > 0.05`) block displacement is FORCED (`select(offsetX, grenadeOffsetX, ...)`) and inversion is forced via `invertNade` (zone + block hash gate), plus a small brightness punch (`1.0 + grenade*0.35`) that decays with the blast. Combined with the brush via `activeMask = clamp(max(brushMask, grenade))`.

3. **Per-channel split shimmer:** Red tear offset driven by `plasmaBuffer[5].x`, blue tear by `plasmaBuffer[8].x` (`splitR = colorSplit*(0.5+bin5)`, `splitB = colorSplit*(0.5+bin8)`) — the chromatic tear shimmers independently per channel across the spectrum; the slider remains the base amount.

## Branchless compliance (CAUTION)

- No `if`/`discard` on any per-pixel path; all new logic uses `select`/`step`/`smoothstep`/`mix`/`max`. (The single bounds-check `return` at entry and the `for` loop over ripples match the pre-existing patterns.)
- `blockUV = floor(uv * blockScale) / blockScale;` and the scanline modulo (`fract(uv.y * resolution.y * 0.5) < 0.5` + `select(...*0.8)`) preserved **VERBATIM**.
- `dataTextureA` remains DISPLAY color (same value as `writeTexture`).
- `extraBuffer` touched only at indices 133–136.
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, all sampler reads via `textureSampleLevel(..., 0.0)`, writes to `writeTexture`/`writeDepthTexture`/`dataTextureA` every frame. No reserved-keyword identifiers (`springGoal` used instead of `target`).

## JSON change

Added ONLY the `updatedParams` array (indices 0–3, names/defaults/min/max/step exactly as in the brief) and `"updated": true`. No existing params renamed, re-defaulted, or reordered. Validated with `json.load`.

## Deviations

- Brief said spring state at `extraBuffer[133..134]` (position); velocity needs two more slots, so I used `[133..136]` (pos.xy, vel.xy) — still well inside [133..255] and matches the established pattern in `lava-lamp-blobs.wgsl`.
- The final brush→glitch composite changed from a hard `select(color, glitchColor, inBrush)` to `mix(color, glitchColor, activeMask)` to support the soft brush falloff and gradual grenade decay — still branchless, same soul (glitch only inside active zones).
- Original `invertCond` (`random(vec2(time,noise)) > 0.95`) kept as `invertBase = step(0.95, ...)` and OR-ed (via `max`) with the grenade inversion gate.
