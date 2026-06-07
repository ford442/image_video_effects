# gen-alpha-aurora — Upgrade Notes

**Batch:** 3A — Chromatic Only
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | 304 | 307 |
| ACES | Yes | Yes |
| dataTextureA write | Yes | Yes |
| Chromatic aberration | No | Yes |
| Temporal (dataTextureC read) | Yes | Yes |

---

## What Changed

Added chromatic aberration block after ACES tone mapping, before final write:
```wgsl
// Chromatic aberration
let caStr = 0.003 * (1.0 + bass) + depthVal * 0.001;
finalColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);
```

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| P1 | Band Speed | `u.zoom_params.x` | 0.5 | 0-1 |
| P2 | Color Temperature | `u.zoom_params.y` | 0.5 | 0-1 |
| P3 | Band Density | `u.zoom_params.z` | 0.5 | 0-1 |
| P4 | Atmospheric Glow | `u.zoom_params.w` | 0.5 | 0-1 |

---

## Validation

```bash
naga public/shaders/gen-alpha-aurora.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** Bass drives band motion speed and intensity via `smoothBass` (envelope-smoothed, stored in `extraBuffer[0]`). Mids influence spectral color mixing (`mids * 0.15` in palette). Treble influences hue offset and spectral color richness.
- **Mouse:** Y position controls aurora altitude shift (`altitudeShift = (mousePos.y - 0.5) * 0.4`). X position controls color temperature offset (`tempShift = mousePos.x * 0.2`).
- **Depth:** `depthVal` sampled from `readDepthTexture` is used only for the chromatic aberration offset (`depthVal * 0.001`).

---

## Gotchas

- Uses raw `bass` (not `smoothBass`) for CA strength, unlike `gen-translucent-nebula` which uses the smoothed envelope.
- Contains an `if/else` cascade in `spectralColor()` (lines 120–125) — branchless refactor candidate for future batches.
