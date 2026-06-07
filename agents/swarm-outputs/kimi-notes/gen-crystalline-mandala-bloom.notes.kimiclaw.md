# gen-crystalline-mandala-bloom — Upgrade Notes

**Batch:** 3C — Chromatic Sweep
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | ~149 | 152 |
| ACES | Yes | Yes |
| dataTextureA write | Yes | Yes |
| Chromatic aberration | No | Yes |
| Temporal (dataTextureC read) | No | No |

---

## What Changed

Added chromatic aberration block after depth computation, before ACES:
```wgsl
let depth = clamp(1.0 - petalSDF * 0.6 - bloom * 0.2, 0.0, 1.0);

let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
finalRGB = vec3<f32>(finalRGB.r + caStr, finalRGB.g, finalRGB.b - caStr * 0.5);
```

Note: `let finalRGB` was changed to `var finalRGB` to allow in-place mutation by the CA pass.

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Symmetry Segments | `zoom_params.x` | 0.5 | 0–1 |
| 2 | Facet Zoom | `zoom_params.y` | 0.4 | 0–1 |
| 3 | Bloom Strength | `zoom_params.z` | 0.5 | 0–1 |
| 4 | Hue Rotation | `zoom_params.w` | 0 | 0–1 |

---

## Validation

```bash
naga public/shaders/gen-crystalline-mandala-bloom.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** `bass` drives rotation scale and CA; `mids` modulate spin rate and ring intensity; `treble` adds sparkle star brightness.
- **Mouse:** Mouse coordinates offset the mandala center (`p = vec2<f32>((uv.x - mouse.x) * aspect, uv.y - mouse.y)`).
- **Depth:** Computed from `petalSDF` and `bloom` (petals near, surround far), used in `caStr` and written to `writeDepthTexture`.

---

## Gotchas

- `finalRGB` changed from `let` to `var` so the CA block can mutate it in-place.
- The shader samples `readTexture` through kaleidoscope-folded UVs — ensure input source is available when testing.
- Hue rotation matrix is a custom 3×3 mix (not a standard RGB→HSV rotate), producing a psychedelic chroma shift.
