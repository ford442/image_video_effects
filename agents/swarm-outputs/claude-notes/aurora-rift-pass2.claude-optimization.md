# aurora-rift-pass2 — Claude Optimization Notes
**Date**: 2026-05-31 | **Effort**: Medium | **Category**: lighting-effects (multi-pass)

## Bottlenecks Identified

1. **globalIntensity hardcoded to 1.0 (line 146)** — The uniform value `u.config.y` carries the globalIntensity parameter but was silently overridden. This meant the final blend `mix(srcCol, toneMapped, globalIntensity)` always ran at 100%, making the intensity slider a no-op. Fixed to `clamp(u.config.y, 0.1, 1.5)`.

2. **Missing audio reactivity** — plasmaBuffer bound but unread. Chromatic dispersion (the most dramatic visual parameter) was not modulated by music energy. Fixed: `bass` drives chromaSpread × (1 + bass × 0.4), `mid` adds subtle rotation speed for hue cycling on mid-range transients.

3. **Alpha always 1.0 on writeTexture** — Pass 2 always output `alpha=1.0` regardless of aurora density, breaking downstream slot chain blending. For pixels where `density` is near zero (sky/background behind aurora), alpha should be low. Fixed to `clamp(density * 0.8 + 0.2, 0.0, 1.0)` — sky gets 0.2 base alpha, dense aurora reaches 1.0.

4. **Missing IGN dither** — The ACES output has strong shadow compression; without dither the crushed shadow gradients showed horizontal banding artifacts in the aurora's deep black regions.

## Optimizations Applied

| Change | Expected Impact |
|--------|----------------|
| Fix globalIntensity = u.config.y | Intensity param now functional — was a silent no-op |
| Bass → chromaSpread × (1+bass×0.4) | Chromatic aberration pulses with music |
| Mid → rotSpeed + mid×0.3 | Hue rotation reacts to vocal/melody range |
| density-driven alpha (was 1.0) | Correct slot-chain blending in downstream effects |
| IGN 1/255 dither before write | Eliminates banding in ACES shadow zones |
| Standard Hybrid Header | AGENTS.md compliant |

## Visual/Transcendence Notes
The globalIntensity fix unlocks the entire parameter range — previously the slider did nothing. Now fading aurora in/out works as intended, enabling graceful transitions.

The density-driven alpha is semantically correct: aurora pixels that barely affect the output (density~0.0) now contribute minimal alpha, letting downstream effects show through cleanly. Dense aurora ribbons (density~1.0) assert full presence.

## Remaining Risks
- `dataTextureC` read (the Pass 1 output) assumes the system has already piped dataTextureA→dataTextureC between passes. This is a renderer assumption; if the multi-pass routing changes, verify this binding still points to Pass 1's output.
- The history feedback via `dataTextureA` write in Pass 2 creates a one-frame loop. At high `diffusionRate` (>0.8) this can accumulate motion blur that persists too long — worth monitoring at slow flowSpeeds.

## JSON Updates Suggested
```json
{
  "features": ["multi-pass-2", "post-processing", "ACES", "chromatic-dispersion", "audio-reactive"],
  "tags": ["aurora", "atmospheric", "scattering", "grading", "audio-reactive"]
}
```
