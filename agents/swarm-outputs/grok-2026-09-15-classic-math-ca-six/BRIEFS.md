# Classic math / CA leftover six — Idea Cards (2026-09-15)

Contract: `docs/SHADER_UPGRADE_BATCH.md`. Two native ideas each. Identities kept.
No new extraBuffer springs. Flash-class size: 6.

Leftover source: `agents/swarm-outputs/grok-2026-09-13-simpler-gen-leftover-ten/BRIEFS.md`
classic math/CA list, minus IDs already stamped 09-14 (langton / klein /
koch / phyllotaxis / newton / mandelbox / magnetic-field-warp).

Skipped: `gen-percolation-threshold` (already carded; extraBuffer[0..] history),
`gen-belousov-zhabotinsky` / `gen-protocell-division` / `gen-hyperbolic-tree`
(idea-rich without `Ideas:` — metadata-pass candidates), tropism-rich
`mycelium-network`, physarum `extraBuffer[0..]` agents, `crt-clear-zone`,
liquid-small, blackbody Phase-C.

---

SHADER: gen-rgb-diffraction
IDENTITY: six virtual slits on rotating axes, sinc² envelopes, separate R/G/B
path lengths, 6-fold kaleidoscopic fold — a spectral grating starburst
KEEP VERBATIM: Evolution Speed / Fringe Frequency / Chromatic Spread / Brightness
roles; SLITS=6, SYMMETRY=6; slitIntensity wave×sinc²; hsv shimmer; bass/mids/treble
chromatic offsets
ADD (2 native ideas):
  1. Blazed grating — tilt the existing sinc envelope along the slit axis so the
     +1 diffraction order is brighter than −1 (a real grating, not a palette)
  2. Spectral order ghosts — extra fringe families at m=±1 using the same slits
     at 2× spatial frequency (grating orders, not a new motif)
FORBID on this file: springs; IQ candy takeover; replacing slits with an SDF scene
A PACKING: ACES display RGBA in A (C is previous display; HEAD filtered-sampled C)
FLOOR (not an idea): ACES; exact textureLoad C; audio clamp; pointer tilts the
grating; click ripples kick phase (optical path, no spring)

---

SHADER: gen-verlet-cloth-wind
IDENTITY: 64×64 height/velocity cloth pinned at the top row, Laplacian springs,
noise wind, silk shading, held-mouse poke
KEEP VERBATIM: Wind Strength / Fabric Weight / Stiffness / Sheen; gridRes=64;
A.r height + A.g velocity on the lattice; pinned y=0; fabric+spec+SSS lighting
ADD (2 native ideas):
  1. Warp/weft thread ridges — grooves along the existing lattice UV so the
     cloth reads as woven fabric, not a smooth membrane
  2. Fold creases from |Laplacian| — the solver already computes the spring
     term; store it and shade valleys where the sheet kinks (cloth, not a new sim)
FORBID on this file: Gray-Scott; new extraBuffer springs; replacing Verlet with
display-history sparkles; writing display RGBA into the 64×64 lattice
A PACKING: lattice texels [0..63]² = raw (height, velocity, laplacian, 0);
off-lattice texels = ACES display RGBA. Display samples C only inside the lattice.
FLOOR (not an idea): write A on every texel (HEAD only wrote the 64×64 corner);
click ripples as wind gusts on the sheet (this is a wind cloth); mids/treble live

---

SHADER: gen-sierpinski-tetrahedron
IDENTITY: IFS Sierpinski tetrahedron (nearest of 4 vertices, midpoint fold)
projected with vertex/edge/shell orbit traps and jewel-tone metallic shading
KEEP VERBATIM: Recursion Depth / Rotation Speed / Perspective / Chromatic Aberration;
V[4] + E[6] capsules; branchless argmin; domain-warp + curl + worley accents;
jewelColor; Schlick; ACES on display
ADD (2 native ideas):
  1. Face-centroid orbit trap — distance to the four triangular face centroids
     (the tet already owns 4 faces; this is the missing trap, not a new fractal)
  2. Generation-index jewel — color by the IFS iteration of closest approach so
     nested generations read as separate gem layers
