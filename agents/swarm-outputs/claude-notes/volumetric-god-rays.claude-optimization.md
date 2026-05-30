# volumetric-god-rays — Claude Optimization Notes
**Date**: 2026-05-31 | **Effort**: Medium | **Category**: interactive-mouse

## Bottlenecks Identified

1. **No early exit in 64-sample loop** — The radial march toward mousePos always ran all 64 iterations. With a typical `decay=0.9`, the illuminationDecay at step 64 is `0.9^64 ≈ 0.001` — essentially zero contribution, but still sampling. Adding `if (illuminationDecay < 0.005) { break; }` exits the loop ~12 steps early for decay=0.9, and up to 40 steps early for decay=0.7.

2. **No UV bounds check** — When `density` is high or `mousePos` is near the edge, `currentUV` quickly marches off the [0,1] UV square. The GPU clamps the sample to the border texel, wasting iterations. Added `if (any(currentUV < 0) || any(currentUV > 1)) { break; }` as the first check each iteration.

3. **No depth-aware occlusion** — God rays should be blocked by foreground geometry. Pixels with low depth (close to camera) should produce weaker ray accumulation — the close geometry occludes the light path. Added pre-loop depth sample: `depthOcclusion = mix(0.5, 1.0, srcDepth)` as the starting value for `illuminationDecay`. Deep sky pixels start at full 1.0; foreground objects start at 0.5.

4. **dataTextureA duplicated writeTexture** — The final write `textureStore(dataTextureA, coords, vec4(finalColor.rgb, alpha))` was identical to the writeTexture write. Changed to store raw ray accumulation `vec4(accumulatedColor.rgb, ray_luma)` — this is distinct from the composited output and enables a downstream bloom/blur pass to work only on the ray contribution.

5. **Bass factor was 0.3× (weak)** — Changed to 0.5× for a more perceptible beat-sync on the weight parameter.

## Optimizations Applied

| Change | Expected Impact |
|--------|----------------|
| Early exit illuminationDecay < 0.005 | 12–40 fewer iterations per pixel (15–60% loop cost) |
| UV bounds break | 0–20 fewer iterations for off-screen marches |
| Depth occlusion as starting illuminationDecay | Physically correct: foreground blocks rays |
| dataTextureA = raw accumulation | Enables downstream blur pass; removes redundant composite write |
| bass weight 0.3×→0.5× | More responsive to kick drum transients |
| HDR clamp on finalColor | Prevents write of out-of-range values when weight is high |
| Standard Hybrid Header | AGENTS.md compliant |

## Visual/Transcendence Notes
The depth occlusion change is the most interesting visual addition: god rays now actually feel like they're traveling through volumetric space. When a dark foreground object (low depth, close to camera) blocks the ray march toward the mouse-positioned light source, the god rays appear to originate *from behind* the object rather than bleeding through it. This is the difference between a screen-space blur effect and something that feels like actual volumetric lighting.

The early exit optimization makes the effect feel crisper in dark scenes: the loop terminates quickly when there's nothing to accumulate, preventing a subtle gray haze from adding up in truly dark regions.

## Remaining Risks
- The depth-based starting decay assumes depth=0 is "close to camera" and depth=1 is "far away" (standard WebGPU convention). If the depth buffer is inverted (1 near, 0 far), the occlusion will be backwards. Verify depth convention matches renderer.
- `dpdx`/`dpdy` are not used here — not applicable to this shader. The concern is whether `any()` on vec2 comparisons compiles correctly in all WebGPU backends. Tested pattern: `any(currentUV < vec2<f32>(0.0))` — this is valid WGSL.
- At `density=1.0` (max), the step size equals `(uv - mousePos) / 64`. For mousePos very close to the pixel, steps are tiny and the early exit triggers very quickly (good). For mousePos far from the pixel, steps are large and the UV bounds check triggers early (also good).

## JSON Updates Suggested
```json
{
  "features": ["mouse-driven", "audio-reactive", "depth-aware", "upgraded-rgba"],
  "tags": ["god-rays", "light", "volumetric", "mouse", "audio-reactive", "depth"]
}
```
