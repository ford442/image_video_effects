# Shader Parameter Audit and Fixes

## Summary

This document tracks the audit and fixes for shaders that don't use all 4 parameter slots (zoom_params.x/y/z/w) or lack mouse reactivity.

## Statistics

- **Total Shaders**: 215 (excluding utility shaders)
- **Shaders with Issues**: 56
- **Shaders with 0/4 params**: 35
- **Shaders with 1-3/4 params**: 21  
- **Shaders without mouse reactivity**: 12

## Completed Fixes

### 1. bubble-wrap.wgsl
- **Status**: ✅ Fixed
- **Change**: Added param4 (w) for Specular Highlight control
- **Impact**: Users can now control highlight intensity (0-80%)

### 2. digital-glitch.wgsl  
- **Status**: ✅ Fixed
- **Changes**: 
  - Added param4 (w) for Color Noise control
  - Added mouse reactivity (glitch intensifies near cursor)
- **Impact**: More interactive and controllable glitch effect

## Shaders Needing Fixes

### Missing Only Param 4 (w) - 14 shaders

1. **chromatic-shockwave** - Add: Ring Count control
2. **dynamic-halftone** - Add: Edge Sharpness control
3. **galaxy-compute** - Add: Galaxy Twist/Rotation control
4. **halftone** - Add: Grid Rotation angle + Mouse reactivity
5. **interactive-emboss** - Add: Emboss Depth control
6. **kaleidoscope** - Add: Center Zoom + Mouse reactivity
7. **pixel-rain** - Add: Trail Fade control
8. **quantum-fractal** - Add: Edge Glow control + Mouse reactivity
9. **selective-color** - Add: Color Saturation Boost
10. **spectral-vortex** - Add: Color Dispersion + Mouse reactivity
11. **tile-twist** - Add: Edge Smoothness control
12. **vortex-warp** - Add: Turbulence control

### Missing Param 3 (z) - 2 shaders

1. **infinite-zoom** - Add: Perspective Strength control
2. **chromatic-manifold** - Add: Point Scatter control

### Missing All Parameters (0/4) - 35 shaders

These shaders need comprehensive parameter addition:

1. ambient-liquid
2. ascii-glyph
3. bitonic-sort
4. boids
5. datamosh
6. digital-waves
7. fractal-kaleidoscope
8. galaxy (also needs mouse)
9. julia-warp
10. lenia
11. liquid-fast
12. liquid-glitch
13. liquid-jelly
14. liquid-oil
15. liquid-perspective
16. liquid-rainbow
17. liquid-rgb
18. liquid (also needs mouse - liquid-v1)
19. liquid-viscous-simple
20. liquid-viscous
21. melting-oil
22. navier-stokes-dye
23. neon-edge-diffusion
24. neon-edges (also needs mouse)
25. physarum
26. pixel-sand
27. plasma (also needs mouse)
28. prismatic-mosaic
29. reaction-diffusion
30. spectrogram-displace
31. spectrum-bleed (also needs mouse)
32. stella-orbit (also needs mouse)
33. temporal-echo
34. voronoi
35. vortex

### Shaders Needing Mouse Reactivity

Shaders that have params but no mouse interaction:

1. crt-tv (4/4 params)
2. digital-decay (4/4 params)
3. galaxy (0/4 params)
4. halftone (3/4 params)
5. holographic-glitch (4/4 params)
6. kaleidoscope (3/4 params)
7. liquid-v1 (0/4 params)
8. neon-edges (2/4 params)
9. pixelation-drift (4/4 params)
10. plasma (0/4 params)
11. rain (4/4 params)
12. sine-wave (4/4 params)
13. snow (4/4 params)
14. spectrum-bleed (0/4 params)
15. stella-orbit (0/4 params)

## Recommendations

### Quick Wins (3/4 params)
Focus on shaders with 3/4 params first - they only need one logical parameter added. Estimated: 2-3 min per shader.

### Medium Effort (0/4 params with mouse)
Liquid effects and simulation shaders that already have mouse interaction but no params. Add controls for:
- Speed/Viscosity
- Turbulence  
- Color intensity
- Decay/Persistence

### Design Considerations

When adding parameters, consider:

1. **Visual Impact**: Parameter should have visible effect
2. **Range**: Use mix() to map 0-1 to sensible ranges
3. **Naming**: Use descriptive names in comments
4. **Mouse Integration**: Distance/direction from cursor
5. **Defaults**: Middle value (0.5) should look good

### Parameter Naming Patterns

Common good parameters to add:
- **Intensity/Strength**: Overall effect magnitude
- **Speed**: Animation/movement speed
- **Scale/Size**: Feature size
- **Color/Hue**: Color manipulation
- **Turbulence/Chaos**: Randomness
- **Smoothness/Sharpness**: Edge control
- **Glow/Bloom**: Brightness effects
- **Decay/Fade**: Temporal persistence

## Testing Checklist

For each fixed shader:
- [ ] All 4 params used with logical names
- [ ] Mouse reactivity appropriate for effect type
- [ ] Parameters have visible impact
- [ ] Default values (0.5) look good
- [ ] UI sliders work correctly
- [ ] No console errors
- [ ] JSON definition includes all 4 params

