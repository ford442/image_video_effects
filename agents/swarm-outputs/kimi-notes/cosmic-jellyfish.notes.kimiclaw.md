# cosmic-jellyfish — Upgrade Notes

**Batch:** 3B — dataTextureA Plumber
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | ~188 | 194 |
| ACES | No | No |
| dataTextureA write | No | Yes |
| Chromatic aberration | No | No |
| Temporal (dataTextureC read) | No | Yes |

---

## What Changed

Added temporal feedback loop:
- Added `textureSampleLevel(dataTextureC, u_sampler, texUV, 0.0)` read (using screen-space `texUV`)
- Added `mix(prev.rgb * 0.96, col, 0.25)` temporal blend
- Added `textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(temporal, 1.0))` write

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Pulse Speed | `zoom_params.x` | 0.5 | 0 – 2 |
| 2 | Tentacle Activity | `zoom_params.y` | 0.5 | 0 – 2 |
| 3 | Hue Shift | `zoom_params.z` | 0 | 0 – 1 |
| 4 | Glow Intensity | `zoom_params.w` | 1 | 0 – 5 |

---

## Validation

```bash
naga public/shaders/cosmic-jellyfish.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** None. No `plasmaBuffer` reads.
- **Mouse:** `zoom_config.yz` controls camera rotation (scaled to `[-1, 1]`). Mouse X rotates around Y axis, Mouse Y rotates around Z axis.
- **Depth:** No `readDepthTexture` sampling. Does not write to `writeDepthTexture`.

---

## Gotchas

- `dataTextureC` is sampled with **screen-space** `texUV` (`global_id.xy / resolution`), while the raymarching uses aspect-corrected `uv` (`(global_id.xy - resolution * 0.5) / resolution.y`). The temporal feedback uses the screen-space UV.
- The temporal blend is applied to `col` but the final `writeTexture` output remains the instantaneous `col` (not the temporally blended value). Only `dataTextureA` receives the blended result.
- Camera rotation math reuses `ro` variables in-place; the second rotation overwrites `ro.z` computed by the first rotation. This is existing behavior, not changed by the upgrade.
