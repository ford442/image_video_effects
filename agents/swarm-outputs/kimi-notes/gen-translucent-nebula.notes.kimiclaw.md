# gen-translucent-nebula — Upgrade Notes

**Batch:** 3A — Chromatic Only
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | 299 | 302 |
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
finalColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);
```

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| P1 | Cloud Density | `u.zoom_params.x` | 0.5 | 0-1 |
| P2 | Cloud Scale | `u.zoom_params.y` | 0.5 | 0-1 |
| P3 | Color Shift | `u.zoom_params.z` | 0.5 | 0-1 |
| P4 | Star Density | `u.zoom_params.w` | 0.5 | 0-1 |

---

## Validation

```bash
naga public/shaders/gen-translucent-nebula.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** Bass drives nebula pulse via `smoothBass` (envelope-smoothed, stored in `extraBuffer[1]`). Mids are not directly used in the main pass. Treble drives star field brightness and sparkle intensity.
- **Mouse:** Position controls nebula center drift via `centerOffset = (mousePos - 0.5) * 0.5`. Mouse clicks create gas concentrations via ripple system (`u.ripples`).
- **Depth:** `depthVal` sampled from `readDepthTexture` is used only for the chromatic aberration offset (`depthVal * 0.001`).

---

## Gotchas

- Uses `smoothBass` (not raw `bass`) for CA strength, consistent with the rest of the shader's audio-reactive pulse logic.
- Temporal state stored to `dataTextureA` is the final color + alpha (`vec4<f32>(finalColor, finalAlpha)`), not simulation state.
