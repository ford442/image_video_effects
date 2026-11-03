# Coordinator review — cursor/batch-36 (2026-11-02)

Cards were written in `BRIEFS.md` before the WGSL edits. Each numbered idea has a `// ── Idea n:` comment in that shader. Earlier ideas stay. Saved params were not renamed or re-defaulted.

| Shader | Verdict | Why |
|---|---|---|
| halftone | pass | Midtone gain fattens the existing density before the ellipse. K is cut slightly larger and CMY is choked under that same dot. Highlight skip, overprint, misregistration, and the mono/CMYK split stay. |
| halftone-reveal | pass | Screen angles pick up a few degrees from the existing loupe. Each plate's AM edge is nibbled by that plate's cell hash, and only inside the reveal. Gain and highlight knockout stay. |
| engraving-stipple | pass | Pits land where the gradient is quiet. The wipe highlight sits on the uninked plate along the hatch's light direction. A stays telemetry and is not tone-mapped. |
| engraving-stipple-blue-noise | pass | A bright ring sits just outside the engraved dot and scales with Burr Texture. The shadow steps away from the pointer in cell space. The jitter, the threshold, and the two sliders' double duty stay. A is new display RGBA because C is unread. |
| spec-blue-noise-stipple | pass | The secondary center steps off the primary inside the cell. Overlap darkens toward stacked ink. Packing, neighbor skip, and the golden tertiary stay. |
| stipple-render | pass | The Sobel the hatch already uses shifts the dot toward darker luma. Wet memory from C draws a dark rim and a pale core. The Lloyd offset, the bleed, and the hatch stay. |
| cyber-halftone-scanner | pass | Odd rows lag half a dot on the existing 15/75/0/45 screens. A missed line, hashed per scanline, drops the thresholds with an exponential tail. Scan bursts, the glitch skip, and the hard-dot stay. Both §12.2B rows are only on this file. |
| polka-dot-reveal | pass | Chained gaps punch alpha through the trail. A small pip sits inside the dot, toward the pointer. A is still the bass envelope, the smoothed mouse, and the trail. ACES is on the display write only. |
| polka-wave | pass | The cell metric stretches along the wave the grid already rides. The product of the four plate masks opens a paper eye. Angles, gain, invert, and the spectral rosette stay. |
| rotoscope-ink | pass | A wider dry-brush sits under the existing tapered core. Flats resample one pixel away on a 12-per-second hold; the line uses the stable sample. A stays telemetry and is not tone-mapped. |
| film-cross-process | pass | The existing per-channel hash is scaled by midtone density. Shadow mix times the existing skew pulls the shadows teal; the highlight crossover is untouched. The enlarger spring stays. Density-weighted grain is only on this file. |
| graphic-novel | pass | Hatch thickens on the shoulder of the spot black, then the solid takes over. A thin ink rectangle sits inset from the frame and skips the spotted blacks. Contour weight, screens, and the C colour mix stay. |

§9 checklist: cards exist and predate the diff; each idea is pointable; keep-verbatim holds; the diff is the print or ink term, not a header/ACES/spring stamp (`engraving-stipple-blue-noise` is the file that gained ACES, under two ideas; `polka-dot-reveal` gained ACES on the display write only); no formula is shared; packing matches how C is read; the only spring is the one `film-cross-process` already had; Naga, extraBuffer, and dead sliders passed on these files.

Real-GPU visual QA is external. This review does not claim the ideas look right on a display.
