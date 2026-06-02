# halftone-reveal v2 Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Replaced uniform dots with stipple patterns: dot size scales inversely with luminance (`stippleScale = mix(1.4, 0.6, lum)`). Added CMYK halftone screening with four independent rotation angles per channel (`angles` vec4).
- **Visualist**: Accurate CMYK dot-gain simulation (`dotGain = 0.88 + mids*0.08`). Moiré patterns from channel overlap (`overlap = max(0, cDot+mDot-1)*0.08`). Paper texture overlay via high-frequency hash. ACES tone mapping.
- **Interactivist**: Bass drives reveal progression (`revealProgress = revealSize + bass*0.06`). Mouse creates magnifying loupe with finer dots (`loupe` smoothstep). Depth controls dot-size perspective (`depthDotSize = effectiveDotSize * mix(1.2, 0.6, depth)`).
- **Optimizer**: `@workgroup_size(16,16,1)`. Reused `rotate2d` for all four channels. Early bounds exit.

## Alpha Semantic
`alpha = clamp(revealMask * 0.35 + dotDensity * 0.3 + depth * 0.2 + bass * 0.05, 0.1, 0.92)`
- Reveal progress × dot_density × depth. Semantic, never 1.0.

## Lines
~145 WGSL lines

## Changes
- New helpers: `acesToneMap`, `hash2`, `rotate2d`, `rgbToCmyk`, `cmykToRgb`
- Full CMYK separation with per-channel angles
- Stipple scaling by luminance
- Dot-gain and overlap moiré
- Paper texture overlay
- JSON description updated; tags expanded
