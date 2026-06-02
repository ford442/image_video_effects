# Luma Magnetism v2 Upgrade Notes

## Upgrade Summary
Upgraded from ~89 lines to 140 lines. Replaced curl-noise distortion with magnetic field line simulation using RK2 integration. Bright pixels become north poles, dark become south. Renders glowing iron-filing filaments with HDR bloom, depth-layered field fading, and ACES tone mapping. Alpha represents field line density × depth.

## Agent Perspectives

- **Algorithmist**: `magneticField()` computes gradient-based polarity from local luma differences and adds a rotating mouse field `vec2(-dy, dx) / dist²`. `rk2Step()` integrates field lines with second-order Runge-Kutta. `fieldLineDensity()` traces 8 steps per pixel for filament visualization.

- **Visualist**: Iron-filing aesthetic uses `smoothstep(0.5, 0.0, abs(sin(lineDensity * PI)))` to create filament patterns. North/south poles get distinct red/blue polarity colors. HDR bloom scales with field magnitude and bass. Depth fade `mix(0.6, 1.0, depth)` creates 3D layering. ACES tone mapping on final emission.

- **Interactivist**: Bass modulates field strength `* (1.0 + bass * 0.5)`. Mouse acts as external magnet with inverse-square falloff. Displacement samples the texture along field direction. Noise grain adds tactile texture to filaments.

- **Optimizer**: Field line tracing uses early `break` at distance 0.3 to limit work. Filament mask culls color calculations for zero-density regions. All luma samples reuse `sampleLuma()` helper. Workgroup size remains standard `(16, 16, 1)`.

## Files Modified
- `public/shaders/luma-magnetism.wgsl`
- `shader_definitions/interactive-mouse/luma-magnetism.json`

## Line Count
- Before: 89
- After: 140
