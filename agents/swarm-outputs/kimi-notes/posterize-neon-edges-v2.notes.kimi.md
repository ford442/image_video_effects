# posterize-neon-edges v2 Upgrade Notes

## Agent Perspectives

### Algorithmist
- Added FBM noise function with 4 octaves for organic level boundaries
- Replaced simple floor quantization with edge-aware multi-band luminance quantization using FBM-driven band edges
- Sobel gradient magnitude now drives both edge mask and dynamic hue rotation
- Added `neonHue()` helper for consistent spectral color generation

### Visualist
- Neon edges now emit HDR values (>1.0) multiplied by glow intensity
- Added ACES tone mapping to prevent clipping while preserving punch
- Cyan/magenta split-tone: shadows tinted cyan (vec3(0.0, 0.3, 0.4)), highlights tinted magenta (vec3(1.0, 0.2, 0.6))
- Inner glow on bright areas amplified by focus factor

### Interactivist
- Bass modulates posterization levels: `levels * (1.0 + bass * 0.4)`
- Mids shift neon hue dynamically: `hue + mids * 0.3`
- Treble adds edge sparkle via high-frequency hash noise
- Mouse position creates focus center with distance-based falloff

### Optimizer
- Branchless `select()` for quantization band edge decision
- Single-pass compute with 13 canonical bindings
- `@workgroup_size(16, 16, 1)` for maximum occupancy
- Early exit on out-of-bounds threads

## Alpha Semantics
`alpha = edgeMask * (0.6 + 0.4 * depth) + baseAlpha * 0.3`
- Edge strength carries through depth factor (stronger edges in foreground)
- Base image contributes partial opacity for compositing stability

## Files Modified
- `public/shaders/posterize-neon-edges.wgsl` (~142 lines)
- `shader_definitions/image/posterize-neon-edges.json`

## Line Count
~142 WGSL lines (target: 130-150)
