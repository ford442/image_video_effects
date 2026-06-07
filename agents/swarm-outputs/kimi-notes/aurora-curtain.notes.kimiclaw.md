# aurora-curtain — Upgrade Notes

**Batch:** 3C
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | 158 | 162 |
| ACES | Yes | Yes |
| dataTextureA write | Yes | Yes |
| Chromatic aberration | No | Yes |
| Temporal (dataTextureC read) | No | No |

---

## What Changed

Inserted chromatic aberration into the existing aurora pipeline:
- Added CA block before ACES tone mapping.
- CA strength: `0.003 * (1.0 + bass) + depth * 0.001`.
- Shifts red channel up and blue channel down while leaving green untouched.

The shader already had ACES and `dataTextureA` writes; this change only adds the chromatic sweep.

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Curtain Layers | `zoom_params.x` | 0.4 | 0 – 1 |
| 2 | Flow Speed | `zoom_params.y` | 0.4 | 0 – 1 |
| 3 | Curtain Width | `zoom_params.z` | 0.5 | 0 – 1 |
| 4 | Color Shift | `zoom_params.w` | 0.3 | 0 – 1 |

---

## Validation

```bash
naga public/shaders/aurora-curtain.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** Yes. `plasmaBuffer[0].x` (bass), `.y` (mids), and `.z` (treble) drive layer thickness, Kelvin-Helmholtz instability, ray bands, intensity, bloom, and CA strength.
- **Mouse:** Yes. `zoom_config.yz` sets the magnetic zenith and drags the curtain base Y position.
- **Depth:** Yes. `readDepthTexture` is sampled for CA offset and atmospheric extinction.

---

## Gotchas

- The `"temporal-flow"` feature flag in JSON refers to the visual curtain-flow effect, **not** actual `dataTextureC` temporal plumbing. There is no feedback buffer read.
- `dataTextureA` stores the **final post-ACES** color with alpha.
