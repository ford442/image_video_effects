# static-reveal v2 Upgrade Notes

## Agent Perspectives

### Algorithmist
- Replaced simple hash static with 4-octave Perlin-like value noise (`perlinOctaves`)
- Added blue-noise dithering via `blueNoise()` for smoother grain distribution
- Temporal coherence: noise evolves smoothly via `time * speed` rather than random flicker
- Three static layers at different scales for rich texture

### Visualist
- Film grain aesthetic with color channel offset (R/B noise slightly diverges)
- Vignette on unrevealed regions: darker, cooler-tinted static at edges
- ACES tone mapping for cinematic color handling
- Warm tint on unrevealed vignette for vintage film look

### Interactivist
- Bass drives static intensity multiplier: `1.0 + bass * 0.6`
- Mouse X (`zoom_config.y`) controls reveal threshold bias via `smoothstep`
- Depth adds parallax: static layers shift by depth for pseudo-3D feel
- Treble increases chromatic shift amount

### Optimizer
- Reusable `noise2()` bilinear interpolation function
- Fixed 4-octave loops (unroll-friendly)
- Single-pass compute with canonical 13 bindings
- `@workgroup_size(16, 16, 1)`

## Alpha Semantics
`alpha = clamp(mask * (1.0 - staticStrength * 0.7) + 0.15, 0.0, 1.0)`
- Reveal progress reduces static opacity contribution
- Minimum 0.15 alpha preserves grain visibility in fully static regions
- Static intensity inversely scales alpha for compositing clarity

## Files Modified
- `public/shaders/static-reveal.wgsl` (~148 lines)
- `shader_definitions/artistic/static-reveal.json`

## Line Count
~148 WGSL lines (target: 130-150)
