# Idea Cards — Grok high (`grok/batch-01`, 2026-10-25)

Written before WGSL edits. Fifteen shaders, 120–199 lines. Each card adds **two** new ideas. Earlier ideas stay. Saved `params` stay byte-exact. No shared spring, ripple stamp, or IQ palette.

Formula rule: a §12.2 row is used on at most one file here. Most additions are domain extensions of quantities the file already computes, so they are not table rows.

---

## cellular-automata-rgba

IDENTITY: four-channel ecosystem — plants, herbivores, predators, nutrients — with continuous densities.
KEEP VERBATIM: RGBA packing and the growth / eat / predation / decay roles of Plant Growth, Herbivore Efficiency, Predator Efficiency, Decay Rate; herbivore taxis; nutrient death-bloom and soil patches; click seeds plants; ripple nutrient scare.
MECHANISM:
- tactic 2: a predator's kill rate saturates (Holling II); a plant below a neighbor threshold fails to establish (Allee).
- tactic 3: `avgPlants` and `herbivorePredation` are already computed and then used linearly.
- tactic 6: C is the four densities; both ideas rewrite those same fields, not a new channel.
ADD:
  1. Holling type II satiation — divide the existing predation term by `1 + k·herbivores` so a herd is not erased in one step, and predators receive the same reduced meal.
  2. Allee establishment — plant growth (already using `avgPlants`) collapses when the neighborhood is barren, and stays near full when neighbors are present.
FORBID: a second CA rule family, springs, neon overlays.
A PACKING: raw (plants, herbivores, predators, nutrients). ACES on display only.
FORMULA: no §12.2 row (ecology terms on the existing Lotka–Volterra step).

## gen-conway-game-of-life

