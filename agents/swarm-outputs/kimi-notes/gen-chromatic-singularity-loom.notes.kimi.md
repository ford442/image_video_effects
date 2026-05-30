# gen-chromatic-singularity-loom — Kimi Notes

## Changes
- Temporal accretion disk memory: `dataTextureC` blends previous frame for persistent disk glow.
- Chromatic gravitational lensing: R and B light bent at different angles by singularity mass.
- Audio-reactive thread chaos: `bass` increases KIFS rotation speed, `mids` add positional jitter.
- Bass-driven mass pulse: gravity well deepens on beats, pulling threads tighter.
- Depth output from ray distance for volumetric compositing.

## Wow-Factor
- Singularity that breathes — mass pulses with bass, threads whip faster on beats.
- Chromatic lensing creates a realistic Einstein-ring color separation effect.

## Risks
- Ray march with KIFS loop inside = 120 steps × up to 4 iterations; very ALU-heavy.
- Gravitational lensing offset can push `pos` to NaN if `dist_sq` is zero; `if (dist_sq > 0.0)` guard prevents this.
