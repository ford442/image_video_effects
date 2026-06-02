# gamma-ray-burst v2 Upgrade Notes

## Overview
Upgraded from 74 lines to 120 lines. Replaced simple radial gradient with physically-motivated relativistic jet simulation featuring Lorenz-boosted Doppler beaming, synchrotron emission spectrum, magnetic field line spirals, extreme HDR bloom, chromatic aberration from relativistic aberration, ACES tone mapping, and film grain.

## Algorithmist Changes
- Added `synchrotron_spectrum(freq)` function computing Gaussian emission peaks shifted by frequency
- Added `lorentz` factor: `1.0 / sqrt(max(1.0 - dist * dist * 0.8, 0.001))`
- Doppler beaming: `pow(lorentz, 3.0)`
- Magnetic field spirals via `sin(angle * jetSpread + dist * 12.0 - time * 3.0 + burstPhase)`
- Jet core + jet wings split for physically-motivated shape
- Burst events use exponential decay: `exp(-fract(time * 1.5) * 3.0)`

## Visualist Changes
- Extreme HDR bloom with values up to 4x in synchrotron emission
- Chromatic aberration magnitude scales with burst and distance: `burst * 0.025 * (1.0 + bass * 0.5) * (1.0 + dist * 0.5)`
- Directional chromatic shift along radial vector for relativistic aberration feel
- ACES tone mapping on HDR accumulation
- Film grain via `hash12(uv * 512.0 + t * 73.0)`

## Interactivist Changes
- Bass triggers burst events with exponential decay: `step(0.65, bass) * burstDecay`
- Mouse positions the jet axis (origin of radial burst)
- Depth controls atmospheric scattering extinction: `depth * 0.35 * (1.0 - burst * 0.3)`

## Alpha Strategy
- `alpha = clamp((1.0 - extinction) * (0.12 + jetIntensity * 0.5 + burstTrigger * 0.2), 0.06, 0.92)`
- Jet intensity × (1.0 - atmospheric extinction) — physically motivated transparency
- Never uses `vec4(..., 1.0)`

## Parameter Changes
- Renamed `rayDensity` to `jetSpread` to match relativistic jet physics terminology

## Validation
- naga: PASS
- workgroup_size: (16, 16, 1)
