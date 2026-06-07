# pixelation-drift — Kimi Notes

## Changes Made
- Added audio reactivity: bass drives pixel size, mids drift speed, treble chromatic bleed.
- Added chromatic pixel separation: RGB sample at different pixel offsets.
- Fixed semantic alpha with edge-glow and audio modulation.
- Enhanced temporal persistence with audio-driven blend factor.

## Wow Factor
- Pixels swell and shrink with bass hits.
- RGB channels separate at pixel boundaries for digital chromatic aberration.
- Audio-driven drift makes pixels flow with the music.

## Risks for Claude Polish
- `persistence = 0.85 + bass * 0.05` may exceed 1.0 at high bass.
- Temporal blend accumulates toward previous frame dominance.
- Chromatic shift (`chromaShift = pixelSize/resolution * treble * 0.5`) may be too small.
