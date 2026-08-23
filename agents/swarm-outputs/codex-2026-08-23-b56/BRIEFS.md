# Batch 56 briefs — 2026-08-23 (tracker #475–482) — MERGED LINEAGES

Three concurrent Batch 56 upgrades claimed the same tracker range. This file
summarizes the union after merging on the cursor branch.

## Cursor cohort (geometry + fast motion + psychedelic color)

| # | Shader | Upgrade focus |
|---|--------|---------------|
| 475 | `ascii-shockwave` | Glyph cells, shock packets, oil-slick phosphor, iris clicks |
| 476 | `cmyk-halftone-interactive` | Rosette rings, ink conveyors, rainbow registration, click splats |
| 477 | `heat-haze-gpt52` | 16x16, thermal filaments, rise packets, held source, click rings |
| 478 | `quantum-prism` | Live sliders, hex grout/runners, oil-slick prism, click fronts |
| 479 | `sphere-projection` | Meridians/parallels, held zoom, rainbow lighting, click shells |
| 480 | `fractal-kaleidoscope` | Canonical bindings, live sliders, seams/conveyors, held pivot |
| 481 | `rgb-iso-lines` | 16x16, iso-runners, rainbow hypsometry; line-mask A |
| 482 | `chromatic-focus-interactive` | Aperture blades, radial packets, held pinch, click rings |

## Also retained from prior main merge

cyber-slit-scan, hyb-spectral-fbm-displace, infinite-zoom-lens,
phosphor-magnifier, warp_drive, liquid-warp-interactive, interactive-ripple,
vertical-slice-wave, matrix-curtain (plus hand-merged overlaps above).

## Shared contract

- Preserve source `params` and add aligned indexed `updatedParams`.
- Preserve canonical 13 bindings, 16x16x1 workgroups, depth ownership, and
  `plasmaBuffer[0].xyz` audio.
- Keep B unused and introduce no `extraBuffer` access.
- Preserve established A packing: CMYK coverage for halftone; line masks for
  iso-lines; phosphor display-RGBA afterimage; display RGBA elsewhere unless
  diagnostic A was explicitly preserved (infinite-zoom-lens, warp_drive).
- Structural validation is local; visual acceptance requires a real GPU.
