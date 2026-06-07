# gen-art-deco-sky — Upgrade Notes

**Batch:** 3B
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | 401 | 409 |
| ACES | Yes | Yes |
| dataTextureA write | No | Yes |
| Chromatic aberration | No | No |
| Temporal (dataTextureC read) | No | Yes |

---

## What Changed

Added temporal plumbing to the Art Deco skyscraper shader:
- Sample `dataTextureC` using a **screen-space UV** (`vec2<f32>(global_id.xy) / resolution`).
- Apply a 0.96-decay temporal blend **before ACES**: `mix(prev.rgb * 0.96, color, 0.25)`.
- Write the pre-ACES blended result to `dataTextureA`.
- ACES tone mapping is now applied to the `temporal` variable instead of raw `color`.
- Added `"temporal"` and `"upgraded-rgba"` to the JSON `features` array.

This is the **only Batch 3B shader that already had ACES**.

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | City Density | `zoom_params.x` | 0.5 | 0 – 1 |
| 2 | Ascent Speed | `zoom_params.y` | 1 | 0 – 5 |
| 3 | Gold Glow | `zoom_params.z` | 1 | 0 – 2 |
| 4 | Fog Density | `zoom_params.w` | 0.5 | 0 – 1 |

---

## Validation

```bash
naga public/shaders/gen-art-deco-sky.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** Yes. `plasmaBuffer[0].x` (bass) boosts gold glow; `plasmaBuffer[0].y` (mid) modulates window flicker.
- **Mouse:** Yes. Orbit camera radius and angle are driven by `zoom_config.yz`.
- **Depth:** No `readDepthTexture` sampling. The shader writes depth (`t / 200.0`) to `writeDepthTexture`.

---

## Gotchas

- Temporal blend happens **before ACES**; `dataTextureA` stores pre-ACES color, while `writeTexture` receives post-ACES + dithered color.
- `textureStore(writeDepthTexture, global_id.xy, ...)` uses `vec2<u32>` coordinates, which naga accepts for storage textures.
