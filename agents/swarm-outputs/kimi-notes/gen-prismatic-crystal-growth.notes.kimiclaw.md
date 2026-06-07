# gen-prismatic-crystal-growth — Upgrade Notes

**Batch:** 3A — Chromatic Only
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | 367 | 370 |
| ACES | Yes | Yes |
| dataTextureA write | Yes | Yes |
| Chromatic aberration | No | Yes |
| Temporal (dataTextureC read) | Yes | Yes |

---

## What Changed

Added chromatic aberration block after ACES tone mapping, before final write:
```wgsl
// Chromatic aberration
let caStr = 0.003 * (1.0 + smoothBass) + depthVal * 0.001;
color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);
```

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| P1 | Growth Rate | `u.zoom_params.x` | 0.5 | 0-1 |
| P2 | Crystal Density | `u.zoom_params.y` | 0.5 | 0-1 |
| P3 | Prism Intensity | `u.zoom_params.z` | 0.5 | 0-1 |
| P4 | Caustic Strength | `u.zoom_params.w` | 0.5 | 0-1 |

---

## Validation

```bash
naga public/shaders/gen-prismatic-crystal-growth.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** Bass drives crystal growth rate via `smoothBass` (envelope-smoothed, stored in `extraBuffer[2]`). Mids drive camera orbit rotation (`camAngle = time * 0.1 + mids * 0.3`). Treble is not directly used in the main pass.
- **Mouse:** Position controls light source direction (`lightDir`). X pans the light horizontally, Y adjusts its vertical elevation.
- **Depth:** `depthVal` is derived from raymarch distance (`clamp(t / 30.0, 0.0, 1.0)`), not from `readDepthTexture`. It is used only for the chromatic aberration offset (`depthVal * 0.001`).

---

## Gotchas

- `depthVal` is computed from the raymarch traversal distance (`t / 30.0`) rather than sampled from `readDepthTexture`. This is correct for a raymarched generative shader where no external depth input exists.
- `dataTextureA` stores simulation state (`thickness, storedGrowth, 0.0, alpha`), not final color. `storedGrowth` persists the maximum growth value across frames for continuous crystal expansion.
- Contains `if/else` branching in SDF crystal type selection (lines 110–114). Do not refactor without checking whether both branches are needed for the visual effect.
- Distance-based ray-step LOD is active (`stepLOD` on line 259). Changing workgroup size is safe here because no shared memory or barrier is used.
