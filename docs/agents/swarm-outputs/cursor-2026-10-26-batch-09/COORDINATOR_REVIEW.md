# Coordinator review — cursor/batch-09 (2026-10-26)

Cards were written before the WGSL. Each numbered idea in `BRIEFS.md` has a `// ── Idea` comment in that shader.

| Shader | Verdict | Formula rows | Notes |
|---|---|---|---|
| liquid-tensor-vortex | pass | none | Well + filaments use Q and `principal` already computed. |
| liquid-warp-interactive | pass | MacCormack (§12.2D) | Second idea is the Coanda waterline, not a second advection scheme. |
| ink-bleed-fluid | pass | 9-point Laplacian (§12.2D); granulation (§12.2C) | Prior capillary and wet-edge comments kept. New ideas numbered 3 and 4. |
| rain-ripples | pass | deep-water dispersion (§12.2D) | Primary ring amplitude unchanged. Jet uses the existing Voronoi cell. |
| liquid-swirl | pass | none | Eye wall is the Oseen peak radius. Stagnation is caustic × low speed. |
| honey-melt | pass | surface tension (§12.2D) | Comb-wall was claimed on 2026-09-08 and missing from the body. Meniscus is the second addition. |
| magnetic-ring | pass | none | Pointer texels and spoke integers unchanged. Dipole is 1/r³, not a shared glow. |
| ferrofluid | pass | surface tension (§12.2D) | Second file on that row. Labyrinth is outside the spike envelope. |
| hyper-tensor-fluid | pass | MacCormack (§12.2D) | Second file on that row. Viscosity weights the old four taps. |
| sim-fluid-feedback-coupled | pass | shallow-water continuity (§12.2D) | Buoyancy and schlieren kept. Torque is the partner of the existing buoyancy, not a second confinement. |
| mouse-fluid-coupling | pass | speed-thinning (§12.2C) | Pointer state moved off the clobbered (0,0) texel. C is `textureLoad` only. |
| gen-abyssal-ferrofluid-singularity | pass | step AO (§12.2E); SDF curvature (§12.2E) | Sphere, gyroid, and held warp kept. |

Formula cap: MacCormack on two files, surface tension on two files, every other row on one file. No shared spring, ripple stamp, or IQ palette.

KEEP VERBATIM holds: kernels, mode-free param roles, and A packing match the cards. Saved `params` were not edited.

Naga + precommit on these 12 files passed. Full-catalog dead-slider and extraBuffer audits reported 0 new findings. Real-GPU visual QA was not run.
