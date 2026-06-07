# ink-diffusion v2 Upgrade Notes

## Algorithmist Perspective
- Replaced simple blur diffusion with Navier-Stokes advection-diffusion
- Added curl noise velocity field for turbulent advection
- Vorticity confinement: computed vorticity from neighbor differences, applied vorticity force
- Surface tension at ink-water boundaries via gradient magnitude detection
- Depth modulates diffusion coefficient (shallower = faster spread)

## Visualist Perspective
- Sumi-e ink wash aesthetic preserved with turbulent eddies
- Paper fiber texture via multi-scale hash noise (`paperFiber()`)
- Chromatic edge darkening: magenta/blue bias at wet edges based on mids
- HDR specular on wet regions: animated specular angle with bass boost
- ACES tone mapping on final color
- Wet ink color enriched with bass-reactive highlights

## Interactivist Perspective
- Bass drives ink injection rate (`injection = bass * 0.08`)
- Mouse deposits both broad brush strokes and concentrated pellets
- Depth controls diffusion coefficient
- Audio adds random splatter with turbulence coupling

## Alpha Strategy
Alpha = `ink_concentration * (1.0 - water_clarity) * depth`
- Ink concentration from simulation
- Water clarity inverse to ink density
- Depth as perspective modulator

## Lines
Upgraded from 93 lines to ~141 lines.

## Naga Status
PASSED — validation successful.
