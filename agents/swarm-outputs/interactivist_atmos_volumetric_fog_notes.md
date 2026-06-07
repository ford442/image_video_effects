# Interactivist Upgrade Notes: atmos_volumetric_fog

## Changes Applied

1. **Bass Envelope (`bass_env`)**: Replaced raw bass with smoothed envelope from `prev.r` (0.8 attack / 0.15 release). Fog density pulses organically with the beat instead of flickering.

2. **Mouse Light Source**: Mouse position acts as a virtual light source for god rays. Directional dot-product scattering creates a searchlight effect, with glow intensity scaled by bass envelope.

3. **Click Shockwave Clear**: Mouse down triggers a radial Gaussian shockwave that subtracts from local fog density, punching a temporary hole in the fog around the cursor.

4. **Video Luma Emission**: Bright areas from `readTexture` (`luma > 0.6`) emit warm light that scatters through the fog, making foreground subjects glow.

5. **Mids-Driven Noise Evolution**: Fog UV offset speed scales with mids, so the fog turbulence morphs faster when mid frequencies are active.

6. **Semantic Alpha**: Alpha encodes `fog density + lightGlow * 0.3 + shockClear * 0.5`. Interactions with mouse light and shockwaves directly boost opacity for compositing feedback.

## Line Count
166 lines (target ~180, within ±20%)
