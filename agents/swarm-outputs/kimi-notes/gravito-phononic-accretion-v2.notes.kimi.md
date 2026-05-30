# gravito-phononic-accretion v2 Upgrade Notes

## Changes
- Added SPH cubic-spline kernel density estimation (4x4 neighbor sampling)
- Added orbital velocity field from angular momentum conservation (v = L/r² perpendicular)
- Added shock detection via density gradient + velocity divergence
- Replaced simple color mapping with temperature-based blackbody approximation
- Added volumetric light scattering along density gradients
- Added HDR bloom on shock fronts
- Added ACES tone mapping
- Added acoustic standing waves driven by treble
- Added ripple-array density perturbations
- Alpha now carries semantic meaning: density × temp × (1 - bgEmpty)

## Lines
- v1: 96 lines
- v2: 138 lines

## Naga
- Validation: PASS (naga 29.0.3)

## Agent Contributions
- **Algorithmist**: SPH kernel, orbital velocity, shock detection
- **Visualist**: Blackbody coloring, volumetric scatter, HDR bloom, ACES
- **Interactivist**: Bass→mass, mids→precession, treble→standing waves, mouse→rogue body, ripples→perturbations
- **Optimizer**: Branchless select(), distance-based LOD implicit in kernel falloff
