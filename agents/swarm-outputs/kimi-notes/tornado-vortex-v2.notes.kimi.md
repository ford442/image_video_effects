# tornado-vortex v2 Upgrade Notes

## Changes
- Replaced simple spiral with Rankine vortex model
  - Tangential velocity: v_θ = Γ/2πr outside core, v_θ ∝ r inside core
  - Added radial inflow and vertical updraft terms
- Lagrangian debris advection with 24 particles using golden-angle distribution
- Condensation funnel with subsurface scattering approximation
- Lightning flash illumination with branch patterns
- Ground dust layer
- HDR bloom on electrical discharge
- Approximate ACES tone mapping

## Audio Reactivity
- Bass drives vortex intensity (Fujita scale proxy)
- Mids widen the funnel
- Treble triggers lightning flashes

## Interactivity
- Mouse acts as a probe that gets flung by vorticity near the cursor
- `zoom_params` control intensity, spin speed, debris amount, lightning

## Alpha Strategy
`alpha = debris_density * condensation_opacity * depth`
- Debris density from Lagrangian particle accumulation
- Condensation opacity from Rankine funnel + spiral streaks
- Depth texture modulates debris size perspective and final opacity

## Line Count
~152 lines

## Validation
Run `naga public/shaders/tornado-vortex.wgsl` after write.
