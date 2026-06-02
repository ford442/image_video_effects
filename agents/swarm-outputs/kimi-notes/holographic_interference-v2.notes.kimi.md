# holographic_interference v2 Upgrade Notes

## Summary
Upgraded from 96 lines to ~130 lines. Converted to fully generative shader (no readTexture sampling). Added multi-source laser interference with object/reference beam phase accumulation, speckle pattern, chromatic aberration on fringes, HDR bloom, and ACES tone mapping.

## Algorithmist Changes
- Replaced simple thin-film cosine with proper laser interference from 3 coherent sources.
- Object beam: spherical wavefront from virtual object point.
- Reference beam: planar wavefront at bass-driven angle.
- Phase accumulation: `objPhase - refPhase + timeDrift`.

## Visualist Changes
- Rainbow holographic colors from wavelength-dependent fringe spacing (R/G/B phase offsets).
- Speckle noise modulates amplitude for realistic coherent-light texture.
- HDR bloom on constructive interference zones (high contrast).
- ACES tone mapping.
- Chromatic aberration on holographic fringes.

## Interactivist Changes
- Bass modulates reference beam angle (`refAngle = (0.25 + bass * 0.25) * PI`).
- Mouse moves virtual object position for parallax.
- Depth scales holographic attenuation for layered parallax.

## Alpha Semantics
`alpha = contrast * speckleCoherence * depthFactor`
- Low contrast or incoherent speckle = transparent.
- Bright constructive interference with coherent speckle at foreground depth = opaque.

## Parameter Mapping
| Slot | Param | Range | Default |
|------|-------|-------|---------|
| x | Film Thickness | 0-1 | 0.4 |
| y | Wave Scale | 0-1 | 0.5 |
| z | Depth Weight | 0-1 | 0.7 |
| w | Chromatic Aberration | 0-1 | 0.3 |

## Validation
- naga: OK
- Category: generative (unchanged)
- readTexture: NOT sampled (generative shader)
