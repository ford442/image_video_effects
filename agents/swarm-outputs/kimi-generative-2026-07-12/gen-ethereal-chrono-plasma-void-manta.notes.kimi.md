# gen-ethereal-chrono-plasma-void-manta — Visualist Notes

- **Original lines:** 174
- **Upgraded lines:** 289
- **Delta:** +115

## Key Visual/Lighting Changes

- Added HDR emission values >1.0 and ACES tone mapping.
- Added hue-preserving clamp before tone mapping.
- Added IGN Bayer-style dither for smooth volumetric gradients.
- Introduced three light sources: warm auroral key, cool deep-space fill, magenta rim.
- Added iridescence function for wing membranes driven by Fresnel angle.
- Added volumetric dark-matter fog/god-ray accumulation along the ray.
- Fresnel rim on the manta body and wings boosted with rim light color.
- Subsurface/bioluminescence (`sss`) promoted to shader-scope variable for alpha.
- Previous frame sampled and blended for temporal stability.
- Alpha driven by hit state: high on manta surface (emission + sss), low in fog.
