# gen-abyssal-chrono-coral — Upgrade Notes

**Batch:** 3B — dataTextureA Plumber
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | ~247 | 251 |
| ACES | No | No |
| dataTextureA write | No | Yes |
| Chromatic aberration | No | No |
| Temporal (dataTextureC read) | No | Yes |

---

## What Changed

Added temporal feedback loop:
- Added `textureSampleLevel(dataTextureC, u_sampler, uv, 0.0)` read (using aspect-corrected `uv`)
- Added `mix(prev.rgb * 0.96, col, 0.25)` temporal blend
- Added `textureStore(dataTextureA, coord, vec4<f32>(temporal, 1.0))` write

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Coral Density | `zoom_params.x` | 0.5 | 0.1 – 1 |
| 2 | Branch Complexity | `zoom_params.y` | 4 | 1 – 8 |
| 3 | Bioluminescence Intensity | `zoom_params.z` | 1 | 0 – 3 |
| 4 | Time Dilation Field | `zoom_params.w` | 0.2 | 0 – 1 |

---

## Validation

```bash
naga public/shaders/gen-abyssal-chrono-coral.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** Mids and treble drive bioluminescent pulses (`audioPulse = mids * 0.6 + treble * 0.9`). Bass boosts final brightness. Mids/treble also amplify node bloom and sediment disturbance glow.
- **Mouse:** `zoom_config.yz` creates a time-dilation field: distance from mouse slows local geological time (`dilation = smoothstep(dilation_strength, 0.0, dist_to_mouse) * 10.0`). `config.y` (click count) and `zoom_config.x` (click time proxy) drive sediment disturbance bloom events.
- **Depth:** **Reads** `readDepthTexture` at `depth_uv` (clamped aspect-corrected UV) and blends it with raymarched distance for the final depth write.

---

## Gotchas

- `dataTextureC` is sampled with the **same aspect-corrected `uv`** used for raymarching (`(coord - 0.5 * resolution) / resolution.y`), so temporal feedback aligns with the scene.
- Temporal blend is applied to `col` before the final alpha-premultiplied write. The `writeTexture` output uses `col * a` (instantaneous), while `dataTextureA` stores the blended value.
- The shader reads `readDepthTexture` and mixes it with its own raymarched depth. If this shader runs in slot 0 (no prior depth), the read may return uninitialized/cleared depth values depending on renderer state.
- Branch complexity (`zoom_params.y`) is used directly as the loop bound `iterations` in `map()`. Values above the default can significantly increase per-pixel cost.
