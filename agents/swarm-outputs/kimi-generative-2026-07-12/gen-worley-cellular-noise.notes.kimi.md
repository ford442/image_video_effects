# Interactivist Notes: gen-worley-cellular-noise

## Key Interactivity/Reactivity Changes

- **Mouse position** attracts Worley feature points.
- **Mouse click + velocity** persisted in `extraBuffer[3..6]`; click bursts add repulsive jitter and amplify subsurface scattering.
- **Spring-damper envelopes** for bass/mid/treble in `extraBuffer[0..2]`.
- **Audio drives multiple elements**: bass → feature-point motion/scale, mid → boundary scatter, treble → chromatic aberration and tint.
- **Temporal feedback** reads `dataTextureC` via `textureSampleLevel(..., 0.0)` and writes feature data to `dataTextureA`.
- Depth sampled with `textureSampleLevel(readDepthTexture, non_filtering_sampler, ..., 0.0)`.
- Click-count-derived mutation seed creates emergent tissue pattern changes.
- Alpha tied to scatter, tissue density, depth, and interaction intensity.

## Line Count Delta

- Original: ~171 lines
- Upgraded: ~236 lines
- Delta: +65 lines
