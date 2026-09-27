# Grok batch — simpler / mid crystal-math ten — Idea Cards

Written **before** WGSL. Six files already had dated cards; those mechanisms stay. Two new ideas each. Crystal caverns, celestial forge, cosmic web, and DLA copper had no `Ideas:` line. Do not copy twin facets / weld seams from `gen-radiant-quantum-crystalline-forge`. Do not copy stator ghosts or cusp flashes from this morning's audio spirograph. No new springs.

---

SHADER: gen-crystal-lattice-growth
IDENTITY: golden-angle mineral dendrite grown from a nucleation seed
KEEP VERBATIM: Symmetry / Growth Rate / Hue / Thickness; crystalBranch; twin-boundary mirror on odd arms; hopper inner-edge; click fronts
ADD:
  1. Growth striae — faint lines running along each segment, inside the arm, not a second hopper edge
  2. Nucleation core — a small faceted seed at the origin the arms leave
FORBID: a new spring; replacing the dendrite with a raymarched cavern
A PACKING: raw HDR display RGBA in A; ACES on writeTexture

---

SHADER: gen-chromatic-zonohedron
IDENTITY: 2D projection of a 4-generator rhombic zonohedron
KEEP VERBATIM: Facet Scale / Spin Speed / Edge Width / Color Cycle; zonoFacet; fourth golden-ratio generator; generator-axis dichroism; generator-pair face IDs; 3-space vertex stars
ADD:
  1. Zone belts — edges parallel to one generator share that generator's hue
  2. Minkowski inset — a half-width rhomb line inside the winning cell. No fifth generator
FORBID: springs; a different polyhedron
A PACKING: ACES display RGBA

---

SHADER: gen-cyber-terminal
IDENTITY: curved-CRT green digital rain over the source, with phosphor trails from C
KEEP VERBATIM: curvature, column speeds/drops, 3x5 segment glyphs, white-hot drop leader, scanlines, input mix 0.8, HDR history in A, four params
ADD:
  1. Column gaps — a seeded blank in each drop so the trail is glyph blocks. Glyph Sharpness still sets stroke width
  2. Bottom restart flash — the cell where a column wraps gets one cold-green frame and a new glyph seed
FORBID: mouse lens, a new colour palette (phosphor green stays), new springs
A PACKING: raw HDR display RGBA history (C read back as the same)

---

SHADER: gen-cyclic-automaton (`gen_cyclic_automaton.wgsl`)
IDENTITY: Greenberg–Hastings excitable media (rest / fire / refractory)
KEEP VERBATIM: States / Spontaneity / Bloom / Cooldown; cardinal ignition; chirality; just-fired halo; leading-edge tracer; existing pointer spring; A = (state, fire, refract, bloom)
ADD:
  1. Pacemaker vs wave — a firing cell with no firing neighbor tints apart from a cell ignited by a cardinal neighbor
  2. Cooldown ticks — later refractory states draw discrete bands. The halo stays only nextState == 2
FORBID: Conway overlay; new extraBuffer slots
A PACKING: raw GH state

---

SHADER: gen-cycloid-bloom
IDENTITY: nested hypotrochoid floral mandala
KEEP VERBATIM: spin / petals / glow / persistence; coarse+refine search; bestT vein; origin stamen
ADD:
  1. Epicycloid counter-layer — one outer epi curve, same petal multiplier, opposite spin (the header promised it; the sampler never drew it)
  2. Petal crossings — a short caustic where two hypotrochoid layers are both near the pixel, away from the stamen
FORBID: extraBuffer springs; spirograph cusp flash or stator ghost
A PACKING: ACES display RGBA

---

SHADER: gen-de-jong-attractor
IDENTITY: Monte Carlo density of the Peter de Jong map, plus the hero tube
KEEP VERBATIM: Morph Speed A/B / Glow Radius / Trail Decay; de_jong iterate; stretch tint; dwell rings; pointer spring; click deformation; raw A
ADD:
  1. Critical curves — faint scaffold where cos(a y) or cos(c x) vanishes
  2. Antipodal ghost — the same orbit also ticks −p
FORBID: ACES on the stored density; a new spring
A PACKING: accumulated density, hue phase, tube depth, alpha (raw)

---

SHADER: gen-crystal-caverns
IDENTITY: raymarched cave tube lined with octahedra, hex prisms, and pyramids, caustic light, subsurface scatter
KEEP VERBATIM: Cave Scale / Crystal Purity / Glow Intensity / Fog Density; the three habit SDFs; causticIntensity; existing click shocks
ADD:
  1. Phantom shell — a smaller, earlier-time copy of the same habit inside each crystal, stronger at low Purity
  2. Basal pinacoid — flat base cut on each habit so it sits on a face
FORBID: a new spring; lattice hopper/twin copied onto this raymarch; replacing the march with 2D dendrites
A PACKING: ACES display RGBA

---

SHADER: gen-celestial-forge
IDENTITY: contra-rotating greebled rings around a plasma core, with hammer-strike ripples
KEEP VERBATIM: Rotation Speed / Complexity / Ring Scale / Core Intensity; spring cursor; greebles; trenches; panels; plasma arcs; click hammer strikes
ADD:
  1. Temper gradient — inner rings white-hot, outer rings straw then blue, graded by ring index
  2. Hammer flats — a low-count chamfer on the torus tube, stronger while a strike is live. Greeble sine noise stays
FORBID: new springs; twin facets or weld seams from gen-radiant-quantum-crystalline-forge
A PACKING: ACES display RGBA

---

SHADER: gen-cosmic-web-filament
IDENTITY: Zel'dovich displacement into a Voronoi filament field with quasar junctions
KEEP VERBATIM: Warp Strength / Filament Density / Evolution Speed / Void Pull; zeldovichDisplacement; filament ridge; ridged striation; quasar junctions; spring void well
ADD:
  1. Walls — a faint sheet where F2−F1 is mid-range, between the filament and the empty cell
  2. Galaxy beads — hashed points on the filament, away from the junction. Not a second quasar
FORBID: a new spring; replacing Voronoi filaments with a different cosmology
A PACKING: ACES display RGBA

---

SHADER: gen-dla-copper-deposition
IDENTITY: eight-neighbor diffusion-limited copper dendrite with oxidation
KEEP VERBATIM: Growth Scale / Arm Count / Oxidation / Spark Intensity; center cathode; held electrode; click nuclei; oxidation age; tip sparks; raw A
ADD:
  1. Tip screening — attach falls off as neighborMean rises, so fjords slow and exposed tips keep growing. Seeds still force growth
  2. Growth-front sheen — a bright copper rim where deposit meets empty electrolyte, distinct from the activity-channel spark
FORBID: replacing the DLA update; ACES on stored fields; a new spring
A PACKING: raw (deposit, depletion, oxidation, activity)
