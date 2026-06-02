# motion-revealer — Kimi Batch E Notes

## Changes Made
- Added audio-reactive pigment: bass/mids/treble shift RGB channels independently via sine-modulated chromatic offsets
- Added depth-aware stroke opacity: near-depth surfaces paint with higher opacity (0.7→1.0)
- Added temporal feedback via `dataTextureC` history buffer with decay factor
- Replaced hardcoded alpha `1.0` with dynamic alpha driven by brush intensity + bass

## Wow Factor
- Painting feels alive — audio literally tints the brush strokes in real-time
- Depth-aware painting means foreground objects pop more vividly

## Risks
- `dataTextureA` write required for temporal persistence; if renderer doesn't feed `dataTextureC` this will show only live frame
- Chromatic shift amplitude (0.05) may be subtle at low audio levels
