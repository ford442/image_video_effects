# pixel-scattering v2 Upgrade Notes

## Agent Perspectives

### Algorithmist
- Replaced simple hash scatter with curl-noise velocity field advection
- Added `curl()` function computing rotational velocity from scalar noise field
- Added Fibonacci spiral scatter via `fibonacciDir()` for organic radial patterns
- Velocity = mouse interaction + curl noise + Fibonacci spiral

### Visualist
- Motion blur trails: 4-sample accumulation along velocity vector with falloff
- Chromatic separation along velocity vectors: R/B channels offset by `length(velocity)`
- HDR accumulation: final color boosted by `treble * 0.3`
- Glow added in velocity direction with color variation

### Interactivist
- Bass triggers explosive scatter events via `step(0.6, bass) * 2.0` burst multiplier
- Mouse down amplifies wind force (2.5x)
- Depth controls scatter intensity: foreground pixels scatter more
- `zoom_params.w` (chaos) controls curl-noise magnitude

### Optimizer
- Branchless `select()` for zero-distance normalization
- Fixed 4-sample trail loop (unroll-friendly)
- Single-pass compute with canonical 13 bindings
- `@workgroup_size(16, 16, 1)`

## Alpha Semantics
`alpha = clamp(velMag * depthFactor * 0.5 + 0.4, 0.0, 1.0)`
- Scatter velocity magnitude × depth determines opacity
- Minimum 0.4 alpha ensures scattered pixels remain visible

## Files Modified
- `public/shaders/pixel-scattering.wgsl` (~136 lines)
- `shader_definitions/image/pixel-scattering.json` (category updated to distortion)

## Line Count
~136 WGSL lines (target: 130-150)
