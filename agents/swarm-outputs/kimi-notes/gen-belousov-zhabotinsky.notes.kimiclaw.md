# gen-belousov-zhabotinsky — Upgrade Notes

**Batch:** 3C — Chromatic Sweep
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | ~142 | 145 |
| ACES | Yes | Yes |
| dataTextureA write | Yes | Yes |
| Chromatic aberration | No | Yes |
| Temporal (dataTextureC read) | Yes | Yes |

---

## What Changed

Added chromatic aberration block after color computation, before ACES tone mapping:
```wgsl
let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
finalColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);
```

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Reaction Rate | `zoom_params.x` | 0.4 | 0–1 |
| 2 | Activator Diffusion | `zoom_params.y` | 0.3 | 0–1 |
| 3 | Inhibitor Diffusion | `zoom_params.z` | 0.25 | 0–1 |
| 4 | Feed Rate | `zoom_params.w` | 0.2 | 0–1 |

---

## Validation

```bash
naga public/shaders/gen-belousov-zhabotinsky.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** `bass` modulates reaction rate (`epsilon *= (1.0 - bass * 0.3)`) and drives chromatic aberration strength.
- **Mouse:** Mouse click seeds new spiral centers via exponential falloff (`seed = mouseDown * exp(-mouseDist² * 800.0) * 0.5`).
- **Depth:** Sampled from `readDepthTexture`, mixed to 0.3–1.0 range, used in alpha blending and `caStr`.

---

## Gotchas

- Shader reads `dataTextureC` for temporal state (activator `a`, inhibitor `b`) — do NOT change workgroup size.
- `var col` must remain mutable for the branchless color-ramp mix chain.
- `finalColor` is declared `var` so it can be mutated by the CA pass.
- This shader also appears in Batch 3D (Claude multi-pass); the chromatic insertion was verified absent before adding.
