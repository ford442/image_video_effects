# sand-dunes v2 Upgrade Notes

## Changes
- Added Bagnold dune physics with wind-driven sand transport
- Implemented anisotropic fBm stretched along wind direction
- Added separation bubbles at dune crests (lee-side deposition)
- Ripple superposition on dune flanks using anisotropic coordinates
- Desert palette: ochre -> sienna -> umber with subsurface scattering on slip faces
- HDR specular saltation sparkles driven by treble
- Approximate ACES tone mapping for HDR sand colors
- Atmospheric haze modulated by depth
- Wind shadows behind mouse cursor

## Audio Reactivity
- Bass drives wind speed (dune migration rate)
- Mids shift wind direction
- Treble adds saltation sparkles on slip faces

## Interactivity
- Mouse position creates wind shadows (dunes shelter behind cursor)
- `zoom_params` control dune scale, wind speed, erosion, shadow depth

## Alpha Strategy
`alpha = sand_density * wind_exposure * (1.0 - haze)`
- Sand density from fBm height + ripple mask
- Wind exposure from wind speed parameter
- Haze from depth texture

## Line Count
~148 lines

## Validation
Run `naga public/shaders/sand-dunes.wgsl` after write.
