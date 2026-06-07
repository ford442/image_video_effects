# gen-ghost-flame — Upgrade Notes

**Batch:** 3A — Chromatic Only
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | 324 | 328 |
| ACES | Yes | Yes |
| dataTextureA write | Yes | Yes |
| Chromatic aberration | No | Yes |
| Temporal (dataTextureC read) | Yes | Yes |

---

## What Changed

Added chromatic aberration block after `dataTextureA` store and before ACES:
```wgsl
// Chromatic aberration + ACES
let caStr = 0.003 * (1.0 + bass) + depthVal * 0.001;
finalColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);
finalColor = acesToneMap(finalColor * 1.1);
```

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| P1 | Flame Height | `u.zoom_params.x` | 0.5 | 0-1 |
| P2 | Turbulence | `u.zoom_params.y` | 0.5 | 0-1 |
| P3 | Cooling Rate | `u.zoom_params.z` | 0.5 | 0-1 |
| P4 | Diffusion | `u.zoom_params.w` | 0.5 | 0-1 |

---

## Validation

```bash
naga public/shaders/gen-ghost-flame.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** Bass drives flame height via `smoothBass` (envelope-smoothed, stored in `extraBuffer[3]`). RMS drives turbulence via `smoothRMS` (stored in `extraBuffer[4]`). Treble is not directly used in the main pass.
- **Mouse:** Position adds a local heat source (`mouseHeat`) near the cursor. Mouse down amplifies the heat burst. Ripple interactions also inject temperature, fuel, and horizontal velocity.
- **Depth:** `depthVal` sampled from `readDepthTexture` is used only for the chromatic aberration offset (`depthVal * 0.001`).

---

## Gotchas

- **ACES ordering differs from other Batch 3A shaders:** In `gen-ghost-flame`, chromatic aberration is applied *before* ACES tone mapping (`acesToneMap(finalColor * 1.1)` on line 324). In the other three Batch 3A shaders, ACES is applied *before* chromatic aberration. This is intentional because CA operates on the already-tonemapped HDR flame color.
- `dataTextureA` stores simulation state (`temperature, fuel, velocityX, age`), not the final rendered color. The simulation state is read back from `dataTextureC` each frame for fluid advection, diffusion, and vorticity.
- The shader samples `dataTextureC` via `textureSampleLevel` with `u_sampler` for neighbor lookups during advection and diffusion (lines 207–210, 217). Do not remove `u_sampler` from this shader.
