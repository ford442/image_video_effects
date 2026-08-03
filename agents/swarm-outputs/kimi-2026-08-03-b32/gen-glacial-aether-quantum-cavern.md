# Changelog — gen-glacial-aether-quantum-cavern (Batch 32, visualist)

Lines: 133 → 235.

## Upgrade

- Extended the cavern with raymarched crystalline geometry, analytic normals, three-point lighting, Fresnel response, frost facets, and temporal ice feedback.
- Restored uniform semantics: config.y is no longer treated as animation data.
- Replaced inverted frost falloff, filtering-sampler feedback reads, and far-is-one depth with bounded falloff, textureLoad feedback, and near-is-one depth.
- Preserved all four saved controls and their original metadata.

## Performance

Up to 64 adaptive march steps, a four-iteration field transform, and a six-sample normal/occlusion neighborhood. No persistent storage writes.

## Validation

Focused WGSL/Naga and bind-group validation passes with no extraBuffer violations. Real-GPU visual QA remains external.

Predicted visual rating: 8.3/10.
