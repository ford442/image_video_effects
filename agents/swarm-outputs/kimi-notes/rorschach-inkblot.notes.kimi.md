# rorschach-inkblot — Kimi Notes

## Changes Made
- Added audio reactivity: bass drives distortion, mids drive drift speed, treble drives grain.
- Added chromatic ink tints: R/B channel UV offsets for colored ink.
- Added temporal ink diffusion via `dataTextureC` blend for evolving blots.
- Fixed hardcoded alpha=1.0 to dynamic semantic alpha.
- Added depth-aware ink density modulation.
- Added `dataTextureA` write for downstream effects.

## Wow Factor
- Audio makes ink flow and swirl with the music.
- Chromatic offsets create colored Rorschach patterns.
- Temporal persistence lets ink blots organically evolve over time.

## Risks for Claude Polish
- `center = mouse.x + bass * 0.02 * sin(time)` may drift outside [0,1].
- Temporal ink blend (`mix(paper, prevInk, 0.03)`) is subtle.
- Invert mode chromatic tint may look muddy at low brightness.
