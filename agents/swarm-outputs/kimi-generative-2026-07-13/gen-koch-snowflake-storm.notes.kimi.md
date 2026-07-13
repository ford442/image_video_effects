# gen-koch-snowflake-storm — Algorithmist upgrade notes

- Original line count: 152
- Final line count: 225
- Delta: +73 lines (target +40 to +90)

## Changes

- Replaced the custom FBM and duplicate ACES functions with canonical `hash21`, `valueNoise`, `fbm`, `domainWarp`, and `acesToneMap`.
- Added a curl-noise storm drift layer on top of domain warping.
- Added a Voronoi ice-crystal grain overlay (`voronoi`) blended into color and depth.
- Added an `sdHexagon` primitive and `smin` smooth union; each snowflake now combines Koch SDF + hexagon SDF.
- Replaced the per-snowflake `if (d < minDist)` minimum selection with branchless `select()`/`mix()` updates.
- Added subsurface-scattering warm core and per-flake ID color variation.
- Added temporal feedback using `textureSampleLevel(dataTextureC, ..., 0.0)`.
- Added semantic alpha driven by glow, inside mask, crystal grain, and treble.
- Preserved ice/storm aesthetic and existing UI parameter mapping.

## Precommit

- `wgsl_precommit_gate.py` passed: naga OK, bindgroup compatible, workgroup size OK.
