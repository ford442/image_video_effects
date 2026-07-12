# Interactivist Notes: gen-cybernetic-mycelium-neural-web

## Key Interactivity/Reactivity Changes

- **Mouse position** now warps mycelial nutrient attraction and pulse seeding.
- **Mouse click + velocity** are persisted in `extraBuffer[3..6]`; click bursts inject mutation seeds and amplify attraction.
- **Spring-damper audio envelopes** for bass/mid/treble in `extraBuffer[0..2]` smooth plasma reactivity.
- **Audio drives multiple elements**: bass → growth/feedback mix, mids → color bloom, treble → chromatic aberration and pulse hue.
- **Temporal feedback** now reads `dataTextureC` via `textureLoad` and writes the final color to `dataTextureA` every frame.
- Added depth-aware feedback by sampling `readDepthTexture` with `textureSampleLevel(..., 0.0)`.
- Emergent mutation behavior from click-count-derived seeds rather than direct 1:1 mapping.
- Alpha now tied to interaction intensity, trail density, and audio envelope.

## Line Count Delta

- Original: ~191 lines
- Upgraded: ~260 lines
- Delta: +69 lines
