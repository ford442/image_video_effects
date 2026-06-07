# phase-memory-weave v2 Upgrade Notes

## Changes
- Replaced binary phase with continuous Ginzburg-Landau order parameter psi = rho·e^(i·theta)
- Added Allen-Cahn interface energy: dpsi/dt = epsilon·Laplacian(psi) - rho(1-rho²)·psi
- Added exponential-decay memory kernel via single readable texture channel (slowMem)
- Added opalescent thin-film interference on phase boundaries
- Added fluid caustics in low-rho regions and crystalline subsurface scattering in high-rho regions
- Bass nucleates seeds via thresholded noise injection
- Mids control grain boundary mobility
- Treble drives capillary wave ripples
- Mouse thermal deposition: heat (melt) on odd clicks, cold (quench) on even clicks
- Alpha: order parameter magnitude × interface curvature

## Lines
- v1: 96 lines
- v2: 139 lines

## Naga
- Validation: PASS (naga 29.0.3)

## Critical Fix
- Removed illegal `textureSampleLevel` calls on `dataTextureA/B` (storage textures). Now only samples from `dataTextureC` and encodes slow memory in `dataTextureC.b`.

## Agent Contributions
- **Algorithmist**: GL order parameter, Allen-Cahn energy, Laplacian on complex psi
- **Visualist**: Thin-film iridescence, caustics, subsurface scattering, ACES
- **Interactivist**: Bass→seeds, mids→mobility, treble→capillary, mouse→thermal, click parity
- **Optimizer**: Single readable texture history, compact neighbor sampling
