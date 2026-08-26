# Generative fireworks / atmospheric / fractal cohort

Date: 2026-08-23

## Exact cohort

1. `gen-fireworks-ring-shell`
2. `gen-fireworks-roman-candle`
3. `gen-fireworks-smoke-bloom`
4. `gen-fireworks-strobe-shell`
5. `gen-fireworks-willow-cascade`
6. `gen-fireworks-wind-ripple`
7. `gen-fluffy-raincloud` (`gen_fluffy_raincloud.wgsl` on disk)
8. `gen-fourier-epicycles`
9. `gen-fractal-bioluminescence-spore-network`
10. `gen-fractal-chrono-dendrite-forge`

## Contract

- Preserve bindings 0 through 12 and `@workgroup_size(16, 16, 1)`.
- Use ACES and meaningful display alpha.
- Read feedback from `dataTextureC` with exact `textureLoad` operations only.
- Write persistent feedback/state only to `dataTextureA`; leave B unwritten.
- Drive distinct behavior from `plasmaBuffer[0].xyz`.
- Keep persistent scalar state within `extraBuffer[133..138]`; do not use engine FFT slots.
- Preserve normalized pointer, held-pointer, and bounded click-ripple behavior.
- Expose four named JSON params aligned with x/y/z/w and existing indexed defaults.
- Pass the focused Naga/bind-group gate and repository validation.
