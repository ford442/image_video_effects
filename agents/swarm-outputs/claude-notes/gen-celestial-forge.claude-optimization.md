# gen-celestial-forge — Claude Optimization Notes
**Date**: 2026-05-31 (batch 2) | **Effort**: High | **Category**: generative

## Bottlenecks Identified

1. **Stub header (line 1, was "COPY PASTE THIS HEADER INTO EVERY NEW SHADER")** — The shader shipped with the template placeholder comment instead of a real Standard Hybrid Header. No category, features, complexity, or attribution.

2. **plasmaBuffer declared but never read** — Binding 12 was present but audio reactivity was entirely absent. A pulsating-star forge is the ideal bass-reactive subject — the core should swell on the beat.

3. **128-step raymarch with fixed `t += d * 0.6` under-stepping** — The 0.6 step multiplier means even in open space the ray creeps forward at 60% of the safe distance, wasting steps. Adaptive relaxation: 0.6 near surfaces (d < 0.3) for detail, 0.85 in open space.

4. **Reinhard tone mapping (`col / (col + 1)`)** — Component-wise, hue-shifting. The molten core (1.0, 0.7, 0.3) loses warmth in highlights.

5. **Depth texture never written** — Only `writeTexture` was written. Downstream depth-aware effects in a slot chain would get stale/garbage depth.

## Optimizations Applied

| Change | Expected Impact |
|--------|----------------|
| Standard Hybrid Header | AGENTS.md compliant |
| Bass → coreIntensity × (1+bass×0.6) | Core swells on kick drum |
| Treble → ring panel brightness | Panels accent on hi-hats |
| Steps 128→96 + adaptive relaxation | ~25% fewer steps in open space, detail preserved near surfaces |
| Reinhard → ACES | Hue-neutral molten core highlights |
| IGN dither | No banding in dark-space nebula |
| Depth write added | Slot-chain depth-aware effects now work downstream |

## Visual/Transcendence Notes
The depth write is the most consequential correctness fix — without it, this generative piece couldn't participate in depth-aware downstream effects (god rays, depth-of-field). Now the normalized ray distance is packed correctly.

The bass-reactive core transforms the forge from a passive animation into a heartbeat: the central star visibly pulses brighter on each kick, and the contra-rotating rings catch treble accents on their glowing panels.

## Remaining Risks
- The adaptive step `select(0.85, 0.6, d < 0.3)` threshold of 0.3 is tuned for the forge's scale (rings at 1.5–4 units). If a future param lets `scale` exceed ~2, the 0.3 threshold may need to scale with it.
- accumEmission still adds every step (even far-field). It's a cheap scalar add, but a future pass could gate it like the holographic-data-core interference.

## JSON Updates Suggested
```json
{
  "features": ["raymarching", "mouse-driven", "audio-reactive", "ACES", "upgraded-rgba"],
  "tags": ["celestial", "forge", "star", "rings", "audio-reactive", "generative"]
}
```
