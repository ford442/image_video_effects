# Batch 58 briefs — 2026-08-23 (tracker #491–498) — SMALLEST MISSING-PARAM CONTRACTS

## Reproducible selection rule

Select the eight smallest WGSL files by byte size among cataloged compute
shaders whose definitions have exactly four saved `params` and no
`updatedParams`. Exclude declared multipass effects and IDs containing `pass`.
No category or prior-batch sequence preference is applied.

| Rank / # | Bytes | Shader | Upgrade focus |
|---|---:|---|---|
| 1 / 491 | 4,995 | `triangle-mosaic` | Truthful display history, seam runners, held twist, spectral fronts |
| 2 / 492 | 5,114 | `polka-wave` | CMYK rosettes, held wave pressure, click overprint fronts |
| 3 / 493 | 5,129 | `sphere-projection` | Latitude bands, moving light, held zoom, spectral click fronts |
| 4 / 494 | 5,138 | `foil-impression` | Brushed foil motion, held emboss pressure, iridescent click rings |
| 5 / 495 | 5,144 | `bio-touch` | Cellular membranes, held curl, growth fronts, organism palette |
| 6 / 496 | 5,198 | `hypnotic-spiral` | Correct pointer space, capped click waves, held reversal |
| 7 / 497 | 5,242 | `spirograph-reveal` | Gear/cusp motion, held deformation, spectral reveal fronts |
| 8 / 498 | 5,300 | `voronoi-chaos` | Ridge runners, held repulsion, click fronts, bounded sampling |

## Shared contract

- Preserve source `params` exactly and add aligned `updatedParams`.
- Preserve canonical 13 bindings, 16x16x1 workgroups, input depth ownership,
  B→C/A→C engine order, and `plasmaBuffer[0].xyz` audio.
- Keep B unused and introduce no `extraBuffer` access.
- Preserve A ownership. Triangle Mosaic deliberately begins writing its display
  RGBA to A because it already consumes C as display history; this makes the
  existing temporal behavior truthful. Sphere, Foil, and Voronoi keep A unused.
- No renderer, graph, TypeScript API, dependency, or bind-group changes.
