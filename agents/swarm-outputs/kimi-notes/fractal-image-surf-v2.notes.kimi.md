# fractal-image-surf v2 Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Added fractal Brownian motion (`fbm`) with 5-octave domain warping. Jacobian-determinant-preserving warp via finite-difference gradient (`dwarp`) and `safeJac` clamp. Three fractal types: Julia, Mandelbrot, Burning Ship — morphed by bass.
- **Visualist**: Self-similar detail at all scales via FBM + fractal orbit traps. HDR specular on raised regions (`pow(max(det - 0.4, 0.0), 3.0)`). ACES tone mapping. Film grain from hashed time.
- **Interactivist**: Bass morphs between fractal types (`fractalMorph = bass`, `smoothstep` weights). Mouse explores Julia constant `c`. Depth adds parallax between displacement layers (`layer1` vs `layer2`).
- **Optimizer**: Fractal iterations clamped 4-32. FBM uses unrolled hash via `hash33`. Jacobian clamp prevents division by zero. Early exit on bounds.

## Alpha Semantics
`alpha = clamp(det * warp * depth * 0.8 + baseColor.a * 0.2 + spec * 0.15, 0.08, 1.0)`
- Displacement magnitude × fractal detail × depth, never default opaque.

## Changes from v1
- Replaced single Julia set with morphable Julia/Mandelbrot/Burning Ship.
- Added FBM domain warping with Jacobian preservation.
- Added HDR specular and film grain.
- Added ACES tone mapping.
- Alpha now semantically derived from det × warp × depth.
- Workgroup size standardized to `(16, 16, 1)`.

## Validation
- naga: OK
- Lines: ~148
