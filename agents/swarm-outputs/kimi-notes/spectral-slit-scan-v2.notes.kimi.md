# spectral-slit-scan v2 — Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Added 3 simultaneous parametric slits (sine wave, spiral, radial). Each slit uses distinct curve math. Spectral decomposition per slit: R/G/B sample history at different temporal offsets (`chromaShift`).
- **Visualist**: Chromatic time smearing via RGB channel lag. HDR streak accumulation with `aces_approx` tone mapping. Feedback loop blends input with multi-slit history.
- **Interactivist**: Bass (via `plasmaBuffer[0].x`) drives slit velocity (`velo`). Mouse position adds parallax offset per slit. Depth (`readDepthTexture`) creates layered separation between slits.
- **Optimizer**: Reduced texture samples by reusing `dataTextureC` for all history reads. Early boundary check. Loop unrolls well for 3 slits.

## Alpha Semantic
`alpha = clamp(slitIntensity * (0.3 + maxAge * 0.7), 0.0, 1.0)`
- `slitIntensity`: how much the multi-slit system contributes
- `maxAge`: temporal accumulation age from history alpha channels

## Lines
126 lines (upgraded from ~90)

## Bindings
Canonical 13-binding header, exact `Uniforms` struct, `@workgroup_size(16, 16, 1)`.

## Chunks Used
- `aces_approx` (filmic tone mapping)
- `hash12` (deterministic noise)

## Params
1. Slit Density (`zoom_params.x`) — controls number of active slits
2. Trail Decay (`zoom_params.y`) — history fade rate
3. Chromatic Shift (`zoom_params.z`) — RGB temporal offset
4. Curve Amplitude (`zoom_params.w`) — parametric distortion strength
