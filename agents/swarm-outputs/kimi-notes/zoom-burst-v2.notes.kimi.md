# zoom-burst v2 Upgrade Notes

## Agent Perspectives

### Algorithmist
- Replaced uniform radial sampling with exponential zoom trajectory (`pow(t, 1.7)`).
- Added angular streak sampling via per-step rotation with spin parameter.
- Aspect-corrected offset vector for distortion-free radial blur.
- Bass acceleration multiplies sample weights; depth scales streak length.

### Visualist
- Starburst light rays via 8-ray directional alignment function.
- Chromatic radial dispersion: R/B split along radial direction per sample.
- HDR bloom threshold on accumulated burst luminance.
- Film grain overlay (sin-hash) and ACES tone mapping.
- Vignette darkens edges to focus burst center.
- Source boost mixing preserves original image detail.

### Interactivist
- Bass drives burst acceleration (`bassAccel`).
- Mouse positions the burst center.
- Depth controls streak length perspective (`depthStreak`).

### Optimizer
- Quality loop bounded by user parameter (8–28 samples).
- Early `srcLum` boost computed once outside loop.
- Reused `aspectVec` to avoid per-iteration recompute.

## Files Modified
- `public/shaders/zoom-burst.wgsl`
- `shader_definitions/distortion/zoom-burst.json`

## Metrics
- Lines: 156
- naga: ✅ Validation successful
