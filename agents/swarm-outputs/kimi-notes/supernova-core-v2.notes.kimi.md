# supernova-core v2 Upgrade Notes

## Changes
- Added Sedov-Taylor blast wave expansion: r ∝ t^(2/5)
- Radioactive decay luminosity: 56Ni -> 56Co -> 56Fe with time-varying intensity
- Rayleigh-Taylor instability fingers at ejecta boundary using fBm noise
- Neutrino-driven convection cells near inner ejecta
- Blackbody cooling sequence on shockwaves: blue -> white -> yellow -> red
- Iron emission lines (blue-green) at RT fingers
- Chromatic aberration on relativistic particle rays
- Light echo shell modulated by depth
- Approximate ACES tone mapping

## Audio Reactivity
- Bass drives shock expansion rate
- Mids seed Rayleigh-Taylor finger amplitude
- Treble triggers nickel-cobalt decay flares

## Interactivity
- Mouse creates asymmetric ejecta (binary companion kick effect)
- `zoom_params` control expansion, ray count, shockwave speed, chromatic shift

## Alpha Strategy
`alpha = ejecta_density * shock_temperature * depth`
- Ejecta density from core, shockwaves, RT fingers, and rays
- Shock temperature normalized from blackbody cooling
- Depth texture controls light echo shell perspective

## Line Count
~153 lines

## Validation
Run `naga public/shaders/supernova-core.wgsl` after write.
