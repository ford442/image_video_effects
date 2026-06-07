# gen-fourier-epicycles — Upgrade Notes

**Batch:** 3C — Chromatic Sweep
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | ~138 | 141 |
| ACES | Yes | Yes |
| dataTextureA write | Yes | Yes |
| Chromatic aberration | No | Yes |
| Temporal (dataTextureC read) | Yes | Yes |

---

## What Changed

Added chromatic aberration block after generated color assembly, before temporal feedback and ACES:
```wgsl
var generatedColor = vec3<f32>(0.008, 0.008, 0.015);
generatedColor = generatedColor + accum;
generatedColor = generatedColor + chroma;

let caStr = 0.003 * (1.0 + bass);
generatedColor = vec3<f32>(generatedColor.r + caStr, generatedColor.g, generatedColor.b - caStr * 0.5);

let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
```

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Rotation Speed | `zoom_params.x` | 0.3 | 0–1 |
| 2 | Cycle Count | `zoom_params.y` | 0.4 | 0–1 |
| 3 | Rim Intensity | `zoom_params.z` | 0.5 | 0–1 |
| 4 | Trail Persistence | `zoom_params.w` | 0.65 | 0–1 |

---

## Validation

```bash
naga public/shaders/gen-fourier-epicycles.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** `bass` drives rotation speed (`speed = (0.25 + bass * 0.6) * ...`) and CA strength; `mids` slightly accelerates trail decay (`decayed = prev.rgb * trailPersist * (1.0 - mids * 0.05)`).
- **Mouse:** Mouse position reshapes epicycle coefficients via `shapeMod = 1.0 + length(mouseShape) * mouseDown`; mouse X also offsets wheel phases.
- **Depth:** Sampled from `readDepthTexture`, mixed to 0.4–1.0 range, used in alpha compositing but **not** in `caStr` (bass-only CA).

---

## Gotchas

- Temporal feedback reads `dataTextureC` for trail persistence — do NOT change workgroup size.
- CA is applied to the raw generated color BEFORE temporal blending (`newTrail = max(decayed, generatedColor * 0.85)`), so chromatic separation does not accumulate across frames.
- `wheelColor` uses `if` branches on normalized wheel index — acceptable here because the branch is uniform per wheel, not per pixel.
- `hash12` uses `p.xyx` swizzle; ensure no WGSL compiler warnings on that pattern.
