# gen-cymatic-plasma-mandalas — Kimi Notes

## Changes
- Temporal symmetry memory: `dataTextureC` previous frame blended for persistent mandala burn-in.
- Audio-driven cymatic frequency: `bass` dynamically modulates symmetry order for rhythmic shape shifts.
- Depth-aware edge glow: `readDepthTexture` scales edge intensity, making background mandalas ethereal.
- Chromatic aberration enhanced with audio-driven per-channel offset scaling.

## Wow-Factor
- Mandala that remembers its previous form — symmetry transitions feel organic rather than abrupt.
- Depth-aware edges create a parallax layer effect without true 3D geometry.

## Risks
- `fold()` function called twice per pixel (once for coordinates, once for angle); already optimized.
- Temporal blend can blur fine detail; 6% blend is conservative.
