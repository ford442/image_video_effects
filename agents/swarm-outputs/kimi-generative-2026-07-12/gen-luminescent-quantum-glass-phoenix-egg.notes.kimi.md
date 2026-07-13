# gen-luminescent-quantum-glass-phoenix-egg — Visualist Notes

- **Original lines:** 197
- **Upgraded lines:** 306
- **Delta:** +109

## Key Visual/Lighting Changes

- Upgraded to HDR pipeline with ACES tone mapping and hue-preserving clamp.
- Added IGN dither for artifact-free gradients.
- Added three light sources: warm key, cool fill, violet rim.
- Added iridescent glass-shell function driven by Fresnel and time.
- Expanded inner-core volumetric march from 50 to 64 steps for denser plasma.
- Added tendril-like emissive surfaces around the core SDF boundary.
- Added external volumetric fog and god-ray bursts behind the egg.
- Previous frame sampled for subtle persistence.
- Alpha derived from Fresnel + core density + fog accumulation, not forced 1.0.
