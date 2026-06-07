# hex-lens — Kimi Batch E Notes

## Changes Made
- Added chromatic aberration: bass shifts R channel, treble shifts B channel
- Added depth-zoom: depth scales magnification
- Added audio-reactive zoom: bass boosts lens magnification
- Added audio-reactive rotation: mids spin hex cells
- Dynamic alpha from mouse influence + bass
- `dataTextureA` write for persistence

## Wow Factor
- Hex lenses now separate colors like real glass optics
- Audio makes the entire grid pulse and rotate

## Risks
- Chromatic offset requires 2 extra `textureSampleLevel` calls per pixel
- Audio rotation may cause disorientation at high mids values
