# Coordinator review — light / optical twelve

Cards were written in `BRIEFS.md` before the WGSL edits. Each numbered idea has a `// ── Idea` comment. On `pp-bloom` and `volumetric-god-rays` the previous pass already used "Idea 1/2", so the new pair is commented as Idea 3 and Idea 4.

| Shader | Verdict | Notes |
|---|---|---|
| divine-light | pass | Phase warmth and veiling use the existing HG weight and ray luma. March and params kept. No new formula row. |
| neon-light | pass | Bore/sheath and cooling phosphor use the existing ridge and raw C phosphor. Packing unchanged. |
| volumetric-god-rays | pass | Beer–Lambert modulates the existing decay. Cauchy replaces the old per-channel tint with a spatial split. |
| light-leaks | pass | Halftone on disk did not implement the named params. Leak blobs restored, then rebate, dye fringe, and halation. |
| kimi-spotlight | pass | Inverse-square sits inside the existing gate. Airy sits on the existing hotspot. Spring kept, not added. |
| alpha-aurora-bands | pass | Lower border uses altitude. Rayleigh limb uses summed emission. Not the ribbon shader. |
| aurora_borealis | pass | Proton arc uses the first ribbon's y and the width slider. Stars use coverage. A.a still the bass envelope. |
| pp-bloom | pass | Energy take is on the spread this file already adds. Cauchy is only on the horizontal streak. |
| velvet-scatter-bloom | pass | Spectral weights are inside the existing tap loop. Trough uses `napDir`. |
| neon-pulse-edge | pass | Afterglow is the edge magnitude this file already stores. Travel uses the Sobel tangent and pulse speed. |
| interactive-film-burn | pass | Blister and rising smoke use glow width and the smoke mask. Scar reads the documented mask packing instead of treating it as a photo. |
| spec-spherical-harmonics-light | pass | Cosine lobe, L1 specular, and Fresnel all consume the coefficients and normal already computed. |

Formula cap: no §12.2 row on more than two files. Beer–Lambert and Cauchy are the only rows on two files, and the second idea on each of those files is different.

Saved `params` were not renamed or re-defaulted. Real-GPU visual QA is external.
