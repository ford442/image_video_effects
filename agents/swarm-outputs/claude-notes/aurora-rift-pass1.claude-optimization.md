# aurora-rift-pass1 — Claude Optimization Notes
**Date**: 2026-05-31 | **Effort**: High | **Category**: lighting-effects (multi-pass)

## Bottlenecks Identified

1. **curlNoise epsilon too tight (line 93, was 0.001)** — The finite-difference gradient computation used eps=0.001. At the sample frequencies involved (scale 0.5–4.0), this produces near-zero gradient differences that get divided by 2×eps=0.002, creating a 500× amplification of floating-point noise rather than a meaningful curl direction. Changed to 0.01 — the standard for visual curl — giving coherent flow fields instead of jittery micro-turbulence.

2. **Missing audio reactivity** — `plasmaBuffer[0]` was bound but never read. Aurora is a perfect bass-reactive effect: low-frequency energy should swell the density field (more presence in quiet regions) and shift hue toward warmer plasma colors. Added `bass` from `plasmaBuffer[0].x` and `treble` from `.z`.

3. **Missing IGN dither before dataTextureA write** — The volumetric data packed into dataTextureA uses float32 precision but Pass 2 will read this and apply tone mapping on top of it. Without dither, subtle gradients in low-density aurora regions show banding artifacts when Pass 2 clips and grades. Added 1/255 IGN dither at line ~220.

## Optimizations Applied

| Change | Expected Impact |
|--------|----------------|
| `eps` 0.001→0.01 in curlNoise | Visually correct curl magnitude — aurora flow field now moves as designed |
| Bass drives density × (1+bass×0.6) | Punchier aurora during music beats, subtle during quiet |
| Treble brightens plasma emissive | Crisp edge highlights on hi-hat transients |
| Hue shift +bass×0.08 on aurora, +bass×0.15 on plasma | Warm→cool sweep synced to music |
| IGN dither before dataTextureA write | Eliminates float-precision banding in Pass 2 |
| Standard Hybrid Header + CHUNK attribution | Compliant with AGENTS.md |

## Visual/Transcendence Notes
The curl fix is the most important perceptual change: previously the curl velocity field was so small that the aurora barely moved — it looked more like static noise than flowing light. With eps=0.01, the aurora ribbons genuinely curl and drift with the depth parallax layers, producing the characteristic sweeping motion of real aurora borealis.

The bass reactivity makes this feel live: in a music visualizer context the aurora swells and glows on kick drums, then cools and contracts in the spaces between beats.

## Remaining Risks
- Watch at 4K: the 4D noise `noise4d()` uses 16 corners — still O(1) but register pressure at 2048² may be noticeable. Consider reducing to 3D noise as a fallback if frame time budgets are exceeded.
- The three parallax layer curl calls (a0, a1, a2) still use independent curlNoise evaluations with the same base spatial coordinate but different time offsets. A further optimization would share the 4 fbm evaluations at the ±eps offsets, then apply time offsets as temporal phases — this could save ~8 fbm calls but requires architectural refactoring.

## JSON Updates Suggested
```json
{
  "features": ["multi-pass-1", "volumetric", "curl-flow", "audio-reactive", "depth-aware"],
  "tags": ["aurora", "volumetric", "lighting", "atmospheric", "audio-reactive"]
}
```
