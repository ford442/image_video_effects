# optical-illusion-spin v2 — Upgrade Notes

## Summary
Upgraded from 80 lines to 142 lines. All 4 swarm perspectives synthesized.

## Algorithmist Changes
- Added op-art Rotating Snakes pattern via `snakePattern()`: ring-indexed alternating wedges with phase-offset angles
- Fraser spiral / peripheral drift via counter-rotating pattern layers
- Replaced simple rotation with moiré interference between counter-rotating patterns (`moireInterference(a, b) = abs(a - b) * 2.0`)
- `patA` and `patB` rotate in opposite directions with 3% scale offset for interference fringes

## Visualist Changes
- High-contrast op-art colors: cyan/yellow vs red/green alternating by angle and ring
- Chromatic afterimage simulation: R channel offset +0.008 UV, B channel offset -0.008 UV, creating RGB separation trail
- HDR on illusion edges: `vec3(0.92, 0.78, 0.55) * (patA + patB) * (0.08 + 0.18 * audio.z)`
- ACES filmic tone mapping via `acesFilm()`
- Dithering for smooth gradients: `hash21()` noise at amplitude 0.012

## Interactivist Changes
- Bass drives rotation speed: `bassSpeed = speed * (1.0 + audio.x * 1.2)`
- Mouse creates local illusion distortion: `localWarp = sin(mouseDist * 20 - time * 3) * 0.015` inside 0.3 radius
- Depth controls pattern scale perspective: `scale = 1.0 - depth * 0.3` applied to centered coords

## Alpha Strategy
`finalAlpha = illusionStrength * contrast * depth * 1.6`, clamped 0.14–0.95
- illusionStrength: `clamp((patA + patB + moire) * 0.5, 0.0, 1.0)`
- contrast: `abs(patA - patB) * 2.0 + 0.2`
- depth: read from `readDepthTexture`

## Naga Status
✅ Validation successful
