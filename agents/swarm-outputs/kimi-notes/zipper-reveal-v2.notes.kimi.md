# zipper-reveal v2 — Upgrade Notes

## Overview
Upgraded from ~89 lines to **136 lines**. Replaced simple wipe with mechanical interlocking zipper teeth, fabric physics, and chromatic aberration.

## Algorithmist Changes
- Interlocking tooth profile using `sin(local.y * 60.0 + time * 4.0 * zipSpeed)`
- Tooth offset subtracted from seam distance for realistic meshing
- Fabric parallax driven by depth (`parallax = (depth - 0.5) * 0.04`)
- Edge confidence computed from distance to zipper gap boundary

## Visualist Changes
- Metallic specular highlights on teeth (Blinn-Phong-style `pow(dot, 16.0)`)
- Fabric weave texture via dual sine interference
- Chromatic aberration on fast-moving teeth (R/G/B channel offsets)
- ACES tone mapping on final composite
- Under-fabric pattern with animated sine waves

## Interactivist Changes
- Bass drives zipper speed (`zipSpeed = 1.0 + bass * 2.0`)
- Mouse controls pull position and rotation angle
- Depth adds parallax between fabric layers

## Alpha Strategy
`alpha = clamp(toothMask * 0.9 + edgeConf * 0.4 * openMask + depth * 0.3, 0.1, 1.0)`
- Semantic: tooth visibility × fabric edge confidence × depth
- Never hardcoded to 1.0

## Validation
- naga: ✅ PASSED
- workgroup_size: (16, 16, 1)
- Bindings: 13 exact canonical
