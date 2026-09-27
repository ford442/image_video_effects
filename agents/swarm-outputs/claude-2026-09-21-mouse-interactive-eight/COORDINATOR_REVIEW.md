# Coordinator review — interactive-mouse eight (2026-09-21)

Checklist from `docs/SHADER_UPGRADE_BATCH.md` §9, applied per file.

| Shader | Idea Card first | Ideas pointable in diff | KEEP VERBATIM holds | Diff ≠ ≥70% boilerplate | No shared overlay | A packing matches C read | Saved params unchanged | Springs/ripples native-only | Naga + extraBuffer + dead-sliders |
|---|---|---|---|---|---|---|---|---|---|
| mouse-magnetic-pixel-sand | ✅ | ✅ (field-line chain, bass pulse, residue) | ✅ | ✅ | ✅ | ✅ (new C read documented) | ✅ | ✅ (ripple loop pre-existing, no new spring) | ✅ |
| magnetic-rgb | ✅ | ✅ (named filaments, bass surge, divergence alpha) | ✅ | ✅ | ✅ | ✅ (no C read, A = display) | ✅ | ✅ (no spring/ripple added) | ✅ |
| mouse-julia-morph | ✅ | ✅ (orbit-trap glow, bass zoom) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (ripple pinning pre-existing) | ✅ |
| cross-stitch | ✅ | ✅ (half/full stitch, sheen, bass tension) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (no springs/ripples on a still-media effect) | ✅ |
| foil-impression | ✅ | ✅ (anisotropic brush, fold shimmer) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (ripple click-front pre-existing) | ✅ |
| interactive-voronoi-web | ✅ | ✅ (named neural web, bass burst) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (no new springs) | ✅ |
| mouse-polarized-light-field | ✅ | ✅ (chromatic dispersion, treble shimmer) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (ripple vortices pre-existing) | ✅ |
| poly-art | ✅ | ✅ (finished edges, flat-shading) + bug fix (bounds guard) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (no springs/ripples added) | ✅ |

No two files in this batch share a generic overlay — each idea is native to that file's own
mechanism (magnetism, fractal iteration, embroidery stitching, foil relief, Voronoi web,
polarization optics, facet tessellation). No spring/ripple was invented for "contract
completeness"; every ripple/click reference already existed in the file being touched.

**Verdict: 8/8 pass.**
