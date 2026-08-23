# Batch 56 briefs — 2026-08-23 (tracker #475–482) — GEOMETRY + FAST MOTION + PSYCHEDELIC COLOR

Batch 56 upgrades eight clean single-pass effects from the ~128–131 line band
with extra geometry, two continuous-motion structures each, held-pointer
deformation, click fronts capped by live ripple count and 50, and psychedelic
color. High-complexity v2 shaders in the same size band (infinite-zoom-lens,
phosphor-magnifier, interactive-ripple, pixel-repel, stipple-render,
liquid-warp-interactive) were skipped. Print/wind/slit leftovers
(`luminance-wind`, `cyber-slit-scan`) remain skipped.

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

## Shared contract

- Preserve source `params` byte-for-byte and add aligned `updatedParams`.
- Preserve canonical 13 bindings, 16x16x1 workgroups, depth ownership, and
  `plasmaBuffer[0].xyz` audio.
- Keep B unused and introduce no `extraBuffer` access.
- Preserve established A packing: CMYK coverage for halftone; line masks
  for iso-lines; display RGBA elsewhere.
- No renderer, graph, toolchain, dependency, or public TypeScript API changes.
- Structural validation is local; visual acceptance requires a real GPU.
