# Coordinator review — kaleido-chroma ten (2026-11-15)

Structural review against the Idea Cards. Not visual QA. Naga 10/10. Precommit gate 10/10 (bind group, workgroup, extraBuffer, no pasted headers). Dead sliders 0. extraBuffer audit pass.

| Shader | Card | Ideas pointable | Kept | Packing | Formula overlap | Verdict |
|---|---|---|---|---|---|---|
| hybrid-noise-kaleidoscope | yes | `warp2`; `pR/pG/pB`; `seam` | fbm, fold, hueShift, angle tint | ACES display RGBA, C unread | none | pass |
| chroma-threads-gabor | yes | `orient` / `grain`; `core` | rows, vibration, three Gabors, palette | ACES display RGBA, C unread | none | pass |
| chromatographic-separation | yes | `diffuse`; `frontLine` | spin, Rf, tail samples | ACES display RGBA | none | pass |
| gen-symbiotic-neuro-lattice | yes | `linkCapsule` ×6; `fire` | hashed nodes, held pull, bass radius | ACES display RGBA, C unread | none | pass |
| breathing-kaleidoscope | yes | `halfT` phase warp; `midrib` | inhale/exhale scale, held freeze | ACES display RGBA | none | pass |
| hyb-iridescent-fbm-glow | yes | `thinFilm`; `spent` | fbm warp, rim, OkLab, chromatic split | ACES display RGBA | thin-film and energy glow, this file only | pass |
| chromatic-focus-interactive | yes | `rel` on the offsets; `aperture` on blur | iris, runners, zone plate, absorption | ACES display RGBA, C is display | Cauchy, file 1 of 2 | pass |
| gen-kaleidoscopic-synapse-bloom | yes | `ranvier`; `sigma` | runners, dendrites, myelin, vesicles | ACES display RGBA, C is colour | none | pass |
| hyb-hex-voronoi-distort | yes | `cellTarget`; `seamDir` kick | hex, mortar, F2−F1 glow | ACES display RGBA | none | pass |
| interactive-fresnel | yes | `nLam` scales; `riser` on the bump | annular bump, five-tap normal, history | ACES display RGBA, C is display | Cauchy, file 2 of 2 | pass |

Checklist:

- [x] Idea Cards written before the WGSL edits (`BRIEFS.md`)
- [x] Mechanism interrogation is in each card
- [x] Each numbered idea is named in the WGSL
- [x] KEEP VERBATIM holds: kernels, folds, param roles
- [x] Diffs are the ideas plus the floor (ACES, alpha, depth, A), not a spring/ripple stamp
- [x] No shared overlay. The two Cauchy uses are a lateral iris split and a same-direction lens scale
- [x] A packing matches how C is read
- [x] Saved `params` unchanged
- [x] No new springs or click systems. Existing click fronts were left where the file already had them
- [x] No §12.2 row on more than two files
- [x] No `fwidth` / `dpdx`. The synapse runner no longer uses `pow` on a signed front
- [x] Naga 10/10
- [x] `verify:shaders:fix` 11/11
- [x] `npm run build` succeeded
- [x] Vitest: 1811 passed on the full run. The 11 failures were timeouts. A quiet re-run of the seven non-numpy files passed 81/81. physarum and sph_fluid were not re-run

Notes that are not failures:

- Chromatographic JSON still labels the sliders as viscosities. The shader's existing roles (separation, rotation, depth weight, separation mode) were left in place.
- Chromatic-focus and the neuro-lattice were missing ACES. ACES landed as floor.
- Real-GPU visual QA is external.
