# pixel-stretch-interactive v2 Upgrade Notes

## Summary
Upgraded from 94 lines to ~130 lines. Added anisotropic structure-tensor-guided pixel stretching, HDR bloom, ACES tone mapping, film grain, and depth-based parallax layering.

## Algorithmist Changes
- Added structure tensor computation using finite-difference image gradients (E, F, G matrix).
- Eigenvector extraction gives edge-aligned stretch direction.
- Replaced uniform stretch with anisotropic stretch that follows image edges.

## Visualist Changes
- Chromatic RGB smear along the stretch axis with per-channel offset scaling.
- HDR bloom accumulation on highlight pixels during smear sampling.
- ACES tone mapping for cinematic color rendering.
- Film grain overlay for tactile photographic feel.
- Parallax layering: near/far samples blended by depth.

## Interactivist Changes
- Bass drives overall stretch magnitude (`stretchAmt *= 1.0 + bass * 0.8`).
- Mouse position blends with edge direction to control stretch vector.
- Depth creates parallax offset between near and far samples.

## Alpha Semantics
`alpha = stretchMag * edgeAlign * depthFactor`
- Zero stretch or flat regions = transparent.
- Strong edges at high depth = most opaque.

## Parameter Mapping
| Slot | Param | Range | Default |
|------|-------|-------|---------|
| x | Stretch Amount | 0-1 | 0.3 |
| y | Bloom Strength | 0-1 | 0.4 |
| z | Grain Strength | 0-1 | 0.2 |
| w | Chromatic Scale | 0-1 | 0.35 |

## Validation
- naga: OK
- Category: image (unchanged)
- readTexture: sampled (image shader)
