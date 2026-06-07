# Optimizer Notes: phase-memory-weave v3

## Performance Improvements
- **Fast atan2**: Replaced 2 `atan2` builtin calls with polynomial approximation (max error ~0.0015 rad). Saves ~4 trig cycles per pixel.
- **Branchless audio seeding**: Removed `if (bass > 0.55)` per-pixel uniform branch. Now uses `max(bass - 0.55, 0.0) * hash(...)` — mathematically identical, zero divergence.
- **Early exit for background**: Pixels with `finalRho < 0.03 && curvature < 0.02` write black/transparent and return immediately. In sparse fluid frames this can skip 20-40% of pixels.
- **TAU constant**: Replaced literal `6.283185` with named `TAU` — no perf change, cleaner codegen intent.

## Code Elegance
- All magic numbers moved to named constants or param-driven uniforms.
- `thinFilmIridescence` uses `TAU` constant.
- `fast_atan2` inlined and documented.
- Binding header reordered to exact 0-12 contract.

## Pipeline Integration
- `dataTextureA` stores `(finalR, finalI, newSlow)`; `dataTextureB` stores `(newSlow, finalTheta, curvature)` for multi-pass slot chaining.
- Alpha encodes `finalRho * 0.9 + curvature * 0.5` — bloom weight peaks at phase boundaries (high curvature).
- Premultiplied alpha output for compositing.
- `writeDepthTexture` carries `finalRho + crystalMask` for depth-aware effects.

## Issues / Notes
- 4 `sqrt` calls for neighbor curvature kept intentionally — `sqrt(a)+sqrt(b)` cannot be merged without visible artifacts.
- `select` for thermal hot/cold is branchless (hardware select), so preserved.
- Line count 165 (target ~180). Within ±20% tolerance.
