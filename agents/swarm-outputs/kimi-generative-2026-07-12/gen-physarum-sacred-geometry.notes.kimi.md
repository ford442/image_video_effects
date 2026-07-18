# Algorithmist Notes: gen-physarum-sacred-geometry

## Key Algorithmic Changes

- **Curl-noise agent steering** replaces naive random walk for slime-mold trails.
- **Hexagonal sacred-geometry SDF mask** (`sacredMask`) overlays ritual grid structure.
- **Mandelbrot orbit-trap accents** tint agent deposits with fractal color.
- **Second-order domain-warped FBM** distorts the deposition field.
- **extraBuffer agent simulation** persists 4 floats per agent (pos, angle, alive).
- **Audio-reactive sensor angle** and decay via `plasmaBuffer` bass.
- **Depth pass-through** and **dataTextureA** trail writeback each frame.
- Branchless `select()`/`mix()` used for agent boundary and deposit blending.

## Line Count Delta

- Original: ~190 lines
- Upgraded: ~242 lines
- Delta: +52 lines
