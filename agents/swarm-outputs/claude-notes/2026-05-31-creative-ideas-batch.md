# Creative Visual-Idea Batch — 16 Shaders
**Date**: 2026-05-31 | **Agent**: Claude Opus 4.8 | **Focus**: inject one *unique visual idea that wasn't already there* per shader (creative, not optimization)

All 16 pass `naga` validation. Disjoint from the day's three prior batches (Kimi 8 + Claude opt batch-1 7 + Claude opt batch-2 5). Method: read each shader, identify what visual idea it lacked, add one self-contained, physically- or aesthetically-motivated technique, validate.

| # | Shader | Category | Unique idea added (was NOT there) |
|---|--------|----------|-----------------------------------|
| 1 | bubble-lens | distortion | **Gravity-driven soap-film drainage** — film thins at top forming the Newton black-spot, color bands pool/swirl at bottom with turbulent flow |
| 2 | heat-haze | distortion | **Rising-convection columns + chromatic Schlieren** — hot air ascends in shimmering columns; wavelengths refract differently → prismatic mirage fringing |
| 3 | glass-brick-wall | distortion | **Per-brick lens caustics** — each squircle focuses the mouse-light into a swimming caustic that sweeps as the light moves, with chromatic focal tint |
| 4 | neon-edges | retro-glitch | **Electric current flowing along the tube** — brightness pulses race *along* each edge's tangent (treble accelerates the current) |
| 5 | halftone | retro-glitch | **Offset-press plate misregistration + paper fibre grain** — each CMYK plate samples at a drifting offset (riso/newsprint look); mouse tightens registration |
| 6 | pixel-rain | retro-glitch | **Multi-layer parallax depth** — 3 rain planes at different speeds/scales/brightness so rain falls through 3D space with depth-of-field dimming |
| 7 | circular-pixelate | image | **Hexagonal honeycomb packing** — replaced the square grid with an optimal hex lattice (fly's-eye / real dot screen) |
| 8 | frost-reveal | image | **Dendritic ice crystals w/ hexagonal 6-fold symmetry** — feathery ferns branch from nucleation points; frost creeps inward from cold screen edges |
| 9 | crumpled-paper | image | **Physical crease response** — worn-white fibre stress along fold peaks, anisotropic specular sheen catching creases, valley ambient occlusion |
| 10 | energy-shield | visual-fx | **Discrete impact shockwaves + Fresnel rim** — clicks detonate expanding bright rings that ignite hexes as the wavefront crosses; shield glows at the curved edge |
| 11 | magnetic-rgb | distortion | **Iron-filing field-line visualization** — filings align along the radial+swirl field (noise compressed perpendicular to field dir); classic physics-demo look |
| 12 | bubble-wrap | image | **Animated pop event** — pop-time stamped in state buffer drives an elastic collapse with damped jiggle, an expanding burst ring, and a wrinkled deflated film |
| 13 | flip-matrix | retro-glitch | **Split-flap display mechanics** — center seam between flaps, a specular glint sweeping each flap mid-rotation, beveled edge shadows for plastic-plaque depth |
| 14 | cosmic-web | generative | **Galaxy clusters at filament nodes + twinkling galaxy field** — warm clusters ignite where filaments intersect; the web is strung with per-galaxy-tinted twinkling points |
| 15 | interactive-voronoi-web | image | **Living neural web** — charge pulses race along each strand (random phase per cell) and synapse nodes fire at the animated cell centers |
| 16 | crt-magnet | retro-glitch | **Shadow-mask beam purity error + aperture grille** — the 3 electron beams deflect by different amounts → rainbow purity blotch against vertical R/G/B phosphor stripes (the signature CRT-magnet artifact) |

## Notes on technique selection
Each idea was chosen to be **physically or aesthetically grounded in the shader's own theme** rather than a generic post-process: a soap bubble gets real film drainage, a CRT magnet gets real beam purity error, a magnetic shader gets real iron filings. Several shaders already had the "obvious" idea (bubble-lens already had basic thin-film interference; halftone already had CMYK rotated screens; radial-blur already had anamorphic streaks + spectral dispersion), so the addition is a genuinely *new* layer, not a duplicate.

## Skipped (to avoid collision / already saturated)
- **black-hole** and **hex-lens**: both were *broken* (non-compiling) when first checked — black-hole had undefined `angle`/`time`, hex-lens had a duplicate `let r`. Both are marked "Updated/Upgraded 2026-05-31" (in-progress by other agents). They compiled clean by end of session (their owners fixed them). Avoided to prevent collision.
- **radial-blur**, **directional-blur-wipe**: already saturated with advanced ideas from the 2026-05-30/31 passes — no clear gap to fill.

## Validation
`naga public/shaders/<name>.wgsl` → "Validation successful" for all 16. No JSON definitions were touched (pure WGSL visual additions), so no `generate_shader_lists.js` run required.
