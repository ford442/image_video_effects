# reactive-glass-grid — Kimi Batch C Notes

## What I Changed
- Added caustic sparkle injection (`hash21`-based) on treble hits.
- Chromatic dispersion now scales with depth-derived IOR (1.1–1.5).
- Added Fresnel rim lighting on tile edges for physical glass feel.

## What I'm Proud Of
The caustic sparkles on treble make the glass feel like it's under bright sunlight — combined with the Fresnel rim, it genuinely looks like physical glass tiles.

## What Might Need a Human Eye
- IOR from depth assumes depth=1.0 is foreground — verify convention match.
