# Interactivist Notes: gen-showcase-nebula-core

## Key Interactivity/Reactivity Changes

- **Mouse position** already acted as a gravity well; now **mouse velocity** adds a rotational swirl to the domain warp.
- **Mouse click + velocity** persisted in `extraBuffer[3..6]`; click bursts amplify star formation and shockwave mutation.
- **Spring-damper envelopes** for bass/mid/treble in `extraBuffer[0..2]` smooth audio reactivity.
- **Audio drives multiple elements**: bass → ionization/rings/feedback mix, mid → warp speed, treble → sparkles.
- **Temporal feedback** reads `dataTextureC` via `textureLoad` and writes final color to `dataTextureA`.
- Click-count-derived mutation seed creates emergent pattern changes.
- Alpha tied to color luminance and click-burst intensity.

## Line Count Delta

- Original: ~196 lines
- Upgraded: ~258 lines
- Delta: +62 lines
