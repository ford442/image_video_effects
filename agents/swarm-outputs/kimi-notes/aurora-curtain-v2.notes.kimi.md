# aurora-curtain v2 Upgrade Notes

## Changes
- Added Chapman layer excitation model with altitude-dependent colors
  - High altitude: atomic oxygen red (630nm)
  - Mid altitude: atomic oxygen green (557.7nm)
  - Low altitude: N2+ blue/purple and N2 pink/magenta
- Kelvin-Helmholtz instability along curtain edges with noise-driven folding
- Rayleigh scattering of underlying atmosphere
- Improved starfield with twinkle
- HDR bloom on curtain folds
- Approximate ACES tone mapping
- Atmospheric extinction by depth

## Audio Reactivity
- Bass drives geomagnetic storm intensity (curtain brightness)
- Mids fold curtains via KH instability amplitude
- Treble creates rayed band structures

## Interactivity
- Mouse drags the magnetic zenith (curtain anchor point)
- `zoom_params` control layers, flow speed, curtain width, color shift

## Alpha Strategy
`alpha = excitation_rate * atmospheric_transparency * depth`
- Excitation rate accumulated per curtain layer
- Transparency decreases near horizon (Rayleigh scatter)
- Depth texture modulates overall opacity

## Line Count
~142 lines

## Validation
Run `naga public/shaders/aurora-curtain.wgsl` after write.
