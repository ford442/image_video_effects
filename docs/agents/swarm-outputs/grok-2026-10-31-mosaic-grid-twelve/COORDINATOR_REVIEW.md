# Coordinator review — mosaic / grid / voronoi twelve

Cards are in `BRIEFS.md` (written first). Ideas are marked in WGSL with `Idea` comments. Naga 12/12, extraBuffer audit pass, dead-slider audit pass on these ids. Saved params unchanged.

| Shader | Verdict | Why |
|---|---|---|
| hex-mosaic | pass | Bevel faces the pointer. Rejected hex centre stains the grout. Reveal, grout, glint kept. |
| triangle-mosaic | pass | Vertex beads and a second sample along the existing tilt. Grid, grout, seam kept. Not the hex grout leak. |
| mouse-voronoi-mosaic | pass | Brown–Conrady (§12.2B), dark lead, age patina. Click-site motion kept. |
| focal-pixelate | pass | Aperture well and a wider hex kernel with defocus. A/B metadata packing kept. |
| pixelate-blast | pass | Dark seam under the existing glow, smear along `blastDir`. Cascade and bevel kept. |
| entropy-grid | pass | Cell lock and square-grid cracks scale with chaos × influence. Warp and Clifford kept. |
| chroma-shift-grid | pass | Cauchy split (§12.2F) of the existing offset. Pointer raises the two existing amounts. Modes kept. |
| hex-pulse | pass | C.r ring-down and cos-phase shade. Raw A packing kept. |
| ripple-blocks | pass | Gutter uses the cell colour. Trail is an exact cell-centre load. Slider roles not remapped. |
| voronoi-shatter | pass | Angle coasts from C.b. Fissure uses the gap slider. Raw A packing kept. |
| interactive-voronoi-web | pass | Width tracks the pulse. Negative half-cycle dims the photo. Pulses and bass burst kept. |
| voronoi-light | pass | Inverse-square core (§12.2F) inside the existing radius. Facet faces the lantern. Spring left as it was. |

Formula check: Cauchy, inverse-square, and Brown–Conrady each appear once. No shared spring/ripple/IQ stamp.

Real-GPU visual QA: external. This VM has no hardware GPU.
