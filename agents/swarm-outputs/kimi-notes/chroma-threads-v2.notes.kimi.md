# chroma-threads v2 Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Added anisotropic noise (`aniso_noise`) for directional filtering along per-thread weave angles. Thread angles vary by `threadID` for organic fabric feel. Weave tension driven by bass (`tension = 1.0 + bass * 0.8`).
- **Visualist**: Silk/sheen BRDF (`sheen_brdf`) on thread highlights with Cook-Torrance-style D*G term. Subsurface scattering (`sss`) between threads on warm fiber tones. ACES tone mapping. Chromatic aberration on thread edges (`edgeCA`).
- **Interactivist**: Bass drives weave tension (tight/loose via `tension`). Mouse pulls threads creating distortion (`influence` + `pluck`). Depth controls thread density perspective (`density = densityBase * (0.7 + depth * 0.6)`).
- **Optimizer**: BRDF uses minimal safe denominators. Aniso noise shares hash with single `hash21` call. Early exit on bounds.

## Alpha Semantics
`alpha = clamp(threadDensityVis * sheen * depth + abs(offset) * 4.0 + influence * 0.1, 0.08, 1.0)`
- Thread density × sheen intensity × depth, never default opaque.

## Changes from v1
- Replaced simple thread sine waves with anisotropic noise weave simulation.
- Added sheen BRDF for silk highlights.
- Added subsurface scattering between threads.
- Added ACES tone mapping and edge chromatic aberration.
- Alpha now semantically derived from thread density × sheen × depth.
- Workgroup size standardized to `(16, 16, 1)`.

## Validation
- naga: OK
- Lines: ~138
