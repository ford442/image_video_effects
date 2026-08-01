# Agent Notes — signal-modulation (Batch 19, Kimi Visualist)

**Date:** 2026-07-31
**Shader:** `public/shaders/signal-modulation.wgsl`
**JSON:** `shader_definitions/visual-effects/signal-modulation.json`

## Line counts

- WGSL: **102 → 161** (+59, inside target 152–192)
- JSON: 48 → 82 (only `updatedParams` + `updated: true` appended)

## Per-slider mapping (saved-preset contract — roles unchanged)

| Slider | JSON id | Name | WGSL source | Drives |
|--------|---------|------|-------------|--------|
| 0 | `freq` | Base Frequency | `u.zoom_params.x` | `freq = mix(1.0, 50.0, x) * bass_env(bass, mids)` — carrier frequency |
| 1 | `amp` | Distortion Amt | `u.zoom_params.y` | `amp = mix(0.0, 0.5, y) * (1.0 + mids * 0.3)` — carrier amplitude, line width, displacement |
| 2 | `speed` | Scroll Speed | `u.zoom_params.z` | `speed = mix(0.0, 10.0, z) * (1.0 + treble * 0.25)` — phase scroll rate |
| 3 | `shift` | Color Split | `u.zoom_params.w` | `colorSplit = w * 0.02 * (1.0 + bass * 0.1)` — r/b chromatic separation |

No renames, no re-defaults, mapping order identical to the prior shader.

## Techniques implemented

1. **Real FFT spectral bands (priority 1):** the fake `bandNoise = fract(sin(band * 12.9898 + time) * 43758.5453)` drive is replaced. Bands 0–7 (`floor(uv.y * 8.0)`) now read engine FFT bins 1–8 via `plasmaBuffer[u32(band) + 1u].x` (clamped 0–1), mapped through the original `mix(0.1, 1.0, …)` floor and the preserved `(1.0 + bass * 0.5)` boost. The hash term survives ONLY as ±10% jitter: `* (0.9 + 0.2 * bandJitter)`.
2. **Spring-damper wave origin:** critically damped spring (`stiffness = 36.0`, `damping = 2*sqrt(stiffness)`, `dt = 0.016`) in `extraBuffer[133..136]` (pos.xy, vel.xy). Raw mouse (`u.zoom_config.yz`) remains the spring target; zero-state init snaps to the cursor. `proximity` now measures distance to the spring-glided origin, so the proximity-warped carrier trails the cursor.
3. **Click carrier bursts:** ripple loop guarded by `min(u32(u.config.y), 50u)`. Each live ripple (`age = time - rp.z`, ~1.2s fade, `fade²`) injects an expanding radial band (`exp(-((ringDist - ringRadius) * 10)²)`, radius `age * 0.35`) that adds up to +0.85 local `signal` boost and up to ×3 extra chromatic split (`1.0 + clickChroma * 2.0` on the offset).

## VERBATIM-preserved structures (CAUTION list)

- `bass_env` and `huePreserveClamp` helpers — byte-identical; the `huePreserveClamp(finalColor, 1.8)` cap call kept.
- Carrier wave construction: `wave = 0.5 + amp * sin(...)` / `distanceToWave = abs(uv.y - wave)` / `1.0 - smoothstep(lineWidth, lineWidth + 0.005, distanceToWave)` (only `let signal` → `var signal` so the click boost can accumulate; expression unchanged).
- `displacement = signal * amp * 0.1` and the r/g/b chromatic tap structure (`uvR`/`uvG`/`uvB` clamps + `vec3(r, baseColor.g, b) + glow`).
- Noise floor block verbatim.
- `bandMask` line verbatim; alpha/depthOut/final store block unchanged. `dataTextureA` stays DISPLAY color.

## JSON changes

Added ONLY the `"updatedParams"` array (indices 0–3, names/defaults/min/max/step exactly as given in the brief) and `"updated": true`. No other keys touched; `python3 -m json.tool` validates.

## Deviations from the brief

- None. (`signal` changed from `let` to `var` — required to inject the mandated click-burst boost; the smoothstep construction itself is verbatim.)

## Gate result

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/signal-modulation.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ public/shaders/signal-modulation.wgsl — naga OK, bindgroup compatible
```

**GREEN — 0 warnings, 0 extraBuffer violations.**
