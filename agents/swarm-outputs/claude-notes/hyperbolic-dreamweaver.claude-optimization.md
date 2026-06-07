# hyperbolic-dreamweaver — Claude Optimization Notes
**Date**: 2026-05-31 | **Effort**: Medium | **Category**: geometric/distortion

## Bottlenecks Identified

1. **Audio source was wrong (line 119, was zoom_config.x)** — `audioOverall` was reading `u.zoom_config.x` which the Uniforms struct comments define as "ZoomTime" — not audio data. The audio reactivity was completely nonfunctional, reacting to the zoom time parameter instead of the plasmaBuffer signal. Fixed to read `plasmaBuffer[0].x` (bass) and `[0].y` (mid).

2. **No anti-moiré at 2048²** — Hyperbolic distortion compresses and stretches UV space non-linearly. At high pixel densities, the warped UV can alias badly: pixels that map to tightly compressed hyperbolic regions sample the texture at sub-texel intervals, producing Moiré patterns. Added LOD-based mip selection using `lodFactor` (which grows from 0 at the disk center to 1 at the boundary) as a mip estimate. Note: `dpdx`/`dpdy` are not available in WebGPU compute shaders, so `lodFactor × 3.0` is used as a proxy for the compression factor.

3. **colorEnhancement could clip without hue preservation** — `sample.rgb * colorEnhancement` scales all channels equally. When any channel reaches 1.0, further enhancement clips that channel while others continue to rise, shifting the hue toward the remaining unsaturated channels. Applied `hue_preserve_clamp`: compute peak channel, scale uniformly down if peak > 1.0.

4. **depth * depthMod can exceed 1.0** — At disk edges where `hyperDist` is large and `lodFactor` is still < 1.0, the depth modulation `1.0 + hyperDist * 0.1` can push depth values above 1.0, breaking downstream depth-aware effects. Added `clamp(..., 0.0, 1.0)` on the depth write.

## Optimizations Applied

| Change | Expected Impact |
|--------|----------------|
| Audio source: zoom_config.x → plasmaBuffer[0] | Audio reactivity now functional (was silently broken) |
| lodFactor-based mip on warped UV sample | Reduces Moiré at 2048² at boundary, zero extra cost |
| hue_preserve_clamp on colorEnhancement | Prevents hue shift when enhancement clips bright channels |
| clamp depth write to [0,1] | Prevents depth buffer overrun at disk boundary |
| Standard Hybrid Header completion | AGENTS.md compliant |

## Visual/Transcendence Notes
The audio fix is the biggest behavioral change: `audioReactivity` now actually reacts to music. The hyperbolic translation speed (controlling how fast the Poincaré disk "breathes") and rotation speed now pulse with bass+mid energy. A kick drum creates a momentary expansion of the disk; vocals cause subtle rotation. This transforms the effect from a static-feeling distortion into a live, responsive geometry.

The anti-moiré mip selection eliminates the periodic striping that was visible when running at 2048×2048 on high-frequency source material (fine textures, text, grid patterns). The effect now reads as smooth dreamlike flow rather than interfering wave patterns.

## Remaining Risks
- The lodFactor mip proxy (mip = lodFactor × 3.0) is a geometric approximation. It correctly suppresses aliasing near the disk boundary but over-blurs pixels at intermediate r where the actual compression is still low. A more accurate approach would compute the warp Jacobian analytically from the hyperbolic translation formula, but that requires matrix math. Flag for future deep pass.
- The `bass * 0.4 + mid * 0.15` weights are tuned for typical music. For very loud or clipped audio, `audioReactivity` could exceed 2.0, making the translation too fast. Consider clamping `audioReactivity` to [1.0, 2.0].

## JSON Updates Suggested
```json
{
  "features": ["advanced-alpha", "hyperbolic-geometry", "depth-aware", "audio-reactive", "anti-moire"],
  "tags": ["hyperbolic", "distortion", "poincare", "dreamweaver", "audio-reactive"]
}
```
