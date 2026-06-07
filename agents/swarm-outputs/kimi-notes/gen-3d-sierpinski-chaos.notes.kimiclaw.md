# gen-3d-sierpinski-chaos — Upgrade Notes

**Batch:** 3B — dataTextureA Plumber
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | ~186 | 191 |
| ACES | No | No |
| dataTextureA write | No | Yes |
| Chromatic aberration | No | No |
| Temporal (dataTextureC read) | No | Yes |

---

## What Changed

Added temporal feedback loop:
- Added `textureSampleLevel(dataTextureC, u_sampler, uv, 0.0)` read (using centered `uv`)
- Added `mix(prev.rgb * 0.96, color, 0.25)` temporal blend
- Added `textureStore(dataTextureA, pixel, vec4<f32>(temporal, 1.0))` write

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Point Density | `zoom_params.x` | 0.6 | 0 – 1 |
| 2 | Rotation Speed | `zoom_params.y` | 0.25 | 0 – 1 |
| 3 | Point Size | `zoom_params.z` | 0.5 | 0 – 1 |
| 4 | Color Shift | `zoom_params.w` | 0 | 0 – 1 |

---

## Validation

```bash
naga public/shaders/gen-3d-sierpinski-chaos.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** Bass boosts rotation speed (`audioSpeed = p2 * (0.9 + bass * 0.5)`). Treble boosts point density/intensity (`audioIntensity = p1 * (0.85 + treble * 0.6)`). Mids shift base hue (`audioColor = p4 + mids * 0.2`).
- **Mouse:** `zoom_config.yz` provides rotation angles when `mouseDown` (`zoom_config.w > 0.5`). When not clicked, auto-rotation is driven by `time * audioSpeed`.
- **Depth:** No `readDepthTexture` sampling. Does not write to `writeDepthTexture`.

---

## Gotchas

- `dataTextureC` is sampled with **centered signed coordinates** `uv = (pixel - resolution * 0.5) / min(resolution.x, resolution.y)`, which ranges outside `[0, 1]` depending on aspect ratio. The sampler wrap mode determines what is read back.
- The shader does not write to `writeDepthTexture`, so depth-aware downstream slots receive undefined/unchanged depth data.
- Uses a pixel-seeded deterministic chaos game: each pixel runs its own independent 20-iteration warm-up + `num_points` samples. Heavy per-pixel work.
