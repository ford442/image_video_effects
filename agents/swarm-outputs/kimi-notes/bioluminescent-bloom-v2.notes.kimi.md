# bioluminescent-bloom v2 Upgrade Notes

## Summary
Upgraded from 107-line pulsing tendrils to 189-line deep-ocean colony with Gray-Scott reaction-diffusion, chemotaxis, quorum sensing, and volumetric scatter. Original tendrils retained as background.

## Algorithmist Perspective
- Gray-Scott reaction-diffusion: U/V chemicals with Laplacian neighbor sampling.
- Parameters feed/kill modulated by bass/mids.
- Chemotaxis advection toward mouse nutrient source.
- Quorum sensing: glow activation threshold on V density.
- Temporal state stored in dataTextureA (U, V, glow, density).

## Visualist Perspective
- Deep ocean palette: cyan → blue → green based on glow intensity.
- Volumetric light scatter approximation radial from center.
- HDR bloom on quorum activation waves.
- ACES tone mapping.
- Background tendrils and dots provide ambient bioluminescence.

## Interactivist Perspective
- Bass drives nutrient injection (feed rate).
- Mids control colony motility (chemotaxis strength).
- Treble triggers flash events (stress response).
- Mouse drops nutrient pellets (smoothstep impulse).
- Depth controls light attenuation (fade with depth).

## Alpha Semantics
`alpha = colony_density × glow_activation × depth_attenuation + background_glow × 0.1`
Never uses opaque 1.0.

## Technical
- Lines: 189
- Naga: ✅ Valid
- No readTexture sampling.
- Uses dataTextureC for temporal RD state feedback.
- dataTextureA stores next-frame state (un, vn, glow, density).
