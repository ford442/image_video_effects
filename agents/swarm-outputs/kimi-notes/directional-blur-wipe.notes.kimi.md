# directional-blur-wipe — Kimi Batch E Notes

## Changes Made
- Added chromatic offset: R/B channels blur at different offsets per sample
- Added depth-scatter: depth scales blur radius
- Added audio-reactive strength: bass scales blur strength
- Added bass brightness pulse on blur side
- Added chromatic line highlight with mids/treble color

## Wow Factor
- Blur wipe now separates colors like a prism — edges bleed into rainbows
- Audio makes the blur breathe with the music

## Risks
- Per-channel blur adds 2 extra `textureSampleLevel` calls per pixel on blur side
- Line highlight color addition may clip to white
