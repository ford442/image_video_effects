# gen-holographic-data-core — Claude Optimization Notes
**Date**: 2026-05-31 (batch 2) | **Effort**: Very High | **Category**: generative

## Bottlenecks Identified

1. **`volumetricInterference()` computed EVERY raymarch step (the dominant cost)** — Line 251 (original) called `volumetricInterference(p, -rd, time)` unconditionally inside the 80-step loop. That function invokes:
   - `volumeDiffraction()` × 3 (each: normalize + dot + exp)
   - `thinFilmInterference()` × 3 (each: 2 cos calls)
   - plus a sin for the optical path
   = roughly **9 transcendental ops per step × 80 steps = 720 transcendentals per pixel**, even for steps marching through empty space where the glow contribution (`0.01 / g_dist`) is negligible. This was the single biggest waste in the shader.

2. **plasmaBuffer declared but never read** — No audio reactivity on a hologram whose entire aesthetic (60Hz flicker, node pulses) screams for audio sync.

3. **Header missing Complexity/Created/By/upgraded-rgba.**

## Optimizations Applied

| Change | Expected Impact |
|--------|----------------|
| **Gate interference: only compute when d < 2.0 (near-field)** | **Est. 30-50% fewer interference evaluations** — far-field steps skip the 9-transcendental block entirely |
| Bass → glowBoost (1+bass×0.5) on node glow | Data nodes swell with the beat |
| Treble → projection flicker instability | Hologram glitches harder on hi-hats |
| Standard Hybrid Header | AGENTS.md compliant |

## Visual/Transcendence Notes
The interference gating is invisible to the eye: at d ≥ 2.0 the glow contribution is `0.01/2.0 = 0.005` multiplied by `(1 + interference)` where interference ∈ [0,1] — so the interference term could at most change a 0.005 contribution to 0.01. Below the perceptual floor. Skipping it costs nothing visually while saving the bulk of the transcendental math.

The treble-driven flicker is a perfect aesthetic match: holograms in film always glitch and destabilize, and now that instability is driven by the music's high frequencies — the data core stutters and flickers on every cymbal hit.

## Remaining Risks
- The d < 2.0 gate threshold is conservative. Profiling on target hardware could push it lower (e.g., d < 1.0) for more savings, since the glow falloff is `1/d`. Test visual parity at d < 1.0 before tightening.
- This shader does NOT use ACES or IGN dither — intentional. It's an additive-glow hologram with carefully capped alpha (max 0.5) and no tone-map stage. Adding ACES would crush the intended ethereal additive look. Left as-is by design.
- The material-ID branch divergence in the glow accumulation (mat_id 1/2/3) remains — acceptable given the gate now skips most far-field iterations.

## JSON Updates Suggested
```json
{
  "features": ["mouse-driven", "depth-aware", "audio-reactive", "alpha-transparency"],
  "tags": ["holographic", "data-core", "interference", "hologram", "audio-reactive", "generative"]
}
```
