# temporal-distortion-field — Kimi Notes

## Changes Made
- Added chromatic time-lag splitting (R=past, G=present, B=future).
- Added temporal freeze memory refinement via `dataTextureC` blend.
- Added depth-aware field radius modulation (`fieldRadius *= (1 - depth * 0.3)`).
- Enhanced fbm warp with audio-driven amplitude (`bass * 0.2`).

## Wow Factor
- RGB channels show different time slices for chromatic ghosting.
- Freeze field radius shrinks around deeper objects.
- Ghost trails persist with bass-reactive memory strength.

## Risks for Claude Polish
- Time-lag UV offsets may drift out of bounds; clamping is present but verify.
- Temporal memory factor differs for freeze vs non-freeze states (0.12 vs 0.06).
- `fbmWarp` uses 4 iterations; may be expensive at high resolution.
