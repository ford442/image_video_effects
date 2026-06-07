# gen-celestial-nanite-swarm-nebula — Upgrade Notes

**Batch:** 3C — Chromatic Sweep
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | ~178 | 181 |
| ACES | Yes | Yes |
| dataTextureA write | Yes | Yes |
| Chromatic aberration | No | Yes |
| Temporal (dataTextureC read) | No | No |

---

## What Changed

Added chromatic aberration block after pow tonemapping, before ACES:
```wgsl
col = pow(col, vec3<f32>(0.8));

let hitDepth = select(0.0, clamp(1.0 - firstHitT / 10.0, 0.0, 1.0), firstHitT >= 0.0);
let caStr = 0.003 * (1.0 + bass) + hitDepth * 0.001;
col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);
```

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Swarm Density | `zoom_params.x` | 0.5 | 0–1 |
| 2 | Constellation Link | `zoom_params.y` | 0.3 | 0–1 |
| 3 | Wind Speed | `zoom_params.z` | 0.2 | 0–1 |
| 4 | Geometric Order | `zoom_params.w` | 0.7 | 0–1 |

---

## Validation

```bash
naga public/shaders/gen-celestial-nanite-swarm-nebula.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** `bass` drives chromatic aberration strength and swells constellation links; `treble` modulates nanite glow multiplier (`1.0 + treble * 0.8`).
- **Mouse:** Mouse position pulls nanite swarm toward cursor via exponential attraction (`pull = exp(-dist_to_mouse * 0.5) * 2.0`).
- **Depth:** `hitDepth` is derived from raymarched `firstHitT` (distance to first density hit), clamped 0–1, written to `writeDepthTexture` and used in `caStr`.

---

## Gotchas

- `hitDepth` is computed fresh each frame from raymarch state — it is NOT sampled from `readDepthTexture`.
- Raymarch uses 60 iterations with adaptive step sizing (`t += max(0.05, 0.1 - d*0.05)`); heavy on low-end GPUs.
- `select()` idiom for `firstHitT` capture avoids if-statements inside the raymarch loop.
