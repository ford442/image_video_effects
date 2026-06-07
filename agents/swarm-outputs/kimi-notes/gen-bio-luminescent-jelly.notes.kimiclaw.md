# gen-bio-luminescent-jelly — Upgrade Notes

**Batch:** 3C — Chromatic Sweep
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | ~259 | 262 |
| ACES | Yes | Yes |
| dataTextureA write | Yes | Yes |
| Chromatic aberration | No | Yes |
| Temporal (dataTextureC read) | Yes | Yes |

---

## What Changed

Added chromatic aberration block after gamma correction, before ACES tone mapping:
```wgsl
col = pow(max(col, vec3<f32>(0.0)), vec3<f32>(0.4545));

let caStr = 0.003 * (1.0 + bass);
col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);
```

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Pulse Speed | `zoom_params.x` | 0.5 | 0–1 |
| 2 | Tentacle Length | `zoom_params.y` | 0.5 | 0–1 |
| 3 | Glow Intensity | `zoom_params.z` | 0.5 | 0–1 |
| 4 | Drift Speed | `zoom_params.w` | 0.5 | 0–1 |

---

## Validation

```bash
naga public/shaders/gen-bio-luminescent-jelly.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** `bass` drives pulse phase and bioluminescent glow intensity; `mids`/`treble` drive sparkle particles and audio smoothing envelopes; `rms` is read but unused.
- **Mouse:** Mouse position attracts the jellyfish (`attraction = (mPos - drift) * 0.15`); mouse down creates shockwave glow rings.
- **Depth:** No `readDepthTexture` sample; writes `alpha` to `writeDepthTexture` for downstream use.

---

## Gotchas

- Temporal feedback reads `dataTextureC` at `.r` for smoothed pulse phase — do NOT change workgroup size.
- `col` is mutable (`var`) before the CA block to allow the gamma pow and CA mutations.
- `env_j` helper uses `select()` for branchless attack/release — ensure `prevState` initialization is non-zero on first frame.
