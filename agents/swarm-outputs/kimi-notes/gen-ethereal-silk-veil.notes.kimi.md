# Showcase Shader: gen-ethereal-silk-veil

## Concept
Multi-layered translucent silk ribbons flowing in an ethereal wind. Designed for strong idle visuals and satisfying mouse "claim" interaction.

## Features
- generative, audio-reactive, mouse-driven, temporal, depth-aware
- upgraded-rgba, aces-tone-map, chromatic-aberration

## Parameters (zoom_params)
| # | ID | Name | Default | Mapping |
|---|----|------|---------|---------|
| x | flowSpeed | Flow Speed | 0.5 | Base downward drift speed |
| y | waveIntensity | Wave Intensity | 0.4 | Sine-wave amplitude, bass-reactive |
| z | layerDensity | Layer Density | 0.5 | Number of silk ribbons (4–10) |
| w | sheenAmount | Sheen Amount | 0.5 | Fold-peak specular highlight strength |

## Audio Reactivity
- **bass** → amplifies wave amplitude and layer opacity
- **mids** → brightens ribbon edges
- **treble** → adds edge flutter via noise

## Mouse Interaction
Mouse position creates a Gaussian "gather" effect — ribbons bend toward cursor. Click/drag amplifies distortion via `zoom_config.w`.

## Validation
```bash
naga public/shaders/gen-ethereal-silk-veil.wgsl
node scripts/generate_shader_lists.js
node scripts/check_duplicates.js
```
All pass ✅

## Showcase Readiness
- Strong idle: ✅ Always renders moving ribbons
- Satisfying claim: ✅ Mouse gather + depth parallax
- 12s rotation ready: ✅ Self-contained generative
