# Interactivist Notes: gen-neural-bioluminescence-matrix

## Key Interactivity/Reactivity Changes

- **Mouse position** repels the raymarched neural lattice.
- **Mouse click + velocity** persisted in `extraBuffer[3..6]`; click bursts amplify repulsion and pulse intensity.
- **Spring-damper envelopes** for bass/mid/treble in `extraBuffer[0..2]`.
- **Audio drives multiple elements**: bass → glow, mid → camera rotation, treble → chromatic aberration hue.
- **Temporal feedback** reads `dataTextureC` via `textureLoad` and writes final color to `dataTextureA`.
- Depth sampled with `textureSampleLevel(readDepthTexture, non_filtering_sampler, ..., 0.0)`.
- Click-count-derived mutation seed creates emergent pattern changes rather than direct mapping.
- Alpha tied to luminance, glow, and audio envelope.

## Line Count Delta

- Original: ~192 lines
- Upgraded: ~263 lines
- Delta: +71 lines
