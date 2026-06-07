# magnetic-edge v2 Upgrade Notes

## Changes
- Added Canny-style edge detection with hysteresis thresholding (`edgeLow`/`edgeHigh`)
- Replaced simple edge glow with magnetic dipole field warping along field lines
- Added neon edge traces with HDR bloom via ACES tone mapping
- Added chromatic aberration on field-aligned displacements
- Added ferromagnetic particle accumulation (`hash22` noise) at edges
- Bass drives field strength and neon intensity
- Mouse acts as movable magnet with `clickBoost` multiplier
- Depth controls edge parallax displacement

## Alpha Semantics
`alpha = edge_confidence * field_alignment * depth * influence_term`
- Edge confidence from Canny hysteresis
- Field alignment from dot product of gradient and dipole direction
- Depth from readDepthTexture for parallax weighting

## Params
1. Pull Strength — dipole attraction force
2. Radius — magnet influence radius
3. Edge Threshold — Canny low threshold
4. Glow — neon bloom and chromatic aberration amount

## Line Count
~148 lines
