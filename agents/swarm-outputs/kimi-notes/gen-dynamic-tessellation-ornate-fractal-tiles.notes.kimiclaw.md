# gen-dynamic-tessellation-ornate-fractal-tiles — Upgrade Notes

**Batch:** 3C — Chromatic Sweep
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | ~145 | 148 |
| ACES | Yes | Yes |
| dataTextureA write | Yes | Yes |
| Chromatic aberration | No | Yes |
| Temporal (dataTextureC read) | No | No |

---

## What Changed

Added chromatic aberration block after color assembly, before tone mapping:
```wgsl
var finalColor = vec4<f32>(srgb * a, a);
let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
finalColor = vec4<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5, finalColor.a);
```

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Intensity | `zoom_params.x` | 0.5 | 0–1 |
| 2 | Speed | `zoom_params.y` | 0.5 | 0–1 |
| 3 | Scale | `zoom_params.z` | 0.5 | 0–1 |
| 4 | Mouse Influence | `zoom_params.w` | 0.5 | 0–1 |

---

## Validation

```bash
naga public/shaders/gen-dynamic-tessellation-ornate-fractal-tiles.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** `bass` increases fractal iterations (`iter = 10 + zoom_params.x * 10 + bass * 5`) and drives CA; `mids`/`treble` contribute to alpha channel.
- **Mouse:** Mouse coordinates offset the tile space (`p += u.zoom_config.yz`), panning the fractal field.
- **Depth:** Sampled from `readDepthTexture` via `non_filtering_sampler`, used in `caStr` and written to `writeDepthTexture`.

---

## Gotchas

- Workgroup size is `(8, 8, 1)` — do NOT change to `(16, 16, 1)` without verifying performance.
- Uses `applyGenerativePrimaryControls` wrapper which applies its own `acesToneMap` after the CA block; CA happens before that wrapper.
- Contains Oklab blackbody color mixing (`mixOkLab`) — mathematically heavy but stable.
- `depth` is read from the input depth texture, not computed procedurally.
