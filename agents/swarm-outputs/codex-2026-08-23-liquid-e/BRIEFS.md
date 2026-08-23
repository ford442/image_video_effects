# Codex (e) — Ferro / Melt / Tensor / Fluid-Sim batch

## Cohort

| # | Shader | Category | Focus |
|---:|---|---|---|
| 1 | `liquid-jelly-fluid` | advanced-hybrid | Elastic vortical jelly dye |
| 2 | `liquid-metal-prismatic` | advanced-hybrid | Prismatic liquid-metal facets |
| 3 | `liquid-oil-iridescence` | advanced-hybrid | Advected thin-film interference |
| 4 | `liquid-smear-structure` | advanced-hybrid | Structure-tensor LIC paint transport |
| 5 | `melting-oil-blackbody` | advanced-hybrid | Thermal-gradient oil and blackbody radiation |
| 6 | `honey-melt-blackbody` | advanced-hybrid | High-viscosity honey thickness and heat |
| 7 | `viscous-drag-bilateral` | advanced-hybrid | Edge-aware bilateral displacement gel |
| 8 | `hyper-tensor-fluid` | advanced-hybrid | Anisotropic tensor-guided fluid |
| 9 | `sim-fluid-feedback-coupled` | simulation | Coupled velocity/pressure/density feedback |
| 10 | `ripple-tank` | simulation | Seven-dispatch capillary wave tank |

## Shared contract

- Preserve the four saved source `params` for every effect.
- Keep the canonical 13 bindings and 16×16×1 compute workgroups.
- Use ACES for final color and source/state-derived semantic alpha.
- Write temporal state only to `dataTextureA`; never write `dataTextureB`.
- Read feedback only by bounded exact `textureLoad` from `dataTextureC`.
- Use genuine bass/mid/treble values from `plasmaBuffer[0].xyz`.
- Keep persistent scratch state out of engine FFT slots. This cohort uses no
  `extraBuffer` state, which is stricter than the allowed `[133..138]` range.
- Preserve aspect-correct pointer position, held interaction, and capped,
  age-guarded click-ripple behavior.
- Validate every WGSL module with actual Naga, not structural parsing alone.

## Ripple Tank ownership correction

The seven-dispatch graph remains `step×4 → inject → capillary → render`. Its
legacy B handoff and broad coarse-grid scratch channel are removed. Every node
now consumes the latest A state through the graph runner's A→C barrier and
writes back only to A. The capillary node stores local foam energy in the
per-pixel A/C state instead of shared `extraBuffer` cells.
