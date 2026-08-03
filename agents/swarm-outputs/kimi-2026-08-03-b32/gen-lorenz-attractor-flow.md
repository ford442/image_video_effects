# Changelog — gen-lorenz-attractor-flow (Batch 32, interactivist)

Lines: 137 → 245.

## Upgrade

- Preserved the Lorenz ODE field and the existing params array byte-for-byte.
- Added a swept 3D attractor tube, orbit camera, kaleidoscopic orbit trap, FFT response, guarded click ripples, temporal feedback, and real depth.
- Corrected mouseDown to zoom_config.w, reserved config.y for rippleCount, bounded accumulated ripple deformation, and replaced filtering feedback reads with textureLoad.
- Kept the existing public URL, shaders/lorenz-attractor-flow.wgsl.

## Performance

The 2D flow integrates up to 80 steps; the 3D tube samples 44 trajectory nodes; ripples are capped at 50 and are normally absent.

## Validation

Focused WGSL/Naga and bind-group validation passes with no extraBuffer violations. Real-GPU visual QA remains external.

Predicted visual rating: 8.2/10.
