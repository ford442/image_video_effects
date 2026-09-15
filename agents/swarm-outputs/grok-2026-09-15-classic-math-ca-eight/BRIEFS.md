# Classic math / CA leftover eight — Idea Cards

Written **before** any WGSL edit, per `docs/SHADER_UPGRADE_BATCH.md` §2.

Family: remaining classic math / lattice leftovers after the 09-13/09-14
carding of Langton, Klein, Koch, phyllotaxis, Newton, mandelbox, and
magnetic-field-warp. Two native ideas each. Identities kept. No
spring+ripple+IQ stamp.

Skipped (already dated `Ideas:`): `gen-langton-ant`, `gen-klein-bottle-walk`,
`gen-koch-snowflake-storm`, `gen-phyllotaxis-galaxy-spiral`, `gen-newton-fractal`,
`gen-mandelbox-explorer`, `gen-magnetic-field-warp`.

Skipped (already idea-rich, no date bump): `gen-belousov-zhabotinsky`,
`gen-protocell-division`, `gen-hyperbolic-tree`, `gen-worley-cellular-noise`,
`gen-quasicrystal`, `gen-zeta-function-landscape`, `gen-von-karman-vortex`,
`gen-cellular-automata-tapestry`, `gen-aperiodic-monotile`.

Skipped globally: tropism-rich `mycelium-network`, physarum `extraBuffer[0..]`
agents, `crt-clear-zone`, liquid-small, blackbody Phase-C ten,
`gen-percolation-threshold` (already 09-14).

---

SHADER: gen-rgb-diffraction
IDENTITY: six-slit RGB grating with 6-fold kaleido starburst
KEEP VERBATIM: Evolution Speed / Fringe Frequency / Chromatic Spread / Brightness;
  slitIntensity sinc² envelope; SLITS=6; SYMMETRY=6; RGB λ = 1.0 / 0.82 / 0.68
ADD (2 native ideas):
  1. blaze-angle envelope — each slit is a blazed grating, so intensity follows
     max(dot(p̂, slit axis), 0)²; belongs on a diffraction grating, not a costume
  2. spectral Airy rings — circular-aperture Airy (sinc² of r·freq·λ) added per
     RGB channel so the starburst has wavelength-scaled rings, not just fringes
FORBID: springs; IQ palette takeover; replacing the grating with a kaleido tunnel
A PACKING: ACES display RGBA (HEAD wrote unmapped color and filtered C)

---

SHADER: gen-verlet-cloth-wind
IDENTITY: 64×64 height/velocity sheet hung from the top row, wind + gravity +
  mouse poke, silk shading on an upsampled mesh
KEEP VERBATIM: Wind Strength / Fabric Weight / Stiffness / Sheen; pinned y=0;
  4-neighbor laplacian; bilinear upsample from C; mouse disk force
ADD (2 native ideas):
  1. weft/warp tension streaks — |∂h/∂x| vs |∂h/∂y| tints the weave so stretch
     reads as threads, not a generic highlight
  2. fluttering hem — free edge (y near 63) gets extra high-frequency wind so
     the unpinned hem lashes; Verlet cloth, not a new solver
FORBID: extraBuffer springs (the sheet already is the mass); liquid rewrite
A PACKING: lattice [0..63]² = raw (height, vel, stretch, 1); all other texels
  ACES display RGBA (HEAD only wrote A on the lattice)

---

SHADER: gen-sierpinski-tetrahedron
IDENTITY: IFS midpoint tetrahedron with vertex / edge / shell orbit traps and
  jewel-tone faces
KEEP VERBATIM: Recursion Depth / Rotation Speed / Perspective / Chromatic Aberration;
  V[4] / E[6]; branchless argmin fold; jewelColor; C.r temporal on minTrap
ADD (2 native ideas):
  1. vertex lamps — the four tet vertices, rotated with the same yaw/pitch as
     the IFS point, add lamp glints (this solid has vertices)
  2. mid-edge beads — glow on the existing capsule edges near parameter 0.5, so
     the six tet edges read as jewelry not just distance traps
FORBID: extraBuffer[0..5] audio/mouse springs (engine FFT zone); new springs
A PACKING: raw (minTrap, trapIdx, density, alpha) — C.r is mixed as minTrap

---

