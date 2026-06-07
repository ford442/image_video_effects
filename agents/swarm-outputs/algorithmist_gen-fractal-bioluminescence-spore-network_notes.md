# Algorithmist Upgrade Notes: gen-fractal-bioluminescence-spore-network

## Key Additions
1. **FBM Domain Warping** — Added `fbm()`, `warpedFBM()` (double-warp) and `vnoise()` for organic turbulence on the ray origin, replacing static camera motion.
2. **SDF smin Composition + Clifford Attractor** — Replaced the bare `length(p) - radius` with `smin`-unioned spore nodes driven by a Clifford strange attractor, plus a filament primitive for network connectivity.
3. **Polar Kaleidoscope Fold** — Added `kaleido()` symmetry to the UV space before warping, creating radial bioluminescence blooms.
4. **Branchless Hue Shift** — Added `hueShift()` using Rodrigues rotation for temporal color drift driven by warped FBM.
5. **Beer-Lambert Depth Absorption** — Added exponential depth fog for volumetric feel.
6. **Gold Noise Jitter** — Sub-pixel ray jitter via `goldNoise()` for anti-aliased glow.
7. **Semantic Alpha** — Alpha encodes `energy * luma + glow` instead of hardcoded 1.0.

## Line Count
~158 lines (target ~170, within ±20%).

## Issues / Warnings
- None. All WGSL built-ins verified (`textureSampleLevel` used, no `tan()`, no `textureSample`).
