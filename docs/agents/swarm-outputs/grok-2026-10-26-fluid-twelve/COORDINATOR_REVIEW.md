# Coordinator review — grok/fluid-twelve (2026-10-26)

Cards were written before the WGSL edits (`BRIEFS.md`). Each numbered idea is marked `// ── Idea:` in the shader.

| Shader | Verdict | Formula rows | Notes |
|---|---|---|---|
| gen-wave-equation | pass | none | Shoaling and crest refraction. Prior four ideas kept. Raw A unchanged. |
| fluid-grid | pass | none | Cell spin and stagnation bead. Prelude migration is infrastructure. |
| spec-runge-kutta-advection | pass | none | Okubo-Weiss cores and Euler residual. RK4 and LIC kept. |
| sim-slime-mold-growth | pass | none | Depletion and speck evaporation. 3×3 diffuse kept. |
| particle-disperse | pass | none | Ballistic coast and clump shadow. No extraBuffer spring. |
| alpha-fluid-simulation-paint | pass | wet-edge (§12.2C) | Pressure relief is display-only. Only wet-edge in the batch. |
| liquid-metal | pass | none | Moat foam uses existing A.b. Catchlight is display-only. |
| ferrofluid-em | pass | none | Packed frequency shared with coalescence. Remanence reads C versus the photo. |
| sim-ink-diffusion | pass | paper granulation (§12.2C) | Split is display-only. Only granulation in the batch. |
| gen-ferrofluid-monolith | pass | step-count AO (§12.2E) | `spikeField` is the old lattice, not a new primitive. Only AO in the batch. |
| sim-smoke-trails | pass | Boussinesq density (§12.2D) | Temperature buoyancy and confinement kept. Only this Boussinesq row. |
| navier-stokes-dye | pass | none | Display-only, so the numpy velocity/dye step is unchanged. ACES added on write. |

No §12.2 row is shared by two files. Saved `params` were not edited. Springs and click fronts were not added to shaders that did not already have them.

Real-GPU visual QA: external.
