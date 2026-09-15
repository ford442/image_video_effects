# Classic field / plasma / crystal leftover six — Idea Cards (2026-09-15)

Contract: `docs/SHADER_UPGRADE_BATCH.md`. Two native ideas each. Identities kept.
No new extraBuffer springs. Flash-class size: 6.

#1274 already took the 09-13 classic math/CA leftovers (rgb-diffraction /
verlet / sierpinski / CA tapestry / turing / buddhabrot). This cohort is the
next thin field / plasma / crystal family that still lacks `Ideas:`.

Skipped: belousov / protocell / hyperbolic-tree (idea-rich, no Ideas line),
stardust-nebula and tessellation (already multi-technique June floors),
chronos-crystal-labyrinth (C used as fake audio LUT), extraBuffer[0..] files,
tropism mycelium, physarum agents, crt-clear-zone, liquid-small, blackbody.

---

SHADER: gen-strange-field-flow
IDENTITY: per-pixel de Jong / Clifford blend, 8-step orbit density, acid-neon
whorls with rotating display-history trails
KEEP VERBATIM: Drift Speed / Chaos Blend / Orbit Density / Trail Persistence;
deJongStep + cliffordStep mix; 8 iters; hist zoom-in + rotate; RGB history offsets
ADD (2 native ideas):
  1. Lyapunov stretch tint — color by mean log|Δstep| of THIS map so expanding
     vs contracting regions of the attractor read differently
  2. Pickover stalks on the attractor orbit — min(|x|,|y|) along the iterated
     point (this map's axes, not a Mandelbrot rewrite)
FORBID on this file: springs; replacing de Jong with Lorenz; IQ candy as the look
A PACKING: ACES display RGBA in A (C is previous display; HEAD filtered-sampled C)
FLOOR (not an idea): ACES; exact textureLoad C; audio clamp; reconstruct vec3
instead of swizzle assignment

---

SHADER: gen-solar-wind-ribbons
IDENTITY: parametric magnetised-plasma ribbons sampled along s, Gaussian width,
stellar-wind streak background, held-mouse curtain steer
KEEP VERBATIM: Ribbon Count / Twist / Speed / Glow; ribbonCentre; 64 samples;
IQ-cosine ribbon hues; fbm brightness; horizontal streaks
ADD (2 native ideas):
  1. Parker spiral lag — azimuth delay grows with |s| so the IMF drapes like
     solar wind, fused into ribbonCentre (not a new solver)
  2. Kelvin–Helmholtz scallops — perpendicular billows along the existing
     centre-line so the plasma sheet edge undulates
FORBID on this file: springs; ferrofluid spikes; IQ takeover of the ribbon identity
A PACKING: ACES display RGBA in A
FLOOR (not an idea): single ACES (HEAD ran aces then acesToneMap); audio clamp

---

SHADER: gen-prismatic-ion-cascade
IDENTITY: mouse-anchored angular ion streams with chromatic phase split,
fbm warp, radial core falloff, trail burn
KEEP VERBATIM: Stream Density / Cascade Speed / Spectral Spread / Ion Thickness;
theta*density bands; RGB phase split; mouse as cascade origin; video haze mix
ADD (2 native ideas):
  1. Cyclotron gyration — a radial-dependent theta wobble (B-field gyro) on
     the existing streams, not a new particle sim
  2. Recombination glow — a radial shell where streams fade into a cool
     charge-exchange halo (ions, not a vignette)
FORBID on this file: springs; floor(time) sparkle strobe; replacing streams with
a liquid solver
A PACKING: ACES display RGBA in A (C is previous display; HEAD filtered-sampled C)
FLOOR (not an idea): exact textureLoad C; continuous sparkle (no floor(time) hash)

---

SHADER: gen-crystal-lattice-growth
IDENTITY: golden-angle dendrites in radial symmetry from a nucleation seed,
prismatic hue, click crystallisation fronts
KEEP VERBATIM: Symmetry / Growth Rate / Hue / Thickness; crystalBranch loop;
golden 137.5° child; held-mouse seed pull; click rings; facet angular ripple;
raw HDR A / ACES write
ADD (2 native ideas):
  1. Twin-boundary mirror — odd arms query a reflected copy of p across a
     slow-rotating diameter (crystal twinning, not a new tree)
  2. Hopper faces — a parallel inner edge on each existing segment so branches
     read as skeletal hopper crystals
FORBID on this file: springs; DLA particle rewrite; IQ candy takeover
A PACKING: raw HDR display RGBA in A; ACES on writeTexture only (HEAD already)

---

SHADER: gen-topological-acoustic-knots
IDENTITY: liquid-crystal director field from ±1/2 defects, mouse-pinned +1/2
core, iridescent stripes along the director
KEEP VERBATIM: Defect Density / Defect Speed / Iridescence / Flow Strength;
hashed orbiting defects; charge ±1/2; mouse pin; iridescent(angle); stripe along dir
ADD (2 native ideas):
  1. Pair annihilation — opposite-charge neighbors fade their winding when
     close (the annihilation the description already claims)
  2. Schlieren brushes — dark |∇θ| brushes between defects along the director
     (LC texture, not a generic glow)
FORBID on this file: new extraBuffer springs; replacing defects with a fluid solver
A PACKING: ACES display RGBA in A (C is previous display; HEAD filtered-sampled C)
FLOOR (not an idea): exact textureLoad C; audio clamp

---

SHADER: gen-quasicrystal-iridescence
IDENTITY: n-fold sum of plane waves (5–13) driving thin-film thickness, metallic
gold/silver/bronze base, held-mouse thickness bump
KEEP VERBATIM: Symmetry / Pattern Density / Color Cycle / Projection Angle roles
(JSON); quasicrystal() cosine sum; thinFilmColor spectral loop; dual HEAD mapping
of the same sliders onto film thickness/IOR/intensity/turbulence
ADD (2 native ideas):
  1. Phason strain — each wavevector is offset along its perpendicular so the
     aperiodic tiling rearranges without changing n
  2. Ammann lattice lines — faint stripes perpendicular to each k, gated by
     the same n-fold sum (quasicrystal scaffolding, not grout from tessellation)
FORBID on this file: springs; replacing the n-fold sum with a Penrose kite/dart
mesh; IQ overlay as the whole look
A PACKING: ACES display RGBA in A (HEAD stored iridescent+thickness while write
stored a different tonemap — lie. Match writeTexture.)
FLOOR (not an idea): ACES; plasmaBuffer[0].xyz; semantic alpha from edge+fresnel
