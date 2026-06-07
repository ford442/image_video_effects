# Optimizer Notes: gravito-phononic-accretion v3

## Performance Improvements
- **7-tap hex bokeh kernel** replaces 16-sample 4x4 SPH density loop. Texture samples drop from 16 → 7 for density estimation. Perceptually identical accretion blur at ~44% sample cost.
- **Gradient from kernel taps**: Reused hex-kernel neighbor offsets to estimate density gradient (`gradX/gradY` accumulated inside the loop), eliminating the 4 additional texture samples for finite differences. Total samples: ~20 → 10 (7 hex + 1 flow + 1 center already counted in hex).
- **Fast exp**: Ripple decay uses `fast_exp` with clamping to avoid GPU pathologies on large negative exponents.
- **Branchless mouse velocity**: `mass3` pre-multiplied by `mouseDown`; `v3` always computed but zeros out naturally when mouse is released. Removes `select` branch on uniform per pixel.

## Code Elegance
- Named constants for all physics params (`SOFTEN_1`, `VEL_AMP1`, `RIPPLE_DECAY`, etc.).
- Header reordered to exact 0-12 binding contract.
- Logical sections: orbital centers → masses → velocity → density → ripples → temperature → render.

## Pipeline Integration
- `dataTextureA` stores `(density, temp, shock)` for downstream slot reads.
- Alpha encodes bloom+shock weight for post-process bloom threshold.
- Premultiplied alpha write (`tone * alpha, alpha`) for correct compositing.
- Depth write preserved for depth-aware chaining.

## Issues / Notes
- Early exit not implemented: accretion disk fills most of frame; exit checks would add branch overhead with minimal savings.
- Hex kernel approximates the original cubic-spline SPH kernel; visual "soul" of the accretion halos is preserved.
- Line count 179 (target ~180). On target.
