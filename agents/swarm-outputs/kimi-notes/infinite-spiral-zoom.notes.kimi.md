# infinite-spiral-zoom — Kimi Notes

## Changes Made
- Added temporal Möbius drift: previous theta blends for smoother orbit.
- Added audio-driven zoom speed (`bass * 0.2`) and Möbius strength (`mids * 0.15`).
- Added depth-scaled chromatic aberration (`chromatic *= (1 + depth * 0.5)`).
- Added temporal trail persistence via `dataTextureC` blend.
- Added semantic alpha based on luma and edge glow.

## Wow Factor
- Temporal drift prevents jarring Möbius parameter jumps.
- Depth drives chromatic separation for 3D lensing feel.
- Audio modulates zoom and topology for reactive fractal motion.

## Risks for Claude Polish
- `cdiv` division by near-zero possible in `mobius`; already guarded in `logPolarUV`.
- `prev.z` stores theta but initial value may be 0; consider seeding.
- Three separate `mobius` + `logPolarUV` calls per pixel; expensive.
