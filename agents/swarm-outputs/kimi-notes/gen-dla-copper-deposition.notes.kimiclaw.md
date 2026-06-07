# gen-dla-copper-deposition — Upgrade Notes

**Batch:** 3C — Chromatic Sweep
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | ~158 | 161 |
| ACES | Yes | Yes |
| dataTextureA write | Yes | Yes |
| Chromatic aberration | No | Yes |
| Temporal (dataTextureC read) | No | No |

---

## What Changed

Added chromatic aberration block after depth computation, before ACES:
```wgsl
let depth = clamp(deposit * (1.0 - polar.x), 0.0, 1.0);

let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

// ACES tone mapping
color = color * (2.51 * color + 0.03) / (color * (2.43 * color + 0.59) + 0.14);
```

Note: `depth` was moved before the CA block so it is available for `caStr`.

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Growth Scale | `zoom_params.x` | 0.5 | 0–1 |
| 2 | Arm Count | `zoom_params.y` | 0.35 | 0–1 |
| 3 | Oxidation | `zoom_params.z` | 0.4 | 0–1 |
| 4 | Spark Intensity | `zoom_params.w` | 0.5 | 0–1 |

---

## Validation

```bash
naga public/shaders/gen-dla-copper-deposition.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** `bass` spawns denser walker clusters and drives CA; `mids` modulates domain warp and stick probability; `treble` triggers spark discharge at dendrite tips.
- **Mouse:** Mouse distance feeds into `applyGenerativePrimaryControls` via `mouseInfluence`; ripples seed crystal center (`seedPos = u.ripples[0].xy`).
- **Depth:** Computed from deposit density and polar distance, used in `caStr` and written to `writeDepthTexture`.

---

## Gotchas

- `depth` computation was explicitly moved before the CA insertion point to make it available for `caStr`.
- Uses both inline ACES (line 152) and `acesToneMap` inside `applyGenerativePrimaryControls` — dual tone-mapping path.
- `zoom_params.w` is named "Spark Intensity" in JSON but is actually mapped to `mouseInfluence` inside `applyGenerativePrimaryControls`; the real spark intensity is driven by `treble`.
