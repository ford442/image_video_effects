# Liquid Lens v2 Upgrade Notes

## Upgrade Summary
Upgraded from ~83 lines to 143 lines. Replaced flat refraction with spherical aberration simulation using Snell's law at curved interfaces. Added 7-sample chromatic dispersion, caustic highlights via sinusoidal power functions, Fresnel reflections, surface wave deformation from bass, and ACES tone mapping. Alpha represents lens thickness × fresnel reflection.

## Agent Perspectives

- **Algorithmist**: `snellRefraction()` implements full Snell's law with total internal reflection fallback. `spectralRefract()` samples R/G/B at different refractive indices for chromatic dispersion. Lens height `h = sqrt(r² - dist²)` provides true spherical curvature. Refractive index `nBase = 1.33 + depth * 0.2 * strength` varies with depth.

- **Visualist**: Chromatic dispersion uses three separate ray directions for RGB channels. `causticHighlight()` combines two high-exponent sine waves for sharp caustic sparks. Fresnel reflection adds environment-like specular. Surface noise and wave deformation from bass create living liquid feel. ACES tone mapping prevents highlight clipping.

- **Interactivist**: Bass drives liquid surface waves via `sin(dist * 20.0 - time * 3.0)`. Mouse position defines lens center and deformation axis. Depth controls refractive index gradient for 3D refraction variation. Edge darkening softens the lens boundary.

- **Optimizer**: `spectralRefract` only runs inside lens mask but is computed per-pixel for simplicity. Caustics are cheap `pow(sin(...), exp)` operations. `clamp()` on UVs prevents out-of-bounds sampling. Workgroup size remains standard `(16, 16, 1)`.

## Files Modified
- `public/shaders/liquid-lens.wgsl`
- `shader_definitions/interactive-mouse/liquid-lens.json`

## Line Count
- Before: 83
- After: 143
