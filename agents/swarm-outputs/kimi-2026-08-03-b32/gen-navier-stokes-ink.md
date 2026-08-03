# Changelog — gen-navier-stokes-ink (Batch 32, interactivist)

Lines: 133 → 259.

## Upgrade

- Preserved the single-pass fluid-inspired state layout and all four saved control roles.
- Added four raymarched vortex tubes, a tessellated emitter corona, orbit camera, audio/FFT response, and guarded click-ripple deformation.
- Replaced filtering-sampler dataTextureC reads with the non-filtering sampler required by the rgba32float fallback path.
- Bounded ripple-driven radii and wrote geometry-aware near-is-one depth.

## Performance

The geometry pass uses up to 26 adaptive steps, each testing four capsules plus the emitter corona; ripples are capped at 50 and normally zero.

## Validation

Focused WGSL/Naga and bind-group validation passes with no extraBuffer violations. Real-GPU visual QA remains external.

Predicted visual rating: 8.0/10.
