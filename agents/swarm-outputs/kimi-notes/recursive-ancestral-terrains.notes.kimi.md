# recursive-ancestral-terrains — Kimi Notes

## Changes
- Added temporal mutation via slow seed drift in FBM, making terrain evolve over time.
- Chromatic lineage separation: each ancestral generation tinted toward a distinct spectral band (R/G/B offsets).
- Depth-aware height mapping writes `writeDepthTexture` with terrain elevation.
- Audio-reactive mutation rate (`mids`) and competition strength (`bass`).
- Data persistence: writes `dataTextureA` for temporal state storage.

## Wow-Factor
- Three ancestral terrains visible simultaneously, each with its own color lineage.
- Mouse proximity dynamically cross-fades generations in real time.
- Terrain “breathes” with audio — mutation rate spikes on beats.

## Risks
- FBM with 3 octaves × 3 lineages is moderately expensive; consider LOD reduction on mobile.
- `dataTextureA` write may accumulate drift if not reset periodically.
