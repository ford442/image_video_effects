# Changelog — gen-chaos-game-ifs (Batch 32, algorithmist)

Lines: 134 → 218.

## Upgrade

- Preserved the rotating 2D chaos-game field and its Iterations, Glow Size, Ring Count, and Saturation controls.
- Added a compact sphere/box/torus/octahedron/capsule SDF library and a raymarched orbit sculpture with material IDs, analytic normals, lighting, and real depth.
- Corrected the ring falloff and changed rgba32float feedback to textureLoad.

## Performance

The IFS uses 3–12 iterations and the hero sculpture uses up to 44 adaptive march steps with early exit. Normal evaluation occurs only on a surface hit.

## Validation

Focused WGSL/Naga and bind-group validation passes with no extraBuffer violations. Real-GPU visual QA remains external.

Predicted visual rating: 8.0/10.
