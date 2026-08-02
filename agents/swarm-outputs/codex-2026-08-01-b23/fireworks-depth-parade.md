# Batch 23: `fireworks-depth-parade`

- Fixed normalized held-mouse conversion with a shared centered-coordinate helper.
- Added discrete ripple-position barrages ordered foreground → midground →
  background and weighted by source depth/color.
- Replaced flat zero depth with the maximum of source-layer depth and local
  launch/spark intensity, with luminance support for dim shell edges.
- Preserved `dataTextureA` display feedback, `dataTextureB` secondary packing,
  temporal trail behavior, and all existing parameter contracts.
- Added indexed `updatedParams`, `updated: true`, and the truthful
  `supportsDepth: true` capability.

