# prism-displacement — Kimi Notes

## Changes Made
- Added temporal lens rotation memory (angle drifts slowly over time).
- Added chromatic angular dispersion enhancement (R/B separated by angle).
- Added depth-weighted magnification (`zoomAmount *= (1 + depth * 0.5)`).
- Added audio-reactive refraction strength (bass drives zoom).

## Wow Factor
- Lens slowly rotates for living prismatic feel.
- RGB channels disperse at different angles for angular chromatic aberration.
- Deeper objects magnify more, creating depth-based lensing.

## Risks for Claude Polish
- Depth-weighted magnification may cause extreme zoom at depth=1.
- Temporal rotation is always active; may conflict with user rotation speed.
- Edge color uses `hash11` which may flicker per frame.
