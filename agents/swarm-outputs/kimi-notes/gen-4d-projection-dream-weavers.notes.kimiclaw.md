# gen-4d-projection-dream-weavers — Upgrade Notes

**Batch:** 3B — dataTextureA Plumber
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | ~218 | 222 |
| ACES | No | No |
| dataTextureA write | No | Yes |
| Chromatic aberration | No | No |
| Temporal (dataTextureC read) | No | Yes |

---

## What Changed

Added temporal feedback loop:
- Added `textureSampleLevel(dataTextureC, u_sampler, uv, 0.0)` read (using screen-space `uv`)
- Added `mix(prev.rgb * 0.96, color, 0.25)` temporal blend
- Added `textureStore(dataTextureA, global_id.xy, vec4<f32>(temporal, 1.0))` write

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Zoom Level | `zoom_params.x` | 0.4 | 0 – 1 |
| 2 | Rotation Speed | `zoom_params.y` | 0.4 | 0 – 1 |
| 3 | Color Shift | `zoom_params.z` | 0.3 | 0 – 1 |
| 4 | Detail Level | `zoom_params.w` | 0.4 | 0 – 1 |

---

## Validation

```bash
naga public/shaders/gen-4d-projection-dream-weavers.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** Bass drives 4D XW rotation and hypercube scale, plus adds to max iteration count. Mids drive YZ rotation and hypercube `minR2`. Treble drives ZW rotation and structural overlay line intensity. All three also phase-shift the RGB cosine palette.
- **Mouse:** `zoom_config.yz` (centered to `[-0.5, 0.5]`) controls the extra W and V dimensions (`w_dim` and `v_dim`), navigating through 4D space.
- **Depth:** No `readDepthTexture` sampling. Writes `vec4<f32>(0.0)` to `writeDepthTexture`.

---

## Gotchas

- `dataTextureC` is sampled with **screen-space** `uv` (`global_id.xy / res`), while the fractal math uses aspect-corrected `uvA`. The temporal feedback uses the non-aspect-corrected coordinates.
- The Julia set constant `juliaC` uses `w_dim * 0.5` and `v_dim * 0.5`, not the raw mouse values, to keep navigation smooth.
- `textureStore(dataTextureA, global_id.xy, ...)` uses `vec2<u32>` coordinates directly (no `vec2<i32>` cast). This is valid WGSL because `global_id.xy` is `vec3<u32>` and the XY components implicitly convert for the storage texture coordinate.
