# holographic-prism v2 Upgrade Notes

## Overview
Upgraded from ~84 lines to ~130 lines. Added triangular prism dispersion with Snell's law, wavelength-to-RGB mapping, holographic speckle, interference fringes, and ACES tone mapping.

## Algorithmist Changes
- Added `snellRefract()` with proper n1/n2 indices (air 1.0, glass 1.52).
- Added `wavelengthToRGB()` mapping 440-645nm to RGB for physical spectrum accuracy.
- Angular dispersion computed per-wavelength with red/blue shift vectors.
- Interference fringe pattern from holographic recording geometry: `sin(dist * 60 - time * 3 + facet * 12)`.

## Visualist Changes
- Accurate rainbow spectrum via `wavelengthToRGB()` instead of simple hue shift.
- Holographic speckle pattern from hash-driven grain at 256x resolution.
- HDR bloom on prism shard ring: warm gold bloom modulated by mids.
- ACES tone mapping on composited result.
- Glitch jitter tied to treble/mids for dynamic holographic instability.

## Interactivist Changes
- Bass rotates prism via `rotationSpeed * (1.0 + bass * 0.5)`.
- Mouse offsets prism center with depth-scaled parallax.
- Depth controls holographic parallax intensity: `(mouse - 0.5) * 0.12 * (1.0 + depth * 0.5)`.
- Dispersion amount driven by parameter + bass warping.

## Alpha Strategy
`finalAlpha = clamp(dispersionAlpha * holoContrast * depth, 0.08, 0.95)`
Semantic: stronger dispersion + higher contrast + closer depth = more opaque.

## Naga Status
Validated with `naga` (see main report).
