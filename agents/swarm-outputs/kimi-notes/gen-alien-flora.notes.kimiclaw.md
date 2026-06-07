# gen-alien-flora — Upgrade Notes

**Batch:** 3B
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | 288 | 293 |
| ACES | No | No |
| dataTextureA write | No | Yes |
| Chromatic aberration | No | No |
| Temporal (dataTextureC read) | No | Yes |

---

## What Changed

Added temporal plumbing to the alien-flora shader:
- Sample `dataTextureC` using a **screen-space UV** (`vec2<f32>(global_id.xy) / resolution`).
- Apply a 0.96-decay temporal blend: `mix(prev.rgb * 0.96, color, 0.25)`.
- Write the blended result to `dataTextureA`.
- Added `"temporal"` to the JSON `features` array.

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Vegetation Density | `zoom_params.x` | 0.5 | 0 – 1 |
| 2 | Sway Speed | `zoom_params.y` | 1 | 0 – 5 |
| 3 | Glow Intensity | `zoom_params.z` | 1.5 | 0.5 – 3 |
| 4 | Color Shift | `zoom_params.w` | 0 | 0 – 1 |

---

## Validation

```bash
naga public/shaders/gen-alien-flora.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** **None in WGSL.** Despite JSON feature flags `"audio-reactive"` and `"audio-driven"`, the shader does not read `plasmaBuffer` or use `u.config.y` for audio. It only uses `u.config.x` for time.
- **Mouse:** Yes. Camera yaw and pitch are driven by `zoom_config.yz`.
- **Depth:** No `readDepthTexture` sampling. The shader writes depth (`t / 100.0`) to `writeDepthTexture`.

---

## Gotchas

- Mismatch between JSON features and actual WGSL inputs: the shader is **not audio-reactive** in practice.
- Uses a custom organic alpha path (`calculateOrganicAlpha`) and writes variable alpha to `writeTexture`.
