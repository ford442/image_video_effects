# gen-bioluminescent-abyss — Upgrade Notes

**Batch:** 3B — dataTextureA Plumber
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | ~413 | 418 |
| ACES | No | No |
| dataTextureA write | No | Yes |
| Chromatic aberration | No | No |
| Temporal (dataTextureC read) | No | Yes |

---

## What Changed

Added temporal feedback loop:
- Added `textureSampleLevel(dataTextureC, u_sampler, texUV, 0.0)` read (using screen-space `texUV`)
- Added `mix(prev.rgb * 0.96, color, 0.25)` temporal blend
- Added `textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(temporal, 1.0))` write

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Worm Density | `zoom_params.x` | 0.5 | 0 – 1 |
| 2 | Current Strength | `zoom_params.y` | 0.5 | 0 – 2 |
| 3 | Glow Intensity | `zoom_params.z` | 0.8 | 0 – 2 |
| 4 | Water Clarity | `zoom_params.w` | 0.5 | 0 – 1 |

---

## Validation

```bash
naga public/shaders/gen-bioluminescent-abyss.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** Bass drives harsh/deep currents (`seasonHarsh`), mids drive bloom/nutrient upwelling (`seasonBloom`), treble drives volatile "feeding frenzy" pulses (`seasonVolatile`). All three season values feed into `glowIntensity` for the worm tips. Bass also adds direct boost to glow.
- **Mouse:** `zoom_config.yz` controls camera yaw/pitch. Mouse position also drives a `mouseSpot` submarine spotlight that illuminates nearby glowing organisms. Ripple positions create local feeding blooms near glowing tips.
- **Depth:** No `readDepthTexture` sampling. Writes raymarched distance `t / 100.0` to `writeDepthTexture`.

---

## Gotchas

- `dataTextureC` is sampled with **screen-space** `texUV` (`global_id.xy / resolution`), while the raymarching uses aspect-corrected `uv`. The two UVs differ, but this is intentional for the temporal feedback path.
- Temporal blend is applied to `color` before the final alpha-premultiplied write to `writeTexture`. The stored temporal value uses `alpha = 1.0`, separate from the scene alpha logic.
- This shader uses extensive branching (`if mat == 2.0`, `if mat == 3.0`, etc.) for material-specific lighting and alpha calculations.
