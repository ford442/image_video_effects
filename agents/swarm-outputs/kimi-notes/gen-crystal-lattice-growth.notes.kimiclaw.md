# gen-crystal-lattice-growth — Upgrade Notes

**Batch:** 3C — Chromatic Sweep
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | ~152 | 155 |
| ACES | Yes | Yes |
| dataTextureA write | Yes | Yes |
| Chromatic aberration | No | Yes |
| Temporal (dataTextureC read) | No | No |

---

## What Changed

Added chromatic aberration block after background mix, before ACES:
```wgsl
col = mix(vec3<f32>(0.02, 0.02, 0.04), col, min(totalGlow * 0.8, 1.0));

let caStr = 0.003 * (1.0 + bass);
col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

col = aces(col);
```

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Symmetry | `zoom_params.x` | 0.4 | 0–1 |
| 2 | Growth Rate | `zoom_params.y` | 0.5 | 0–1 |
| 3 | Hue | `zoom_params.z` | 0.6 | 0–1 |
| 4 | Thickness | `zoom_params.w` | 0.4 | 0–1 |

---

## Validation

```bash
naga public/shaders/gen-crystal-lattice-growth.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** `bass` modulates growth rate, thickness, and CA strength; `mids` shift hue base; `treble` adds refractive sparkle.
- **Mouse:** Mouse attracts the nucleation seed (`p -= mouse * 0.35 * u.zoom_config.w`).
- **Depth:** Computes `depth2` from pixel distance to center but does **not** use it in `caStr` (bass-only CA). Writes `depth2` to `writeDepthTexture`.

---

## Gotchas

- ~~Two ACES functions defined (`aces` and `acesToneMap`).~~ **FIXED 2026-06-06:** Removed `aces`, changed call to `acesToneMap(col)`.
- No meaningful spatial depth in the crystal model — the CA is purely audio-driven (`bass`).
- `crystalBranch` uses a fixed 5-iteration loop with early `break` on `depth`; branch divergence is localized.