FORBID on this file: new springs; extraBuffer[0..132] (HEAD wrote [0..5] into
engine-reserved + FFT); replacing the tet IFS with a raymarched mesh
A PACKING: raw telemetry in A (minTrap, trapIdx, density, alpha) — C.r is mixed
as previous trap distance. ACES on writeTexture only.
FLOOR (not an idea): delete extraBuffer[0..5] writes; read plasmaBuffer[0] live;
clickPulse from zoom_config.w; mouse UV already 0–1

---

SHADER: gen-cellular-automata-tapestry
IDENTITY: Gray-Scott A/B on the video feed — convolution Laplacian, feed/kill
sliders, mouse nutrient, chemical overlay as a living tapestry
KEEP VERBATIM: Diffusion A / Diffusion B / Feed Rate / Kill Rate; 3×3 weights
(center −1, adjacent 0.2, diagonal 0.05); reaction A·B²; luminance-modulated
feed/kill; raw A/B stored in dataTextureA.xy
ADD (2 native ideas):
  1. Warp/weft from the two chemicals — A as vertical warp, B as horizontal weft,
     so the tapestry in the name is woven from the solver, not stamped noise
  2. Pearson glaze — spots vs worms vs maze tint from (kill−feed), which this
     file already exposes as sliders (Pearson classification, not a new RD)
FORBID on this file: rewriting as Conway Life; plasmaBuffer[idx] LUT (illegal);
springs; mixing chemical A.rgb into the photo as if it were display history
A PACKING: raw (nextA, nextB, weave, 1) — C is read as .xy chemicals. Do not ACES A.
FLOOR (not an idea): native A/B colormap (drop plasmaBuffer[plasmaIdx]); exact
textureLoad C; dt from bass not config.y (ripple count); held mouse strengthens
nutrient; click rings inoculate B; ACES on writeTexture

---

SHADER: gen-turing-morphogenesis
IDENTITY: closed-form activator–inhibitor (two-scale value-noise) that morphs
between spots, stripes, and labyrinth from (kill−feed), organic coat palette
KEEP VERBATIM: Feed Rate / Evolution Speed / Pattern Scale / Color Shift;
activatorInhibitor; spots/stripes/labyrinth via fk thresholds; mouse deposit;
organicColor 5-stop mix; ACES display history in A
ADD (2 native ideas):
  1. Inhibitor halo — a dark ring from the inhibitor field around existing spots
     (Turing’s inhibitor, not a vignette)
  2. Chemical-front ridges — thin bright crests where activator ≈ scaled inhibitor
     (the morphogenesis front this file already computes as `diff`)
FORBID on this file: replacing the closed-form field with a Gray-Scott solver
(that is CA tapestry); springs; IQ overlay
A PACKING: ACES display RGBA in A (C is previous display; HEAD already packed this)
FLOOR (not an idea): bounds guard; mids/treble on halo/front; exact C already

---

SHADER: gen-buddhabrot-aura
IDENTITY: per-pixel Mandelbrot orbits whose escaping trajectories tint a nebula
aura (Buddhabrot-style density + orbit-trap bloom)
KEEP VERBATIM: Orbit Threshold / Density Scale / Mouse Zoom / Aura Intensity;
z ← z²+c loop; 4-sample φ offsets; orbitTrapColor; escape-time density; ACES
ADD (2 native ideas):
  1. Nebulabrot channels — split the existing escape density into early/mid/late
     iteration bands (classic R/G/B Buddhabrot, not a new fractal)
  2. Anti-Buddhabrot interior — orbits that never escape add a dim interior dust
     (the complementary Buddhabrot, fused into this loop)
FORBID on this file: springs; rewriting as a standard Mandelbrot set portrait;
cloning Inverse Mandelbrot Pickover stalks
A PACKING: ACES display RGBA in A (C is previous display; HEAD filtered-sampled C)
FLOOR (not an idea): exact textureLoad C; audio clamp; click ripples kick c
