# solarize-warp v2 — Upgrade Notes

## Summary
Upgraded from 77 lines to 132 lines. All 4 swarm perspectives synthesized.

## Algorithmist Changes
- Added proper Sabattier effect via `sabattier()` function with tone curve inversion at threshold
- Edge-aware inversion using `smoothstep(0.0, 0.12, edge) * step(threshold, luma)`
- Replaced simple rotation warp with domain-warped fBm displacement (`fbm()` with 4 octaves, `fbm(uv * 3.0 + time * 0.25 + audio.y * 0.5)`)
- fBm drives `warpAngle` offset alongside twist + sinusoidal displacement

## Visualist Changes
- Mackie lines: bright edge lines at solarization threshold boundary (`smoothstep(0.08, 0.0, edge) * strength * 0.55`)
- Split-tone shadows/highlights: shadow tint `vec3(0.95, 0.42, 0.15)` vs highlight tint `vec3(0.12, 0.62, 0.92)`, blended by luma
- ACES filmic tone mapping via `acesFilm()`
- Film grain via `hash22()` at amplitude 0.018
- Man Ray darkroom aesthetic maintained

## Interactivist Changes
- Bass drives solarization threshold oscillation: `threshold = solarizeThreshold + sin(time * 1.8) * audio.x * 0.18 * influence`
- Mouse warps displacement field via centered rotation + fBm
- Depth controls parallax between solarized layers: `parallax = depth * 0.04 * influence` applied to layer UV

## Alpha Strategy
`finalAlpha = effectIntensity * edgeDensity * depth * 1.8`, clamped 0.12–0.95
- edgeDensity: `smoothstep(0.0, 0.12, abs(luma - threshold))`
- effectIntensity: user parameter
- depth: read from `readDepthTexture`

## Naga Status
✅ Validation successful
