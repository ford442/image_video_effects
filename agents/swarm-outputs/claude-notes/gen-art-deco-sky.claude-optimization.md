# gen-art-deco-sky — Claude Optimization Notes
**Date**: 2026-05-31 (batch 2) | **Effort**: High | **Category**: generative

## Bottlenecks Identified

1. **Incomplete header** — Had a description but no Features/Complexity/Created/By/upgraded-rgba fields. Category was capitalized "Generative" (inconsistent with the lowercase convention).

2. **plasmaBuffer declared but never read** — No audio reactivity. The lit windows and gold trim are ideal audio targets (city skyline pulsing with music).

3. **150-step raymarch, `t += d * 0.8`** — The most expensive batch member by step count. The Art Deco tower has large flat facades where the ray can safely take bigger steps in open air. Adaptive: 0.8 near surfaces (d < 1.0), 0.95 in open air.

4. **Reinhard tone mapping** — Comment even said "simple exposure/ACES fit approx" but it was actually `color / (color + 1)` Reinhard. The gold material (1.0, 0.7, 0.2) is exactly the kind of warm highlight Reinhard desaturates.

5. **No IGN dither** — The dark blue night sky (0.02, 0.05, 0.1) gradient bands visibly.

## Optimizations Applied

| Change | Expected Impact |
|--------|----------------|
| Complete Standard Hybrid Header | AGENTS.md compliant |
| Bass → goldGlow × (1+bass×0.5) | Gold trim pulses with music |
| Mid → window flicker modulation | Windows twinkle on melody/vocals |
| Steps 150→110 + adaptive relaxation | ~27% step reduction; flat facades march faster |
| Reinhard → ACES | Gold accents keep their warmth in highlights |
| IGN dither | No banding in night sky |

## Visual/Transcendence Notes
The bass-driven gold glow plays beautifully against the Art Deco aesthetic — the genre is all about gilded opulence, and now the gold literally pulses with the music's low end. The mid-range window flicker adds life to the background skyline: individual lit windows twinkle in sync with the melody, like a city responding to the soundtrack.

The ACES upgrade matters most on the gold material — under Reinhard the gold trim washed toward pale yellow in bright areas; ACES keeps it a rich, saturated gold even at peak brightness.

## Remaining Risks
- The `goldGlow × (1+bass×0.5)` could push goldGlow above its intended 0..2 range during loud bass. The downstream `emission` uses are clamped by ACES, so no blowout, but the glow may feel intense on bass-heavy tracks. Consider clamping if it reads as too much.
- 110 steps may still miss thin fluting detail at grazing angles on the central tower. Watch the column fluting (`cos(cp.x*10.0)*0.1`) at oblique camera angles.

## JSON Updates Suggested
```json
{
  "features": ["raymarching", "mouse-driven", "audio-reactive", "ACES", "upgraded-rgba"],
  "tags": ["art-deco", "skyscraper", "architecture", "gold", "audio-reactive", "generative"]
}
```
