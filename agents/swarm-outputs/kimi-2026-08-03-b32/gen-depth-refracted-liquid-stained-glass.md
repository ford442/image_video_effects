# Changelog — gen-depth-refracted-liquid-stained-glass (Batch 32, visualist)

Lines: 135 → 197.

## Upgrade

- Fixed the dead Facet Count control by mapping its normalized range to 3–16 facets; Bevel Width, Temporal Drift, and Chromatic Amount retain their named roles.
- Built heightfield normals from depth, three-point lighting, Fresnel and thin-film response, stable per-cell materials, and tessellated rosette inlays.
- Removed float modulus, config.y animation misuse, filtering reads of unfilterable depth/feedback textures, and illegal plasmaBuffer indices 1–3.
- Writes source-derived relief depth instead of luminance-as-depth.

## Performance

Five depth taps, three source-color taps, and analytic ornament/material shading; no raymarch loop or storage-buffer writes.

## Validation

Focused WGSL/Naga and bind-group validation passes with no extraBuffer violations. Real-GPU visual QA remains external.

Predicted visual rating: 8.2/10.
