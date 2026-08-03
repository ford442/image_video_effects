# Changelog — gen-aperiodic-monotile (Batch 32, algorithmist)

Lines: 138 → 224.

## Upgrade

- Preserved the stylized 2D monotile-inspired pattern and all four saved control roles.
- Added a compact sphere/box/torus/octahedron/capsule SDF library and a raymarched relief sculpture with material IDs, analytic normals, lighting, and real depth.
- Corrected inverted edge falloffs and changed rgba32float feedback to textureLoad.
- Metadata now explicitly labels the pattern as an artistic motif, not a proof-accurate hat tiling.

## Performance

The relief uses up to 42 adaptive march steps with early exit; normal evaluation occurs only on a surface hit. No storage-buffer writes.

## Validation

Focused WGSL/Naga and bind-group validation passes with no extraBuffer violations. Real-GPU visual QA remains external.

Predicted visual rating: 7.9/10.
