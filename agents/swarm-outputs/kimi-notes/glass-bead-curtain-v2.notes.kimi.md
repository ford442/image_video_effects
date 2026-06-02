# glass-bead-curtain v2 Upgrade Notes

## Overview
Upgraded from ~84 lines to ~135 lines. Added physical refraction, Fresnel equations, chromatic caustics, subsurface scattering, bead-collision physics, and ACES tone mapping.

## Algorithmist Changes
- Added `sphereRefract()` for proper spherical glass bead refraction using eta ratio (air/glass = 1/1.5).
- Added `fresnelSchlick()` for physical reflection/transmission split at bead surface.
- Added bead collision physics: `neighborLeft` / `neighborRight` hash-driven pushes + `verticalCoupling` for strand cohesion.
- Chromatic dispersion via per-channel refraction offsets (R/G/B at 1.00/0.97/0.94 eta ratios).

## Visualist Changes
- Multi-lobe specular: sharp (pow 64) + broad (pow 8) for HDR plastic-glass look.
- Chromatic caustics: `causticPattern` + `causticRing` modulated by mids.
- Subsurface scattering: per-bead randomized warm/cool SSS color.
- Environment reflection term on bead tops.
- ACES tone mapping on final color.
- Sparkle highlights driven by treble.

## Interactivist Changes
- Bass drives `windSway` amplitude and frequency.
- Mouse push uses `interactTension` param to displace bead normals.
- Depth read from `readDepthTexture` scales bead count for perspective size.
- `verticalCoupling` adds strand physics when bass hits.

## Alpha Strategy
`finalAlpha = clamp(beadMask * density * causticAlpha + beadMask * density * 0.25, 0.12, 0.92) * depth`
Semantic: denser beads + stronger caustics + closer depth = more opaque.

## Naga Status
Validated with `naga` (see main report).