SHADER: gen-3d-sierpinski-chaos
IDENTITY: chaos-game point cloud of a 3D Sierpinski tetrahedron
KEEP VERBATIM: Point Density / Rotation Speed / Point Size / Color Shift;
  pickVertex; warmup discard; saturation early-exit; held-mouse orbit
ADD (2 native ideas):
  1. attractor-biased chaos — held mouse weights the next midpoint toward the
     tet vertex nearest the cursor (chaos game with a biased die)
  2. iteration-age hue — palette walks with i/numPoints so IFS depth shows as
     a second color axis on top of vertex-id hue
FORBID: extraBuffer[5..12] FFT reads; extraBuffer[133] bass env (CPU upload zeros it)
A PACKING: ACES display RGBA (HEAD stored unmapped temporal RGB)

---

SHADER: gen-chromatic-zonohedron
IDENTITY: 2D projection of a rhombic zonohedron — three-axis rhomb tiling,
  spectral facets, neon edges
KEEP VERBATIM: Facet Scale / Spin Speed / Edge Width / Color Cycle; zonoFacet /
  zonoSDF on axes (1,0), (½,√3/2), (−½,√3/2); mouse pan
ADD (2 native ideas):
  1. generator-axis dichroism — hue from which of the three rhomb families won
     (f0/f1/f2), so each generator keeps a stable spectral identity
  2. 3-space vertex stars — where all three facet distances nearly match, the
     projected zonohedron vertices flare (geometry, not sparkles)
FORBID: springs; IQ overlay; packing display into A while C is read as color
A PACKING: ACES display RGBA (HEAD stored (sdf, hue, α, fill) but mixed prev.rgb)

---

SHADER: gen-quasicrystal-iridescence
IDENTITY: n-fold quasicrystal field driving thin-film thickness / soap-film color
KEEP VERBATIM: Symmetry / Pattern Density / Color Cycle / Projection Angle;
  quasicrystal() sum of cosines; thinFilmColor 380–700 nm; dual-use of sliders
  x/y as film thickness / IOR (do not steal)
ADD (2 native ideas):
  1. Bragg peak ridges — extra constructive flare at qc zero-crossings (the
     matching-rule bright ridges of a quasicrystal, not a generic edge glow)
  2. phason shift — mouse offsets the wave-vector phases (phasons are native
     to quasicrystals; thickness-poke on hold stays)
FORBID: springs; rewriting as a different tiling; stealing slider roles
A PACKING: ACES display RGBA (HEAD stored iridescent HDR in A, unused C)

---

SHADER: gen-turing-morphogenesis
IDENTITY: closed-form activator-inhibitor spots / stripes / labyrinth by feed–kill
KEEP VERBATIM: Feed Rate / Evolution Speed / Pattern Scale / Color Shift;
  activatorInhibitor noise pair; fk → spots/stripes/labyrinth; held-mouse deposit
ADD (2 native ideas):
  1. morphogen ridges — highlight activator>inhibitor fronts as Turing
     boundaries (the chemistry, not an outline shader)
  2. pattern-type seams — glow at the fk = 0.01 / 0.02 thresholds where spots
     become stripes become labyrinth
FORBID: replacing the closed-form field with a Gray-Scott sim rewrite; springs
A PACKING: ACES display RGBA (HEAD already persists display for the trail)

---

SHADER: gen-buddhabrot-aura
IDENTITY: escaping-orbit density (Buddhabrot-style) with a trap-colored aura
KEEP VERBATIM: Orbit Threshold / Density Scale / Mouse Zoom / Aura Intensity;
  4-sample φ offsets; |z|²>4 escape; orbitTrapColor
ADD (2 native ideas):
  1. trichrome dwell — R/G/B from early / mid / late escape iteration (classic
     Buddhabrot channel split, not a costume palette)
  2. anti-Buddhabrot ghost — orbits that never escape add a faint complementary
     interior glow (the native dual of the escaping set)
FORBID: springs; turning it into a Mandelbrot-set portrait
A PACKING: ACES display RGBA (HEAD filtered C — exact load)

---

## Floor (not the upgrade)

Canonical 13 bindings, 16×16, exact C loads, A packing as documented, saved
`params` / `updatedParams` byte-exact. No new extraBuffer springs. Delete
illegal extraBuffer[0..5] writes (tetrahedron) and extraBuffer FFT / [133]
envelope lies (chaos game). Real-GPU visual QA is external.
