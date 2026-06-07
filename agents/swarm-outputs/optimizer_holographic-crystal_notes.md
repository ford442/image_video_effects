# Optimizer Notes: holographic-crystal

## Key Changes
1. **Anti-moire attenuation**: Added `moireAttenuate()` helper that approximates screen-space LOD for the 40Hz interference pattern, fading it when pixel frequency approaches Nyquist.
2. **Early exit for background**: Pixels outside the crystal bounds (`crystalShape > 0.55`) write background and return immediately.
3. **Named constants**: PI, TAU, PHI, HOLO_*_SHIFT, FACET_ID_OFFSET replace all magic numbers.
4. **Premultiplied alpha writeback**: Output is `vec4(rgb * alpha, alpha)` for slot-chain compositing.
5. **Structured sections**: Code grouped into Parameter extraction, Early exit, Facet structure, Chromatic phase, Interior/moire, Composition, and Output blocks.

## Pipeline Integration
- dataTextureA packs (edgeGlow, moire, interior, alpha) for downstream slots.
- writeDepthTexture stores depth for depth-aware passes.
- Alpha encodes presence weight for bloom/threshold post-processing.

## Lines
~145 lines (target ~170 ±20%).
