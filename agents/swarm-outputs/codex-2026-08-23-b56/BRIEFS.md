# Batch 56 briefs — 2026-08-23 (tracker #475–482) — INTERACTIVE COMPLEXITY

Batch 56 upgrades eight single-pass interactive effects with distinct geometry,
continuous motion, psychedelic color, held-pointer response, and click events
capped by the live ripple count and 50.

| # | Shader | Upgrade focus |
|---|--------|---------------|
| 475 | `cmyk-halftone-interactive` | Rosette/moiré print geometry, registration drift/shear, ink blooms |
| 476 | `cyber-slit-scan` | Traveling scan heads, diagonal tears, held slit bends, click injections |
| 477 | `interactive-ripple` | Analytic Huygens interference, crest packets, pressure, thin-film color |
| 478 | `phosphor-magnifier` | Raster beam, degauss/click shells, pressure, display afterimages |
| 479 | `vertical-slice-wave` | Layered strips, seam runners, held twist, click fronts, rainbow interference |
| 480 | `chromatic-focus-interactive` | Bounded blur, zone plates/caustics, focus squeeze, iris shells |
| 481 | `quantum-prism` | Honeycomb bevels, spectral bands, cell deformation, facet depth |
| 482 | `matrix-curtain` | Glyph strokes, parallax rain, curtain vortices, alternate phosphors |

## Shared contract

- Preserve each source `params` object and ordering; add aligned
  `updatedParams` without changing preset IDs, defaults, or ranges.
- Preserve all 13 canonical bindings, input depth ownership, B→C/A→C engine
  ordering, and `plasmaBuffer[0].xyz` audio.
- Keep B unused and introduce no `extraBuffer` access.
- Use 16x16x1 workgroups and cap event loops with `min(u.config.y, 50)`.
- Preserve A ownership except the documented Phosphor Magnifier correction.
- Structural validation is local; visual acceptance requires a real GPU.

## Dual-lineage merge

A second Batch 56 (local) upgraded a different eight-shader set with the same
tracker range. Unique shaders from both lineages are retained; the four
overlaps were hand-merged. See `COORDINATOR_REVIEW.md` and `SHADER_NOTES.md`.
