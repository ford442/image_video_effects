# Changelog — gen-lorenz-attractor (Batch 32, optimizer)

Lines: 140 → 242.

## Upgrade

- Preserved the temporal Lorenz density accumulation and every saved parameter.
- Added a sampled 3D orbit tube, symmetry fold, orbit-trap material shading, feedback-aware density, and near-is-one tube depth.
- Kept engine FFT slots read-only and retained dataTextureA/dataTextureC feedback ownership.

## Performance

The density path uses a 20-step warm-up plus 52 projected samples; the hero geometry uses up to 34 adaptive march steps with early exits.

## Validation

Focused WGSL/Naga and bind-group validation passes with no extraBuffer violations. Real-GPU visual QA remains external.

Predicted visual rating: 8.1/10.
