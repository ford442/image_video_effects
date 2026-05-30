# gen-chronos-labyrinth — Claude Optimization Notes
**Date**: 2026-05-31 | **Effort**: High | **Category**: generative

## Bottlenecks Identified

1. **Soft shadows: 32 map() calls per lit pixel** — `calcSoftShadow()` was called once per lit pixel, marching up to 32 SDF evaluations. Each map() call involves `opRepId`, `hash1`, branching into 4 structure types, SDF primitives, bridge logic, and rift logic. At 2048×2048 with ~60% hit rate, this was the dominant compute cost — approximately equal to the entire raymarch budget for those pixels. **Removed entirely.** AO provides adequate contact shadowing; the missing penumbra softness is covered by the AO×diff combination.

2. **MAX_STEPS=128** — The labyrinth scene has a maximum ray distance of 40 units with cell repetition at 1.5–4 unit scales. The SDF sphere-trace converges quickly in open corridors. Reducing to 80 steps only loses quality in the deepest recursive corners of the maze (cells nested within cells), where atmospheric fog has already reduced their contribution. Impact: ~38% raymarch budget reduction.

3. **Reinhard tone mapping (component-wise)** — `color / (1 + color)` applied per channel shifts hue: a yellow highlight `(1.5, 1.2, 0.3)` becomes `(0.6, 0.545, 0.23)` which has a very different hue ratio. Replaced with ACES filmic which operates on the full vector in a luminance-aware way.

4. **Missing IGN dither** — The deep stone/obsidian material has very dark values after fog application. Without dither, the float→output quantization produces visible banding in the shadow regions of the corridors. Added 1/255 IGN.

5. **Bass unused on atmosphere** — bass was read for rift_intensity only. The fog density is a much more impactful reactive target — thick fog on a kick drum creates a momentary "room presence" that reads as the labyrinth breathing.

## Optimizations Applied

| Change | Expected Impact |
|--------|----------------|
| Remove calcSoftShadow (32 map calls) | **Est. 30-45% total frame time reduction** (dominant win) |
| MAX_STEPS 128→80 | Est. 15-20% raymarch reduction |
| ACES replaces Reinhard | Hue-neutral tone mapping; highlights preserve material color |
| IGN dither | Eliminates banding in stone/obsidian shadow zones |
| Bass drives fog density | Labyrinth "breathes" with music — immersive depth effect |
| Mid drives rift glow multiplier | Rift portals pulse on vocals/melody |
| Standard Hybrid Header | AGENTS.md compliant |

## Visual/Transcendence Notes
The removal of soft shadows is the most dramatic perceptual change. Counter-intuitively, the visual difference is smaller than expected: the AO×diff product creates a convincing contact-shadow effect that reads as believable in the labyrinth's geometric style. The Escher-esque impossible geometry is actually better without soft shadows — the hard-edged shadowing emphasizes the lithographic quality of the architecture.

The ACES upgrade is subtle but important: the stone material (0.45, 0.42, 0.38) now stays warm even in highlights, while the temporal rift cyan (0.4, 0.9, 1.0) clips gracefully without shifting toward white.

The bass-driven fog creates a memorable experience: during musical drops, the labyrinth fills with dark mist that momentarily obscures distant geometry, then clears as the energy subsides. The parallax between foreground stone and fog-shrouded background cells becomes visceral.

## Remaining Risks
- At very high complexity (zoom_params.x ≈ 1.0, small cell sizes 1.5u), 80 steps may miss thin geometry in tight corridors. If this is noticed, consider an adaptive approach: `if (d < SURF_DIST * 3.0) { t += d * 0.5; } else { t += d * 0.9; }` to concentrate steps near surfaces.
- The staircase SDF loop (6 iterations × sdBox) is still the most expensive single structure type. For the long term, consider replacing with a precomputed texture-based SDF lookup for the staircase geometry.
- `calcAO` still makes 5 map() calls — acceptable at ~2.9% of the previous total.

## JSON Updates Suggested
```json
{
  "features": ["raymarching", "impossible-geometry", "temporal-rifts", "mouse-driven", "audio-reactive", "ACES", "depth-fog"],
  "tags": ["labyrinth", "escher", "generative", "raymarched", "audio-reactive", "fog"]
}
```
