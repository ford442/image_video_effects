# rgb-topology v2 Upgrade Notes

## Swarm Synthesis
- **Algorithmist**: Added per-channel topographic contour extraction with independent intervals (R=1.0, G=1.618, B=2.414 golden-ratio spacing). Each RGB channel is now a 3D heightfield rotated by mouse X.
- **Visualist**: Hypsometric tinting per channel (green low, brown mid, white peaks), HDR specular on channel peaks using normalized specDir, chromatic blending at contour crossings with animated tint, ACES tone mapping.
- **Interactivist**: Bass drives contour density (adds up to 0.25 to param), mouse X rotates the 3D terrain view, depth controls elevation exaggeration (0.5 to 2.0x).
- **Optimizer**: Branchless smoothstep where possible, early-ish exit via boundary check, compact ACES approximation, no dynamic loops.

## Alpha Semantics
`finalAlpha = contour_density * channel_separation * depth + contour_mask * 0.35 + source_blend * src.a * 0.25`
Alpha carries contour density, spatial separation, and depth information.

## Line Count
129 lines

## Changes from v1
- Replaced simple luminance topo with per-channel 3D heightfields
- Added mouse-driven 3D rotation
- Added hypsometric tinting and specular highlights
- Added chromatic blending at contour crossings
- Added ACES tone mapping
- Alpha now semantically meaningful (was clamped mix)

## Validation
naga: PASS
