# gen-aurora-borealis-synthesis — Kimi Notes

## Changes
- Chromatic wavelength splitting: R aurora samples higher altitude noise, B lower, for atmospheric dispersion.
- Temporal aurora persistence: `dataTextureC` blends previous frame for smoother curtain motion.
- Audio storm intensity: `bass` drives upward motion speed and volume height for storm surges.
- Depth output from accumulated alpha for volumetric layer compositing.

## Wow-Factor
- Aurora curtains with realistic chromatic dispersion — red tops, blue bottoms, like real atmospheric physics.
- Temporal smoothing makes the volumetric raymarch feel like slow-exposure photography.

## Risks
- 20-step raymarch with 3-channel noise = 60 fbm evaluations; heaviest shader in Batch G.
- `break` on `accumulated_alpha >= 1.0` helps but early-exit penalty varies by GPU architecture.
