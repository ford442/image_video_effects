# slime-mold-on-video — Kimi Batch E Notes

## Changes Made
- Added chromatic tendrils: bass shifts green, mids cyan, treble magenta
- Added depth-glow: depth scales glow intensity
- Added audio-reactive mouse boost: bass amplifies food deposit
- Added audio-reactive jitter scaling via `bass_env()`
- Dynamic alpha from trail density + bass

## Wow Factor
- Tendrils now glow in different colors based on frequency content
- Depth makes near-surface slime glow brighter

## Risks
- Color shifts on tendrils may make them hard to distinguish from background
- `bass_env()` multiplier on jitter may destabilize simulation at high bass
