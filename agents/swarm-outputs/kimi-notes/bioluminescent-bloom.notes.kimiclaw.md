# bioluminescent-bloom — Upgrade Notes

**Batch:** 3C
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | 199 | 203 |
| ACES | Yes | Yes |
| dataTextureA write | Yes | Yes |
| Chromatic aberration | No | Yes |
| Temporal (dataTextureC read) | Yes (Gray-Scott) | Yes (Gray-Scott) |

---

## What Changed

Inserted chromatic aberration into the existing bioluminescent-bloom pipeline:
- Added CA block before the first ACES tone-mapping call.
- CA strength: `0.003 * (1.0 + bass) + depth * 0.001`.
- Shifts red channel up and blue channel down while leaving green untouched.

The shader already had ACES, `dataTextureA` writes, and `dataTextureC` reads (for reaction-diffusion); this change only adds the chromatic sweep.

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Tendril Count | `zoom_params.x` | 0.4 | 0 – 1 |
| 2 | Pulse Speed | `zoom_params.y` | 0.4 | 0 – 1 |
| 3 | Dot Density | `zoom_params.z` | 0.5 | 0 – 1 |
| 4 | Glow Radius | `zoom_params.w` | 0.5 | 0 – 1 |

---

## Validation

```bash
naga public/shaders/bioluminescent-bloom.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** Yes. `plasmaBuffer[0].x` (bass), `.y` (mids), and `.z` (treble) feed into Gray-Scott parameters, chemotaxis, flash events, bloom, and CA strength.
- **Mouse:** Yes. `zoom_config.yz` drives chemotaxis gradient; `zoom_config.w` (mouse down) drops nutrient pellets.
- **Depth:** Yes. `readDepthTexture` is sampled for attenuation and CA offset.

---

## Gotchas

- ~~Contains two identical ACES function definitions (`aces_tone_map` and `acesToneMap`).~~ **FIXED 2026-06-06:** Removed `aces_tone_map`, unified all calls to `acesToneMap`.
- `dataTextureC` is read for **Gray-Scott reaction-diffusion simulation**, not for temporal blending. `dataTextureA` stores simulation state (`un`, `vn`, `glow`, `density`), not final rendered color.
