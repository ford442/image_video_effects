# gen-luminescent-aether-plasma-nebula-koi — Visualist Notes

- **Original lines:** 199
- **Upgraded lines:** 301
- **Delta:** +102

## Key Visual/Lighting Changes

- Added HDR emission values >1.0, ACES tone mapping, hue-preserving clamp.
- Added IGN dither for smooth volumetric nebula gradients.
- Introduced three light sources: warm aether key, cool nebula fill, violet rim.
- Added iridescent scale shimmer driven by Fresnel angle and time.
- Added subsurface plasma scattering (`sss`) inside the koi body.
- Expanded volumetric nebula march from 32 to 40 steps.
- Added god-ray bursts from above mixed with nebula density.
- Added explicit normal estimation via central differences for proper shading.
- Previous frame sampled for subtle temporal persistence.
- Alpha driven by hit-state emission/Fresnel + nebula density, not forced 1.0.
