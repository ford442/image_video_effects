# Coordinator review — cursor/batch-15 (2026-10-27)

Cards were written before the WGSL. Each numbered idea is named in the shader. Saved params were not renamed or re-defaulted.

| Shader | Verdict | Ideas in the diff | Formula | Packing |
|---|---|---|---|---|
| log-polar-droste | pass | Droste frame; sector gutter | none | ACES display RGBA |
| ethereal-swirl | pass | silver lining; wind smear | none | ACES display RGBA |
| fractal-image-surf | pass | orbit-trap veins; calm lake | §12.2E orbit trap | ACES display RGBA |
| polar-warp-interactive | pass | stretch bleach; atan2 branch cut | none | raw bass/mouse in A |
| mouse-julia-morph | pass | distance rim; arg(z) palette | none | ACES display RGBA |
| mouse-hyperbolic-navigator | pass | horocycle gutter; Cauchy split | §12.2F Cauchy | ACES display RGBA |
| perspective-tilt | pass | cos⁴ falloff; card edge | §12.2A cos⁴ | ACES display RGBA |
| infinite-spiral-zoom | pass | Droste frame; upstream zoom trail | none | display RGBA, exact C |
| parallax-shift | pass | relief step; disocclusion gap | none | ACES display RGBA |
| swirling-void | pass | photon caustic; ISCO lip | none | pre-ACES RGB in A |
| origami-fold | pass | valley/mountain crease; cast shadow | none | display RGBA |
| julia-warp | pass | calm interior; distance contour | none | ACES display RGBA |

Formula use: orbit trap once, Cauchy once, cos⁴ once. No row on three files.

Dead `plasmaBuffer[1..]` reads and the swirling-void colour/state mix-up are fixes, listed in NOTES, not counted as ideas.

Checklist: cards exist; ideas are commented in the main path; kernels and param roles kept; no shared spring or IQ stamp; Naga 12/12; prelude consistent; dead sliders 0 new; list JSON only these ids.
