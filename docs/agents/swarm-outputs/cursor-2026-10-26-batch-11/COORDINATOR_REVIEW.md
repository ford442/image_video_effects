# Coordinator review — cursor/batch-11 (2026-10-26)

Cards were written before the WGSL. Each new idea in `BRIEFS.md` has a `// ── Idea` comment in that shader. Earlier ideas were left in place.

| Shader | Verdict | Formula rows | Notes |
|---|---|---|---|
| viscous-drag-bilateral | pass | 9-point Laplacian (§12.2D) | Mix uses the isotropic neighbor mean. Stall reads C.z. Bilateral kernel kept. |
| liquid-viscous-grokcf1 | pass | MacCormack (§12.2D) | Correction clamped to the forward and back samples. Front uses the existing density argument. |
| liquid-perspective | pass | deep-water dispersion (§12.2D) | Middle wave's relative speed is 1. Foam reads `jacobian`. |
| interactive-ripple | pass | none | Ring multiplies the existing click envelope. Focus uses the signed wave. A stays raw. |
| rgb-ripple-waves | pass | deep-water dispersion (§12.2D); Cauchy (§12.2F) | Green clock is the speed slider. Red phase stays 0. Beer–Lambert kept. |
| velvet-vortex | pass | speed-thinning (§12.2C) | Fiber is the swirl tangent. Radius uses the existing spring speed. Single writer. |
| vortex-drag | pass | none | Spin multiplies twist only. Groove darkens before the existing ribbon palette. |
| liquid-glitch | pass | dropout bursts (§12.2B); chroma delay (§12.2B) | Tail is along x. Green is the undelayed sample. C.a still the trail weight. |
| sim-volumetric-fake | pass | Beer–Lambert (§12.2F); Henyey–Greenstein (§12.2F) | Extinction multiplies the existing attenuation. Lobe peak matches the old alignment term. |
| liquid-viscous-simple | pass | vorticity confinement (§12.2D) | Curl is analytic on `flowField`. Streak samples along `ambientFlow`. |
| liquid-mirror | pass | surface tension (§12.2D) | κ = laplacian / slope. Meniscus is the lip of `pointerMask`. Glitter and rough blur kept. |
| raindrop-ripples | pass | 9-point Laplacian (§12.2D) | Weights match 5-point magnitude on a flat field and a spike. Decay slider is still the base. |

Formula cap: 9-point Laplacian on two files, deep-water dispersion on two files. Every other row is on one file. No shared spring, ripple stamp, or new IQ palette.

KEEP VERBATIM holds: kernels, param roles, and A packing match the cards. Saved `params` were not edited.

Naga 12/12. Precommit 12/12. Dead sliders 0 new. Vitest 1435 passed. `SKIP_WASM_BUILD=1` build passed. Real-GPU visual QA was not run.
