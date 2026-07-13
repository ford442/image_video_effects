# gen-mandelbox-explorer — Algorithmist upgrade notes

- Original line count: 137
- Final line count: 198
- Delta: +61 lines (target +40 to +90)

## Changes

- Replaced the custom `acesToneMap` with the canonical ACES function.
- Added canonical `hash21`, `valueNoise`, `fbm`, and `domainWarp` functions.
- Added `sdSphere` and `smin` helpers for orbit-trap blending.
- Converted `sphereFold` from an `if/else` chain to a branchless `select()` formulation.
- Added domain-warped perturbation to the Mandelbox slice thickness and `c` offset.
- Added a 3D strange-attractor-style moving sphere as an additional orbit trap blended via `smin`.
- Added per-axis orbit-trap minimums (`orbitTrap`) for metallic surface tinting.
- Added `luma` helper and semantic alpha based on density and orbit depth.
- Kept temporal feedback, chromatic aberration, and existing parameter mapping.

## Precommit

- `wgsl_precommit_gate.py` passed: naga OK, bindgroup compatible, workgroup size OK.
