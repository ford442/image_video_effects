# Coordinator review — ecology-field ten (2026-11-15)

Cards were in `BRIEFS.md` before the edits. Each numbered idea is marked in the WGSL with an `Idea` comment. Saved params on shaders that already had them were not renamed or re-defaulted.

| Shader | Verdict | Why |
|---|---|---|
| predator-prey-ecology | pass | Holling, grazing scar, and age cohorts sit on the existing Lotka–Volterra step. Render still writes the raw field back. |
| gen-astro-orrery-blackbody | pass | The original annulus and starfield remain. Flanking rings, blackbody, and the orbital wake are additive. New params default to the old constants (temperature 0.08 ≈ 2000 K orange). |
| sim-smoke-trails-thermal | pass | Solver packing unchanged. MacCormack is clamped and does not touch the velocity integration. Blackbody replaces the gray-to-orange lerp the name already claimed. |
| gen-string-theory-structure | pass | The four-fold loop is the same. Core/sheath, fold count, and the rotational wake are inside it. New params default to gap 0.5, rate 20, trail 0.85, glow 0.05. |
| jfa-aurora-voronoi | pass | Same 3×3 flood. The jump now halves; Jump Scale still sets the reach (default sum matches the old 32×8). Curtains use the distance gradient. Counter is `extraBuffer[133]` at (0,0) only. |
| photonic-caustics-graph | pass | Photon loop, Fresnel, and Snell stay. Cauchy and Beer–Lambert consume the existing IOR split and path length. The repeat averages a second stratum instead of treating the caustic as a normal. |
| luma-flow-field | pass | Second pass on the 2026-09-12 LIC. Adds the upstream sample and pooling from taps the kernel already fetched. No new palette. |
| physarum-agents | pass | Steer and the CPU-spec constants are untouched. Crust and peristalsis are render-only. |
| sim-sand-dunes-rgba | pass | Second pass on the 2026-09-12 dune field. Repose and lee fallout use the populations and the wind sign already in the step. |
| wave-tank | pass | Same velocity integrator. 9-point stencil matches the 5-point on an x-only wave. `.b` is finally the previous height, and foam reads it. State copied back is still raw. |

Formula check: blackbody on two files (the two temperature emitters). MacCormack, 9-point, fold-count, Cauchy, and Beer–Lambert each on one file. No spring overlay.

Floor: bindings via `#include "_prelude.wgsl"`, 16×16 (physarum step stays 64×1, one agent per invocation), exact `textureLoad` of `dataTextureC` on the history the ideas read, ACES only on display RGB, semantic alpha on the present passes.

Real-GPU visual QA: external. Not claimed from this VM.
