# Coordinator review — optical / glass / holographic ten (2026-10-17)

Idea Cards were written in `BRIEFS.md` before the WGSL edits. Every numbered addition is marked in the WGSL source and in the `//  Ideas:` header banner.

| Shader | Ideas pointable in WGSL | Keep verbatim holds | A packing | Saved params | Naga |
|---|---|---|---|---|---|
| `gen-holographic-data-core` | corner-cube retroreflector bevels (`retroFlash`); bus-junction standing-wave nodes (`junctionNode`, `junctionSurface`) | pass | linear HDR display RGBA (ACES on `writeTexture`) | pass | pass |
| `gen-holographic-fracture` | Wallner stress-wave hackle arcs (`wallnerArcs`); birefringent photoelastic isochromatic fringes (`isochromatic`) | pass (spring kept) | ACES display RGBA | pass | pass |
| `gen-holographic-lens-flare-matrix` | achromatic doublet cemented-interface halo (`doubletHalo`); micro-lenticular sensor-grid satellite dots (`sensorSatellites`) | pass | raw flare state (`persistentDensity`, `persistentStreak`, `persistentDistance`, `stateAlpha`) | pass | pass |
| `gen-holographic-membrane` | Plateau-border capillary veins (`saddleRidge`, `veinFringe`); Newton black-film drainage islets (`blackFilmIslet`, `blackFilmRim`) | pass | raw `[depthNorm, normal.x, normal.y, alpha]` | pass | pass |
| `gen-holographic-plasma-geode` | druzy quartz micro-sparkle collar (`druzySparkle`); piezoelectric phantom zoning (`piezoGlow`) | pass | ACES display RGBA | pass | pass |
| `gen-holographic-rainbow-surface` | Rayleigh-Plateau ridge pearl beads (`ridgePearls`); Brewster-angle polarization extinction band (`brewsterNull`, `brewsterFringe`) | pass | ACES display RGBA | pass | pass |
| `gen-hyper-geometric-void-glass-seraph` | six-wing seraphic feather-vane facets (`seraphVanes`); singularity Einstein-ring gravitational lensing halo (`photonRing`, `einsteinColor`) | pass | ACES display RGBA | pass | pass |
| `gen-hyper-rainbow-vortex` | Kelvin-Helmholtz eyewall shear vortices (`eyewallEddies`); Ekman boundary-layer spiral inflow streaks (`ekmanInflow`) | pass | raw HDR display RGBA (ACES on `writeTexture`) | pass | pass |
| `gen-hyper-refractive-rain-matrix` | Villermaux-Bossa aerodynamic basal flattening & capillary ripples (`basalBulge`, `capRipple`, `basalBelly`); Descartes secondary internal-reflection rainbow glint (`descartesBow`) | pass | raw HDR rain RGB + coverage alpha | pass | pass |
| `gen-ice-crystal-lattice` | basal-facet stepped hopper terraces (`hopperTerraces`); cross-polarized birefringence interference tints (`birefColor`) | pass | raw HDR display RGBA (ACES on `writeTexture`) | pass | pass |

10/10 pass. Real-GPU visual QA is external.