IDENTITY: neon Game of Life on a coarse grid, morphing Classic / Day & Night / HighLife, with birth, death, and trail color.
KEEP VERBATIM: the three rule weights, cell size from Grid Scale, seed from Seed Density, trail from Trail Decay, generation in C.g, neighbor heat, still-life amber, split deaths, glider lean, bezel, oscillator strobe, pointer spring already in the file.
MECHANISM:
- tactic 3: `neighbors` and `generation` are already on the pixel and only tint coarsely.
- tactic 6: generation is the longevity field in C; rings read it, they do not repack it.
ADD:
  1. Longevity rings — concentric bands from the generation counter so an old still life shows age the way a growth ring does.
  2. Survival knife-edge — cells alive on exactly two neighbors (Conway's lonely edge) take a cold rim, distinct from the neighbor-heat ramp.
FORBID: a new rule, extraBuffer slots, IQ palette.
A PACKING: raw alive, generation, activity, alpha.
FORMULA: no §12.2 row.

## gen-bioluminescent-reaction-diffusion

IDENTITY: Gray–Scott bioluminescence, cyan substrate and violet activator, with luciferin age.
KEEP VERBATIM: 9-point Laplacian, feed/kill from luma, Intensity / Simulation Speed / Spatial Scale / Mouse Influence, luciferin quench, excitation front, pointer age reset, quorum ignition. A/B/age packing.
MECHANISM:
- tactic 3: neighbor A samples exist for the Laplacian and are discarded after it; luciferin age is already a glow weight.
- tactic 2: a real dinoflagellate trail leaves a substrate ridge, and a quenched colony goes dark rather than merely dimmer.
ADD:
  1. Substrate veins — cyan ridges on `|∇A|` from the four edge neighbors already loaded.
  2. Quenched-core bleach — high luciferin age pulls the glow toward the deep-water color already used as the background, so spent colonies go dark instead of staying pastel.
FORBID: replacing Gray–Scott, a new species channel, springs.
A PACKING: raw (A, B, luciferin-age, 1). ACES on display only.
FORMULA: no §12.2 row (the 9-point Laplacian is already the solver, not a new idea).

## gen-dla-copper-deposition

IDENTITY: persistent copper dendrites grown by diffusion-limited aggregation, oxidizing as they age.
KEEP VERBATIM: deposit / depletion / oxidation / activity packing; Growth Scale, Arm Count, Oxidation, Spark Intensity; tip screening, growth-front sheen, dendrite twin, electrolyte meniscus; cathode, held cursor, and click seeds.
MECHANISM:
- tactic 2: real electrodeposited copper anneals into facets, and current crowds into exposed tips.
- tactic 3: `oxidation` and `exposed` (from `neighborMean`) are already in the metal color and only drive patina and screening.
ADD:
  1. Annealing grain — facet tint from a stable cell hash, strength following stored oxidation, so old copper breaks into grains.
  2. Current crowding — extra warm highlight on fresh tips that are still exposed (low neighbor fill), distinct from the hash spark and the front sheen.
FORBID: a second aggregate species, springs, oil-slick thin film.
A PACKING: raw deposit, depletion, oxidation, activity.
FORMULA: no §12.2 row.

## wave-equation

IDENTITY: a 2D wave tank on the photo, with height, velocity, foam, and a pointer oscillator.
KEEP VERBATIM: damped wave step, Wave Speed / Damping / Source Strength / Reflectivity, foam from `|laplacian|`, caustic ridges, standing-node darkening, click fronts, wall reflectivity. Packing (h, v, foam, phase).
MECHANISM:
- tactic 1: the update is a non-dispersive wave; short waves should die faster than the swell.
- tactic 2: a crest steeper than the slope already measured for caustics breaks into a whitecap that the foam channel can carry.
- tactic 6: foam is already the persistent field; whitecaps write into it.
ADD:
  1. Capillary damping — extra velocity loss where `|laplacian|` is large, so tight rings die and long waves travel. Discrete stand-in for deep-water dispersion (§12.2D), one file only.
  2. Breaking whitecaps — foam locks on when the previous crest is both positive and steep, then the existing foam decay carries the cap.
FORBID: a new solver, Gray–Scott, springs.
A PACKING: raw (height, velocity, foam, oscillator phase). ACES on display only.
FORMULA: deep-water dispersion (§12.2D), adapted as scale-dependent damping on the existing velocity. Whitecaps are not a table row.

## slime-mold-on-video

IDENTITY: physarum trails eating video luma, advected by the packed drift.
KEEP VERBATIM: trail / food / drift packing; Follow, Decay, Food Gain, Glow; anastomosis bridges; streamer veins; chem packets; click food fronts.
MECHANISM:
- tactic 4: Decay is one scalar; on a real mold it is faster off the food.
- tactic 7: drift and `gradFood` already exist; their alignment is the chemotaxis confidence the deposit ignores.
ADD:
  1. Substrate-gated decay — trails evaporate faster where video luma is low, and keep the saved Decay rate on bright food.
  2. Chemotaxis confidence — extra deposit where the drift direction agrees with the food gradient.
FORBID: a particle agent buffer, a new food channel, galaxy costume.
A PACKING: raw (trail, food, drift.x, drift.y).
FORMULA: no §12.2 row.

## galaxy-compute

IDENTITY: volumetric log-spiral galaxy — arms, fBm nebula, Keplerian star motes, halo — composited over the photo by optical depth.
KEEP VERBATIM: `spiralArmDensity` (3 arms, tightness 2.2), nebula warp, 3×8 Keplerian motes, halo, optical-depth composite. Slider roles as the shader uses them today: `zoom_params.x` zoom, `.yz` pan, `.w` opacity (JSON labels stay Gravity / Damping / Star Size / Pattern Opacity; do not retarget them).
MECHANISM:
- tactic 2: a trailing dust lane sits just off the log spiral the density function already integrates; the bulge is already a hot core.
- tactic 3: arm phase is computed inside `spiralArmDensity` and thrown away; bulge is a scalar multiplied into color.
ADD:
  1. Trailing dust lane — extinction and reddening on the phase just behind the existing arm crest.
  2. Core blackbody — the existing bulge temperature shifts hotter, with bass lifting that core (§12.2F blackbody via the file's `colorTemperature`).
ALSO (floor, not ideas): prelude include, ACES on display, `dataTextureA` write, `plasmaBuffer` on the core and a slight treble lift of the existing motes.
FORBID: a second galaxy, phyllotaxis florets, springs, click shockwaves.
A PACKING: ACES display RGBA (C is not read).
FORMULA: blackbody (§12.2F) on the bulge only.

## gen-verlet-cloth-wind

IDENTITY: a pinned cloth height field in wind, read back as shaded fabric.
KEEP VERBATIM: 64×64 (h, v) lattice, Wind / Gravity / Stiffness / Sheen, gust front, hem lead, warp/weft tension sheen, fold occlusion, pinned row `y == 0`.
MECHANISM:
- tactic 2: a woven selvage at the free side edges is stiffer than the body.
- tactic 3: `stretch` is already the sheen amplitude; near-zero stretch is slack cloth and is currently lit the same as a taut panel.
ADD:
  1. Selvage stiffness — the free side columns damp velocity more, so the edges do not flap like the belly. The pin row stays locked.
  2. Slack drape — panels with near-zero stretch darken, distinct from the concave fold term.
FORBID: a 3D mesh, a new grid size, springs.
A PACKING: raw (h, v, 0, 0) on the lattice; display RGBA outside it (unread).
FORMULA: no §12.2 row.

## gen-phyllotaxis-galaxy-spiral

IDENTITY: a golden-angle floret spiral read as a galaxy, with bulge, disk, dust lanes, and H II knots.
KEEP VERBATIM: `n·PHI` placement, `c·sqrt(n)` radius, flat rotation curve, Star Spread / Star Size / Disk Rotation / Wave Density, Sersic bulge, dust lane, H II knots, parastichy sheen, shock fronts.
MECHANISM:
- tactic 2: a real capitulum has a bract on the outer side of each floret, and the youngest florets are the outer ring.
- tactic 3: `pos`, `radial` direction, and `r` exist per floret and only draw a Gaussian star.
ADD:
  1. Seed-scale bracts — a short radial streak on the outer side of each floret, using that floret's position vector.
  2. Meristem rim — the outermost florets (large `r`) take a cool youth tint, scaled by treble. Inner Hubble colors stay.
FORBID: a second spiral law, replacing PHI, Conway, cloth.
A PACKING: ACES display RGBA in A.
FORMULA: no §12.2 row (golden-angle layout is already the motif, not a new formula).

## gen-plasma-mandala

IDENTITY: a dihedral plasma mandala — folded petals, a hollow diocotron ring, click echoes in every petal.
KEEP VERBATIM: Symmetry / Spin Speed / Zoom / Glow Scale, sector fold, plasma trig sum, diocotron ring, dihedral pulses, midline filaments, Debye sheath.
MECHANISM:
- tactic 3: filament and `ring_r` are both on the pixel and never meet; the sheath is only the inner gap.
- tactic 2: where a current filament crosses the column edge, plasma reconnects; just outside the column the density was expelled.
ADD:
  1. X-point reconnection — a white flash where the petal filament crosses the diocotron ring.
  2. Density cavity — a dim well just outside the ring, opposite the existing inner Debye sheath.
FORBID: a second symmetry group, thin-film as the look, springs.
A PACKING: ACES display RGBA in A.
FORMULA: no §12.2 row.

## gen-fractal-tree-growth

IDENTITY: a recursive branching tree that grows from the base, with bark, sap, and a leaf glow.
KEEP VERBATIM: depth / spread / growth / leaf-glow params, per-level sway, sap pulses, bark rings, apical buds, click growth rings. A stores pre-ACES HDR.
MECHANISM:
- tactic 2: wind-bent wood lays reaction wood on the compressed side; bark has lenticels between the rings.
- tactic 7: `bend` and segment `h` exist and only move the centerline and the rings.
ADD:
  1. Reaction wood — the compressed side of each bend (cross of the segment direction with the pixel) is thicker.
  2. Lenticels — sparse dark pores along `h`, between the existing continuous bark rings.
FORBID: a second tree species, hyperbolic disk, springs.
A PACKING: raw HDR display RGBA (ACES on writeTexture).
FORMULA: no §12.2 row.

## gen-hyperbolic-tree

IDENTITY: one Poincaré-disk tree with geodesic lattice and horocycles in the negative space.
KEEP VERBATIM: Möbius map, depth from param1, branch angle from param2, metric-thinned strokes, terminal leaves, ideal 7/14 polygons, horocycles, chromatic leaves.
MECHANISM:
- tactic 2: hyperbolic length piles up at the rim, so branches there should run hotter.
- tactic 3: the 7-fold angle used by the ideal polygon is not painted into the empty sectors.
ADD:
  1. Rim crowding — branch glow near the disk boundary shifts hot, where the metric already thins the stroke.
  2. Fuchsian sector tint — a faint alternating wash of the same 7-fold, only in negative space, rotating with the geodesic lattice.
FORBID: a Euclidean tree, a new polygon family, springs.
A PACKING: ACES display RGBA (read back as colour history).
FORMULA: no §12.2 row.

## gen-fireworks-dahlia-burst

IDENTITY: firework shells that open as dahlia disks — rows of petals, pistils, midribs, falling tips.
KEEP VERBATIM: Petal Count / Disk Size / Petal Rows / Hue Cycle, imbrication, midrib, involute curl, pistil florets, gravity on `sparkPos`, launch-then-burst timing.
MECHANISM:
- tactic 5: a decorative dahlia petal is notched at the tip; the disk sheds pollen as it ages.
- tactic 3: `perp`, `fallPos`, and the pistil center already exist.
ADD:
  1. Tip notch — two lobes offset along the petal perpendicular, with the center tip slightly reduced, so the tip reads as laciniated.
  2. Falling pollen — a few gold grains launched from the pistil disk and dropped with the existing gravity.
FORBID: a second flower, a galaxy shell, springs.
A PACKING: ACES display RGBA.
FORMULA: no §12.2 row.

## particle-dreams-hdr

IDENTITY: five depth layers of the photo, vortex-zoomed with flow noise, then an exposure bloom and fog.
KEEP VERBATIM: 5-layer accumulation, Bloom Radius / Bloom Intensity / Tone Map Exposure / Fog Density and their existing layer-speed coupling, 16-tap bloom, depth chromatic, fog mix. A stores raw HDR rgb plus exposure (C is not read).
MECHANISM:
- tactic 8: bloom currently adds light the source still keeps.
- tactic 3: `dist` to the vortex center is already the spin weight and is never used to hollow the tunnel.
ADD:
  1. Energy-conserving bloom (§12.2F) — the source loses a fraction of the spread before the spread is added back.
  2. Hollow vortex eye — layer weight falls at the spin center so the dream tunnel has a pupil.
ALSO (floor): mouse glow uses `zoom_config.yz` as 0–1 UV (it was divided by resolution, so it sat on the origin). Semantic alpha from layer weight, bloom, and fog. No new audio claim.
FORBID: a particle simulation, slime, springs, a second bloom kernel.
A PACKING: raw HDR rgb + exposure in A. ACES on writeTexture only.
FORMULA: energy-conserving bloom (§12.2F).

## nano-assembler

IDENTITY: a grid of nanobots that merge into the photo as assembly rises, and scatter away from the pointer.
KEEP VERBATIM: Assembly Progress / Particle Density / Scatter Force / Rebuild Speed, cell soft-body, docking seams, ballistic radial scatter, emission mix.
MECHANISM:
- tactic 4: Assembly Progress is one scalar; a printer head is that scalar as a position across the grid.
- tactic 5: a growing lattice has vacancy sites that fill only when the build is nearly done.
ADD:
  1. Print-head front — cells ahead of `uv.x = assembly progress` stay mostly scattered; the slider remains "how far the build has reached."
  2. Lattice vacancies — stable holes from the cell hash, filled only at high Assembly Progress.
FORBID: a fluid solver, DLA dendrites, springs.
A PACKING: ACES display RGBA.
FORMULA: no §12.2 row.

---

## Batch de-duplication

| §12.2 row | Files |
|---|---|
| Deep-water dispersion (D), as capillary damping | wave-equation only |
| Blackbody (F) | galaxy-compute only |
| Energy-conserving bloom (F) | particle-dreams-hdr only |

No other file uses a table row. Dust lanes stay on the two galaxies that already had or now gain them, and they are different mechanisms (phyllotaxis arm phase vs volumetric log-spiral trailing phase).
