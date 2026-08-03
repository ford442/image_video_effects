# Changelog — gen-de-jong-attractor (Batch 32, optimizer)

Lines: 135 → 238.

## Upgrade

- Preserved the Peter de Jong density field and its four saved control roles.
- Added a budgeted 3D tube sampled from the same attractor orbit, symmetry folding, orbit-trap material shading, temporal feedback, and near-is-one depth.
- Kept dataTextureC read-only and dataTextureA as the shader-owned feedback output.

## Performance

The density pass uses 128 fixed map iterations and the hero tube uses up to 36 adaptive march steps with early exits. No ripple loop or storage writes were added.

## Validation

Focused WGSL/Naga and bind-group validation passes with no extraBuffer violations. Real-GPU visual QA remains external.

Predicted visual rating: 8.0/10.
