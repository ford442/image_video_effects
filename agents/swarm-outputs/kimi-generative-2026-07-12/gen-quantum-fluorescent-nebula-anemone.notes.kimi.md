# gen-quantum-fluorescent-nebula-anemone — Visualist Notes

- **Original lines:** 171
- **Upgraded lines:** 260
- **Delta:** +89

## Key Visual/Lighting Changes

- Added HDR pipeline with values up to 6.0 before tone mapping.
- Integrated ACES filmic tone mapping and hue-preserving clamp.
- Added IGN dither to kill 8-bit banding in smooth nebula gradients.
- Introduced three light sources: warm key, cool fill, and magenta rim.
- Added iridescent tentacle coloring via HSV hue shifting per tentacle.
- Added volumetric fog layer over the 2D nebula field.
- Added radial god-ray bursts emanating from the anemone center.
- Fresnel-style rim falloff on tentacle edges.
- Alpha now driven by `tentacleEmission + nebulaDensity + fog`, not forced 1.0.
- Chromatic aberration removed in favor of cleaner HDR glow.
