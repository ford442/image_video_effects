# Coordinator review — grok/small-ten (2026-11-15)

Cards were in `BRIEFS.md` before the WGSL edits. Each numbered idea has a `// ── Idea n` comment. Saved params were not renamed or re-defaulted. No new spring. No shared palette, ripple stamp, or §12.2 row.

| Shader | Verdict | Why |
|---|---|---|
| adaptive-mosaic | pass | Lip uses the existing bevel face. Glaze is per `tileId`. Subdivision, mortar, runners, Voronoi kept. |
| chroma-kinetic-blackbody | pass | Wien scales the existing R/B offsets from temperature. Core bleach uses the same falloff. Split axis, kinetic boost, 0.6 mix kept. |
| hybrid-magnetic-field | pass | Filings break the existing sine. Null is the weaker-pole stagnation and is masked by `fieldMag`. LIC and both poles kept. A stays pre-ACES. |
| liquid-smear-structure | pass | LIC length is the same ±3 loop, gated by coherence. Wet-edge (§12.2C) only here. Solver unchanged. |
| predator-camouflage | pass | Pigment chase reads the field A already wrote. Luma match is interior-only; rim additions stay after it. A stays raw fields. |
| ring-slicer | pass | Shear uses `ringPos` the seam already had. Kerf darkens that same distance. Alternating direction, wobble, grab-twist, palette kept. |
| spectral-bleed-confinement | pass | Fan stays 120°. Axis leans toward the gradient this file used to throw away. Residual is the confined energy. Existing spring untouched. |
| pp-ssao | pass | Bias and horizon use the existing taps and the radius slider. Sample counts, cosine weight, bent normal kept. |
| alpha-spectral-decompose | pass | Gabor was already in the file and unused. Low band is the only one that reads C. Gains stay the four sliders. A stays raw bands. |
| radiating-displacement | pass | Spread is inside `waveDisplacement`. Saturation scale sits on the cursor wave only. Neutral gate and click path kept. |

Formula check: wet-edge (§12.2C) appears once. No other §12.2 row. No pair of files shares a formula.

Packing check: display ACES where C is read as color (`adaptive-mosaic`, `chroma-kinetic-blackbody`, `spectral-bleed-confinement`, `ring-slicer`, `pp-ssao`, `radiating-displacement`). Linear or pre-ACES in A where the next frame needs the unmapped paint or trails (`liquid-smear-structure`, `hybrid-magnetic-field`). Raw fields where C is a field (`predator-camouflage` pigment, `alpha-spectral-decompose` bands).

Naga 10/10, extraBuffer clean, dead sliders 0. Real-GPU visual QA is external.
