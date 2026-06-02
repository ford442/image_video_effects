# contour-flow v2 Upgrade Notes

## Agent Perspectives
- **Algorithmist**: Replaced simple gradient with structure-tensor edge detection using full 3x3 Sobel kernel on luminance. Added flow advection along edge-tangent direction. Mouse vortex sources via perpendicular rotation of distance vector. Bass-driven turbulence term.
- **Visualist**: Flow-aligned streaks sampled along the advection direction with HDR glow. Velocity color mapping: slow flow = blue, fast flow = red. ACES tone mapping. Treble adds bright streak highlights.
- **Interactivist**: Bass drives turbulence (`turbulence * bass * 0.01`). Mouse creates vortex sources (`vortex = perpendicular(distVec)`). Depth controls flow viscosity (`viscosity = mix(0.3, 1.0, depth)`).
- **Optimizer**: Single-pass with 9 texture samples for Sobel. Reused grayscale values. Early boundary return. No dynamic loops.

## Alpha Strategy
`alpha = flowMag * edgeStrength + advected.a * 0.4 + mouseFactor * 0.15`
Flow magnitude multiplied by edge strength ensures transparent flat regions, opaque flowing edges.

## Lines
123 lines (was 77)

## Files Written
- `public/shaders/contour-flow.wgsl`
- `shader_definitions/image/contour-flow.json` (moved from interactive-mouse/)
