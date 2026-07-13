# gen-apollonian-gasket — Algorithmist upgrade notes

- Original line count: 145
- Final line count: 208
- Delta: +63 lines (target +40 to +90)

## Changes

- Replaced the custom `acesToneMap` with the canonical ACES function.
- Added canonical `hash21`, `valueNoise`, `fbm`, and `domainWarp` functions.
- Added a Voronoi distortion field that warps the plane before circle inversion.
- Converted the inner circle-inversion loop from `if (distance(q, c) < r) { ... break; }` to a branchless `select()` update (`q = select(q, invQ, inside)`).
- Converted the mouse inversion block to a branchless `select()`.
- Added FBM grain modulation to the orbit-trap density.
- Added a metallic rim term driven by inversion count and orbit distance.
- Added `luma` helper and kept semantic alpha based on density/inversion count.
- Preserved Apollonian gasket theme, Descartes circle config, and existing parameter mapping.

## Precommit

- `wgsl_precommit_gate.py` passed: naga OK, bindgroup compatible, workgroup size OK.
