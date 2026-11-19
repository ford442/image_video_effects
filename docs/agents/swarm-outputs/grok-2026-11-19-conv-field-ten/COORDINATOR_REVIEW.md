# Coordinator review — conv / field ten (2026-11-19)

Cards were written in `BRIEFS.md` before the WGSL. Each numbered idea has a `// ── Idea` comment. Saved params were not renamed or re-defaulted.

Formulae: density-weighted grain (§12.2A) on `film-gate-weave` only. No other §12.2 row. No shared spring, shockwave, or palette.

| Shader | Verdict | Notes |
|---|---|---|
| conv-non-local-means | pass | Gaussian window inside `patchDistance`. Centre-luma gate on the existing weight. SSD, h, tangent bias kept. |
| film-gate-weave | pass | §12.2A on the dye-cloud grain. Pin offset is one value per frame, scaled by weave. C.g still the scratch. |
| conv-morphological-erosion-dilation | pass | Penalty is on the score; stored min/max are the winning texel. Relief multiplies the existing gradient. |
| conv-frequency-domain-notch | pass | Harmonic and Hann are inside the existing cosine kernel. Band loop and residual cut kept. |
| conv-stochastic-stipple | pass | Lloyd mixes the hash site; polarity stays bright-dot. Nib darkens the ellipse rim. |
| conv-bilateral-grid-splat | pass | Slice weights are (1−frac, frac) at the centre bin. Detail add-back scales with bin coarseness. |
| multi-turing | pass | Display only. Feed, kill, DA, DB, DT untouched. A is still (a1, b1, a2, b2). |
| conv-bilateral-dream | pass | Chroma added to the existing range. Hold uses the bilateral gap. Hue slider still gates the hue shift. |
| conv-spiral-blur | pass | Arm width is a second tap on the same station. Arc-length divides the existing exp weight. |
| iso-hills | pass | Index line is every 5th level. Fall-line ticks sit on that band beside the sine hachure. A stays the relief tuple. Prelude migration is not the upgrade. |

Naga 10/10. extraBuffer 0 new. Dead sliders 0. Pasted headers 0 on these ten.

`verify:shaders:fix` fails on four other shaders that still paste a binding header in this branch's diff against `origin/main` (`cosmic-web-structure`, `gen_cyclic_automaton`, `mycelium-network`, `phase-memory-weave`). This branch is four commits behind `origin/main`. They were not edited here.
