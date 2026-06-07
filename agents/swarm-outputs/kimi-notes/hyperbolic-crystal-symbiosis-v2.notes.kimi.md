# hyperbolic-crystal-symbiosis v2 Upgrade Notes

## Changes
- Added true Poincaré disk geodesic distance function (acosh metric)
- Replaced sine waves with 5-seed Voronoi tessellation on hyperbolic domain
- Added Gray-Scott reaction-diffusion (U/V fields) on the hyperbolic domain
- Curvature morphs between Euclidean (low), parabolic (mid), and hyperbolic (high) via mids
- Added iridescent thin-film coloring on facet edges
- Added HDR bloom at triple junctions
- Bass drives crystal growth rate
- Treble adds sparkle at grain boundaries
- Mouse warps disk center with Doppler-like color shifts
- Alpha: facet centrality × crystal purity × depth

## Lines
- v1: 103 lines
- v2: 154 lines

## Naga
- Validation: PASS (naga 29.0.3)

## Critical Fix
- Fixed WGSL bool-to-float arithmetic (`isHyperbolic * 0.08` → `select(0.18, 0.26, isHyperbolic)`)

## Agent Contributions
- **Algorithmist**: Poincaré disk metric, Voronoi on hyperbolic plane, Gray-Scott RD
- **Visualist**: Iridescent facets, triple-junction bloom, domain gradient shading, ACES
- **Interactivist**: Bass→growth, mids→curvature morph, treble→sparkle, mouse→disk warp
- **Optimizer**: Compact Voronoi loop, select-based branchless curvature
