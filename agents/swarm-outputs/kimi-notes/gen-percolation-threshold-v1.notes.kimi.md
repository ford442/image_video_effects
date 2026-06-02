# gen-percolation-threshold — New Shader Notes

## Overview
Site percolation on a 2D square lattice near the critical threshold p_c ≈ 0.5927. Iterative connected-component labeling via min-label propagation, with jewel-tone cluster coloring and HDR spanning-cluster bloom.

## Algorithm
- 80×60 lattice stored in dataTextureC/dataTextureA for temporal state
- Occupancy determined by deterministic hash with probability p
- p oscillates around critical threshold via bass + user param
- One iteration of min-label propagation per frame (union-find relaxation):
  - Occupied sites initialize to their flat index
  - Each site takes the minimum label among itself and occupied neighbors
  - Over ~10–20 frames labels converge to stable cluster roots
- Edge labels written to extraBuffer for spanning-cluster detection
- Render: each pixel maps to a lattice site, samples label, hashes to hue
- Spanning cluster glows bright magenta-white; boundary sites get chromatic aberration
- Grain, ACES tone mapping, and depth-based alpha
- Mouse click flips nearby sites to occupied (injection)

## Wow Factor
- Phase-transition dynamics: clusters suddenly span as p crosses threshold
- Jewel-tone coloring makes every cluster distinct and beautiful
- Spanning cluster detection highlights the "infinite" cluster in real time

## Risks
- Generative — no image input
- Label propagation converges slowly (~10–20 frames); rapid p changes cause flicker
- Spanning detection may lag one frame due to extraBuffer read/write timing
- extraBuffer size assumed ≥ 120 elements
