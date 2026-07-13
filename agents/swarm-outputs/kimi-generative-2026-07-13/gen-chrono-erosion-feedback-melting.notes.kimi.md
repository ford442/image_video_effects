# gen-chrono-erosion-feedback-melting — Algorithmist upgrade notes

- Original line count: 117
- Final line count: 191
- Delta: +74 lines (target +40 to +90)

## Changes

- Replaced the single `noise()` / `hash()` pair with the canonical `hash21`, `valueNoise`, `fbm`, and `domainWarp` functions.
- Upgraded `curlNoise` to use 4-octave FBM instead of a single value-noise layer.
- Added a Voronoi layer to carve erosion pits into the melt blend.
- Added domain-warped coordinates for the flow field (`wuv`).
- Replaced the per-pixel `if (bass > 0.6)` audio shock block with a branchless `max(bass - 0.55, 0.0)` shock term plus hash-driven angle.
- Replaced the per-pixel `if (audioOverall > 0.7)` inversion block with `saturate((audioOverall - 0.85) * 0.6)` and `mix()`.
- Added temporal feedback trail using `textureLoad(dataTextureC, pixel, 0)` with decay.
- Added ACES tone mapping and luma-based semantic alpha instead of hardcoded 1.0.
- Added chromatic aberration driven by flow magnitude, bass, and depth.
- Preserved datamosh/melt theme and existing UI parameter mapping.

## Precommit

- `wgsl_precommit_gate.py` passed: naga OK, bindgroup compatible, workgroup size OK.
