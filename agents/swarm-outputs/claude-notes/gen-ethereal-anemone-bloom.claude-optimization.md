# gen-ethereal-anemone-bloom — Claude Optimization Notes
**Date**: 2026-05-31 (batch 2) | **Effort**: High | **Category**: generative

## Bottlenecks Identified

1. **CRITICAL BUG: audio reactivity read the wrong uniform fields** — The shader's "AUDIO REACTIVITY" block read:
   ```wgsl
   let audioOverall = u.config.y;   // u.config.y is MouseClickCount, NOT audio
   let audioMid     = u.config.z;   // u.config.z is ResX (e.g. 2048)
   let audioHigh    = u.config.w;   // u.config.w is ResY (e.g. 2048)
   ```
   Per the Uniforms struct comment, `config = (Time, MouseClickCount, ResX, ResY)`. So:
   - `audioReactivity = 1.0 + audioOverall * 0.5` was driven by **mouse click count** — a value that jumps in integer steps and never returns to zero. Every click permanently sped up the animation.
   - Anywhere `audioMid`/`audioHigh` were intended (resolution values ~2048) would have produced absurd multipliers.
   
   This is the exact silent-failure pattern codified in the batch-1 session notes ("verify audio source = plasmaBuffer, not uniform fields"). Fixed all 4 read sites to use `plasmaBuffer[0].x/.y/.z`.

2. **No tone mapping (gamma only)** — Final color went straight to `pow(color, 0.4545)` with no tone-map. The bioluminescent tips (`emissive = shiftColor * glowIntensity * 2.0 * pulse_factor`) easily exceed 1.0 and clipped harshly to white.

3. **Header missing Complexity/Created/By/upgraded-rgba.**

## Optimizations Applied

| Change | Expected Impact |
|--------|----------------|
| **Fix audio: u.config.y/z/w → plasmaBuffer[0]** | Audio reactivity now actually works AND animation speed no longer corrupted by clicks/resolution |
| ACES before gamma | Bioluminescent tips glow instead of clipping to white |
| IGN dither | No banding in deep-sea fog gradient |
| Standard Hybrid Header | AGENTS.md compliant |

## Visual/Transcendence Notes
The audio fix is a genuine bug repair, not just an enhancement. Before this, the anemone's sway speed was tied to how many times the user had clicked — a completely broken behavior that would have made the effect feel erratic and unrepeatable. Now the tentacles sway with the bass, and the bioluminescent tips pulse with the low-frequency energy as intended.

The ACES addition rescues the glowing tips: previously the magenta/cyan bioluminescence saturated to flat white at the brightest points. Now the color survives all the way up, giving the tips a genuine luminous quality — they read as emitting light rather than being blown out.

## Remaining Risks
- The 100-step raymarch with `t += d` (full step, no relaxation needed since it's already 1.0) is fine. No step optimization applied here — the SDF is well-behaved.
- `audioMid` and `audioHigh` are now declared but lightly used (the sway uses bass-derived `audioReactivity`). They're available for future enhancement (e.g., treble could drive tip flicker). Left in place as documented hooks.
- The SSS thickness sampling (`map(p - n * 0.4)`) adds one extra map() call per lit tentacle pixel. Acceptable for the organic look; flag if perf-constrained.

## JSON Updates Suggested
```json
{
  "features": ["bioluminescence", "subsurface-scattering", "mouse-driven", "audio-reactive", "ACES"],
  "tags": ["anemone", "deep-sea", "organic", "bioluminescent", "audio-reactive", "generative"]
}
```
