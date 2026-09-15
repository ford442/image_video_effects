# Classic geometry leftover six — Idea Cards (2026-09-15)

Contract: `docs/SHADER_UPGRADE_BATCH.md`. Two native ideas each. Identities kept.
No new extraBuffer springs. Flash-class size: 6.

#1274 took the math/CA leftover six. #1276 took the field/plasma/crystal six.
This cohort is the next thin **geometry / tiling / landscape** family still
missing `Ideas:`.

Skipped: `gen-quasicrystal` (already n-fold + Voronoi + Fresnel + neon),
`gen-hyperbolic-tree` / `gen-belousov-zhabotinsky` / `gen-protocell-division`
(idea-rich, no Ideas line — metadata-pass), `gen-crystal-caverns` (June gem
caustics), extraBuffer[0..] files (`gen-worley-cellular-noise`), tropism
mycelium, physarum agents, crt-clear-zone, liquid-small, blackbody.

---

SHADER: gen-3d-sierpinski-chaos
IDENTITY: chaos-game point cloud of a 3D Sierpinski tetrahedron, perspective-projected
KEEP VERBATIM: Point Density / Rotation Speed / Point Size / Color Shift; 4 tet
vertices; warmup + pickVertex; extraBuffer[133] bassSmooth; mouse orbit vs auto-spin
ADD (2 native ideas):
  1. Repeat-vertex corner flares — consecutive same-index picks light the tet
     corners (this IFS, not a new attractor)
  2. Opposite-face chroma — hue from the farthest of the 4 vertices so the cloud
     reads as four tet faces instead of a single rainbow dust
FORBID on this file: new springs; replacing the chaos game with a raymarched SDF tet
A PACKING: ACES display RGBA (C is previous display; HEAD stored unmapped RGB)

---

SHADER: gen-aperiodic-monotile
IDENTITY: hex-metric “hat” tiling with chromatic edges and a budgeted relief sculpture
KEEP VERBATIM: Tile Scale / Rotation Speed / Edge Width / Saturation; hatTileDistance;
reliefDE raymarch; ACES mix with C
ADD (2 native ideas):
  1. Reflected hats — flip local hex axes on odd cells (hat tiling uses reflected copies)
  2. Chevron brim — a sawtooth notch along hex_q so cells read as hat polykites, not hexes
FORBID on this file: extra SDF overlay; springs; replacing the 2D tiling with the sculpture
A PACKING: ACES display RGBA

---

SHADER: gen-chromatic-zonohedron
IDENTITY: 2D projection of a rhombic zonohedron — 3-axis rhomb tiling, spectral facets
KEEP VERBATIM: Facet Scale / Spin Speed / Edge Width / Color Cycle; zonoFacet; mouse pan
ADD (2 native ideas):
  1. Fourth generator — a golden-ratio axis so cells become 4-vector zono rhombs
  2. Generator-pair face IDs — hue from which facet wins, not floor(p.x)
FORBID on this file: springs; IQ candy as the look; a different polyhedron
A PACKING: ACES display RGBA (HEAD stored raw (cell, hue) while C is read as color)

---

SHADER: gen-zeta-function-landscape
IDENTITY: Dirichlet-eta continuation of ζ(s) as height in the critical strip
KEEP VERBATIM: Sigma Offset / T Range / Height Scale / Term Precision; eta continuation;
click UV refraction; chromatic zeros
ADD (2 native ideas):
  1. Known-zero rails — bright ticks at the first Riemann zero ordinates, strongest
     when σ≈1/2 (this landscape, not a new function)
  2. |ζ|=1 iso-contours — log-magnitude rings (Hardy-style oscillation, not a palette)
FORBID on this file: springs; replacing eta with fbm height; stealing Sigma into a new axis
A PACKING: ACES display RGBA; exact textureLoad C (HEAD used a filtering sample)

---

SHADER: gen-prismatic-mobius-helix
IDENTITY: stacked Möbius-strip SDFs twisted into a helix with thin-film iridescence
KEEP VERBATIM: Coil Count / Ribbon Width / Helix Radius / Iridescence; sdMobius;
mouse yaw/pitch orbit
ADD (2 native ideas):
  1. Half-twist seam — highlight the identification where the strip flips (u = t/2)
  2. Centerline core — glow the (r−R, y) spine before thickness so each ribbon has a wire
FORBID on this file: springs; replacing Möbius with a torus or spring cursor
A PACKING: ACES display RGBA (HEAD stored raw (d, hue) while C is read as color)

---

SHADER: gen-voronoi-crystal
IDENTITY: animated Voronoi cells as growing crystals with facet edges and frost
KEEP VERBATIM: Growth Speed / Crystal Count / Irregularity / Glow Intensity;
f1/f2 Voronoi; extraBuffer[133..138] pointer spring; growth rings; click cracks
ADD (2 native ideas):
  1. Triple-junction vertices — track f3; spark grain corners where three crystals meet
  2. Facet flats — mix L∞ distance into the existing seed metric so interiors facet
FORBID on this file: new springs (keep the existing pointer spring); Gray-Scott
A PACKING: ACES display RGBA
