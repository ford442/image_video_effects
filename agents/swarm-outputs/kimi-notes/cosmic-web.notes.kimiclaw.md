# cosmic-web — Upgrade Notes

**Batch:** 3B — dataTextureA Plumber
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | ~167 | 172 |
| ACES | No | No |
| dataTextureA write | No | Yes |
| Chromatic aberration | No | No |
| Temporal (dataTextureC read) | No | Yes |

---

## What Changed

Added temporal feedback loop:
- Added `textureSampleLevel(dataTextureC, u_sampler, uv, 0.0)` read (using aspect-corrected `uv`)
- Added `mix(prev.rgb * 0.96, color, 0.25)` temporal blend
- Added `textureStore(dataTextureA, coord, vec4<f32>(temporal, 1.0))` write

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Warp Strength | `zoom_params.x` | 0.5 | 0 – 2 |
| 2 | Filament Density | `zoom_params.y` | 1 | 0.1 – 3 |
| 3 | Flow Speed | `zoom_params.z` | 0.2 | 0 – 2 |
| 4 | Color Shift | `zoom_params.w` | 0 | 0 – 1 |

---

## Validation

```bash
naga public/shaders/cosmic-web.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** None. No `plasmaBuffer` reads.
- **Mouse:** `zoom_config.yz` acts as a gravity well. UV coordinates are warped toward the mouse position with `pullStrength = 0.3 * smoothstep(0.8, 0.0, distMouse)`.
- **Depth:** No `readDepthTexture` sampling. Writes `density` to `writeDepthTexture`.

---

## Gotchas

- `dataTextureC` is sampled with the **same aspect-corrected `uv`** used for the effect calculation, unlike some other Batch 3B shaders that use a separate screen-space UV. This means the temporal buffer aligns exactly with the warped domain.
- The galaxy point-field uses `resolution.x / resolution.y` for aspect correction but the `gPos` jitter does not account for aspect, which can stretch galaxy clusters horizontally on wide screens. Existing behavior, not affected by upgrade.
- `coord` is declared as `vec2<i32>(global_id.xy)` and reused for both `dataTextureA` and `writeTexture` stores.
