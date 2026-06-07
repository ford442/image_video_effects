# bayer-dither-interactive v2 Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Replaced 4×4 Bayer with full 8×8 Bayer matrix (`bayer8`). Added blue-noise threshold modulation. Added gather-style Floyd-Steinberg error-diffusion approximation using neighbor quantization error (`errDiff = (neighbor - nQ) * 0.25 * influence`).
- **Visualist**: Retro 1-bit/4-bit/8-bit palette modes switched by bass intensity. CRT phosphor dot-pitch simulation via `dotMask` grid. ACES tone mapping. Chromatic aberration on dither edges (`caAmt` from edge intensity).
- **Interactivist**: Bass switches palette bit-depth (`modeIdx = clamp(i32(bass*3),0,2)`). Mouse scrubs dither threshold via `influence` radius. Depth controls perceived dot pitch (`depthScale = mix(1.15, 0.75, depth)`).
- **Optimizer**: `@workgroup_size(16,16,1)`. Precomputed Bayer lookup table (64 scalars). Early bounds exit.

## Alpha Semantic
`alpha = clamp(influence * 0.35 + scanline * 0.15 + ditherConf * 0.2 + bass * 0.06, 0.1, 0.92)`
- Dither confidence × (1.0 - error_diffusion_noise). Semantic, never 1.0.

## Lines
~145 WGSL lines

## Changes
- New helpers: `acesToneMap`, `hash2`, `bayer8`
- 8×8 Bayer with blue-noise jitter
- Gather-style error diffusion
- 1-bit/4-bit/8-bit retro palette mixing
- CRT phosphor dot mask + scanlines
- Chromatic aberration on quantization edges
- JSON description updated; tags expanded
