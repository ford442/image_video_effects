# gen-abyssal-leviathan-scales — Upgrade Notes

**Batch:** 3B
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | 209 | 215 |
| ACES | No | No |
| dataTextureA write | No | Yes |
| Chromatic aberration | No | No |
| Temporal (dataTextureC read) | No | Yes |

---

## What Changed

Added temporal plumbing to the raymarched leviathan-scales shader:
- Sample `dataTextureC` using a **screen-space UV** (`fragCoord / dims`) separate from the centered raymarching UV.
- Apply a 0.96-decay temporal blend: `mix(prev.rgb * 0.96, col, 0.25)`.
- Write the blended result to `dataTextureA`.
- Added `"temporal"` to the JSON `features` array.

The temporal blend happens **after** tone-mapping and gamma correction, so `dataTextureA` stores the post-processed color.

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Scale Density | `zoom_params.x` | 5 | 1 – 15 |
| 2 | Plasma Intensity | `zoom_params.y` | 1 | 0 – 5 |
| 3 | Breathing Speed | `zoom_params.z` | 1 | 0.1 – 3 |
| 4 | Core Heat | `zoom_params.w` | 2 | 0.5 – 5 |

---

## Validation

```bash
naga public/shaders/gen-abyssal-leviathan-scales.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** `u.config.y` (click/beat accumulator) scaled by `0.1` drives `audioPulse`, which modulates plasma heat, volumetric glow, and core brightness. No `plasmaBuffer` reads.
- **Mouse:** Yes. Normalized mouse from `zoom_config.yz` creates a repulsion field that lifts and tilts nearby scales.
- **Depth:** No `readDepthTexture` sampling.

---

## Gotchas

- Uses a centered raymarching UV (`(fragCoord * 2.0 - dims) / dims.y`); the agent added a separate **screen-space `dataUV`** so the `dataTextureC` sample aligns with pixel coordinates.
- Temporal blend is applied **after** `col/(col+1)` Reinhard-style tone mapping and gamma, so the feedback buffer stores post-tonemapped color.
