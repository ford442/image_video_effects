# cyber-physical-portal v2 — Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Added event-horizon frame-dragging approximation (`frameDrag` rotates angle based on distance falloff), gravitational lensing displaces sample UV radially, accretion disk bands with animated jitter and hash noise.
- **Visualist**: Cyan/magenta holographic rim (`cyanMagenta`), chromatic aberration on lensed regions (R/B channels sampled with offset), HDR bloom on portal edges and core, ACES tone mapping, ring grid scrolls with audio-driven spin speed.
- **Interactivist**: Bass drives portal spin (`spinSpeed = 1.5 + audio.x * 3.0`); mouse positions portal center; depth controls lensing strength (`lensingScale`).
- **Optimizer**: Single-pass lensing with rotated/distorted UV; bloom derived from max channel to avoid extra texture samples.

## Alpha Semantics
`finalAlpha = rimIntensity * lensingConfidence * depth + mask * 0.15`
- Encodes portal rim glow intensity, gravitational lensing confidence, and depth. Core portal mask adds base visibility.

## Line Count
~140 lines

## Naga Status
✅ Validation successful

## Bindings
Exact canonical 13-binding header used. No additions.

## Params
Unchanged: portal_radius, swirl_amount, grid_density, glow.
