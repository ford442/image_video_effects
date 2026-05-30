# magnetic-chroma v2 Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Added HSV color space conversion (`rgb2hsv`/`hsv2rgb`) with hue-wheel warping via magnetic field lines. Replaced simple displacement with RK2-integrated field line advection per RGB channel (`rk2_advect`). Field computed as radial dipole + tangent component.
- **Visualist**: Chromatic dispersion along field lines (per-channel RK2 advection with depth-scaled separation). Neon glow on high-field regions (`vec3(0.15, 0.85, 1.0)`). ACES tone mapping on final composite. HDR bloom via `highField` modulation.
- **Interactivist**: Bass drives `fieldStrength` multiplier. Mouse acts as magnetic dipole center. Depth controls chromatic separation magnitude (`sepR` scaled by depth). Treble modulates RK2 timestep.
- **Optimizer**: Noise helper only used for potential expansion; kept minimal. Early exit on bounds. `textureStore` writes packed into single exit.

## Alpha Semantics
`alpha = clamp(fieldStrength * chromaticSep * depth + influence * 0.12 + highField * 0.08, 0.08, 1.0)`
- Field strength × chromatic separation × depth, never opaque 1.0 without cause.

## Changes from v1
- Replaced simple radial+tangent displacement with RK2 magnetic advection.
- Added full HSV hue warping in field regions.
- Added ACES tone mapping and neon glow.
- Alpha now semantically derived from field × chroma × depth.
- Workgroup size standardized to `(16, 16, 1)`.

## Validation
- naga: OK
- Lines: ~160
