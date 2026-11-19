# Coordinator review — zoom / weave ten (2026-11-19)

Cards were written in `BRIEFS.md` before the WGSL edits. Each numbered idea is marked in the shader with a `// ── Idea` comment.

| Shader | Ideas in the diff | Kept | Packing | Formulae | Verdict |
|---|---|---|---|---|---|
| liquid-zoom | radial C smear; off-axis chroma in `sampleLayer` | 4-layer zoom, sliders, click pulses | ACES display RGBA | none | pass |
| liquid-jelly | Poisson bulge; soliton beads | Kelvin-Voigt, shear, tether, candy, spring | ACES display RGBA, alpha = thickness | none | pass |
| gen-celestial-weave | over-under shed; star occultation | weave, glint, parallax, pulses, lens | ACES display RGBA | none | pass |
| gen-cycloid-bloom | fixed circle; contact bead | hypotrochoid search, epi, sparks, roller | ACES display RGBA | none | pass |
| gen-luminous-fluid-chladni-resonator | crossing piles; free-edge clearance | modes, sand, Faraday, flow, meniscus | ACES display RGBA | none | pass |
| mouse-electromagnetic-aurora | E×B shear; log-spaced equipotentials | LIC, curtains, anchored charges | display + pointer texels | none | pass |
| gen-luminescent-singularity-loom | heddle shed; pluck antinode | fold, lens, beads, pluck | ACES+gamma display | none | pass |
| gen-percolation-threshold | lattice bonds; union-find root | 80×60 labels, pulses, red bonds | lattice state + display elsewhere | none | pass |
| sacred-geometry-torus | sacred ring restored; strand over-under | taps, phi nodes, phyllotaxis, gold | pre-ACES display (was a packing lie) | none | pass |
| signal-noise | chroma delay; dropout burst | YUV path, head-switch, staircase, crawl, spring | ACES display RGBA | §12.2B chroma delay; §12.2B dropout | pass |

Checklist:

- [x] Idea Cards and mechanism answers are in `BRIEFS.md`
- [x] Each idea is pointable from a comment in the WGSL
- [x] Slider roles unchanged (`params` ids, names, defaults, min, max, step)
- [x] No spring, ripple stamp, or IQ palette added across the batch
- [x] §12.2 rows appear on one file only (`signal-noise`)
- [x] Formulae consume quantities the file already had (YUV sample, VHS intensity)
- [x] Springs left only where they already existed (jelly, signal-noise)
- [x] `gen-celestial-weave` no longer writes `extraBuffer[0]`
- [x] Prelude migration of percolation and torus is recorded as infrastructure, not as the idea

Naga and the shader gates are recorded in `NOTES.md` after the run. Real-GPU visual QA is external.
