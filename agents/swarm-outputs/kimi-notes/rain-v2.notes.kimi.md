# rain v2 — Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Added streak physics with gravity acceleration (`gravity = 1.0 + dropSeed * 2.5`), exponential fall curve, wind drift per droplet, splash particles on simulated ground impact.
- **Visualist**: Chromatic droplet lensing (R/G/B displaced separately), HDR bloom on bright sources through rain, ACES tone mapping, fog/mist layer with depth-scaled density, rain tint shifts with mids.
- **Interactivist**: Bass drives gust strength (`gust = audio.x * 0.04`) and bloom intensity; mouse X creates wind shear (`mouseWind`); depth scales droplet size/perspective (`depthScale`).
- **Optimizer**: Early per-cell rejection via `step(0.65, dropSeed)`; distance-based LOD implicit in grid sampling.

## Alpha Semantics
`finalAlpha = dropletAlpha * motionBlurStrength * depth + mistLayer * 0.6 + splash * 0.4`
- Encodes droplet density, motion blur strength, and depth perspective. Mist and splash add atmospheric contribution.

## Line Count
~137 lines

## Naga Status
✅ Validation successful

## Bindings
Exact canonical 13-binding header used. No additions.

## Params
Unchanged: rain_density, fall_speed, wind, wetness.
