# Claude generative-fourteen — Idea Cards

Written before WGSL edits, 2026-10-19. Four groups worked in parallel (A fractal/geometry,
B cosmic/particle, C organic/bio, D sim/image); each group's cards were written before its edits.

Batch: gen-quantum-aether-origami, gen-nebular-chrono-astrolabe, gen-neural-fractal,
gen-murmuration-phantom, sand-dunes, gen-fractal-bioluminescence-spore-network, aurora-curtain,
voxel-grid, gen-bioreactor-bloom, spore-galaxy, neon-edge-pulse, gen-luminous-cauldron,
gen-xeno-botanical-synth-flora, generative-turing-veins. `turing-veins` is a second definition
(shader_definitions/generative/turing-veins.json) serving generative-turing-veins.wgsl, so it is
covered by that file. Eight files pasted the 13 bindings and were migrated to
`#include "_prelude.wgsl"` first in a separate header-only commit (not counted).

Coordinator change after the cards: gen-bioreactor-bloom Idea 6 (culture turbidity, Beer–Lambert)
was dropped at review because Beer–Lambert landed on three files (§12.4 de-dup limit is two). See
COORDINATOR_REVIEW.md.

---
<!-- group A -->
# Agent A — Idea Cards (2026-10-19)

Files: gen-quantum-aether-origami, gen-neural-fractal, gen-fractal-bioluminescence-spore-network, voxel-grid.
Cards written before any WGSL edit.

## gen-quantum-aether-origami

```
SHADER: gen-quantum-aether-origami
IDENTITY (one sentence): a raymarched KIFS "paper" sheet (thin box ∪ sphere) folded by five
  domain-warped mirror planes per iteration, lit with thin-film interference, Fresnel rim, crease
  edge glow and fog; the pointer unfolds it back to a flat plane near the cursor.
KEEP VERBATIM: map() (curl flow, domainWarp fold normals n1..n5, 5 folds + 3 rotations + abs per
  iteration, iters = mix(1,10,x), thin box smin sphere, fbm detail); 100-step march with
  mix(flat, folded, fold_factor); thin-film palette(view_angle) bands; soft shadow; 5-tap AO;
  spectralFold; Fresnel rim; crease emissive (Crease Glow = y); Beer–Lambert fog; existing
  Idea 1 (superposition jitter in the C mix) and Idea 2 (chromatic fold creases); param roles
  x Fold Complexity / y Crease Glow / z Audio Reactivity / w Interference Shift.
MECHANISM INTERROGATION:
  t1 (deepen the kernel): fold() is a conditional reflection — whether a point was reflected is
    computed (t < 0) and thrown away. The full KIFS state is (position, reflection record).
  t2 (physics one step further): real folded paper has mountain and valley folds (the facet's
    orientation flips at every crease), and a crease line is whitened where the fibres break —
    the paper is lighter exactly where it bends hardest.
  t3 (promote an intermediate): the per-plane reflection test inside fold(); the SDF itself
    (second derivative = bend) — only its gradient is used today.
  t6 (history): C is read as display colour history (0.02-ish mix + jitter); no extra
    continuity needed — the new ideas are geometric, so packing is untouched.
ADD (2 native ideas, numbering continues after existing Ideas 1–2):
  3. Mountain/valley fold parity — §12.2E "Fold count as material": count reflections in the
     existing fold() calls; parity flips facets between a lit (mountain) and slightly cooler,
     shaded (valley) paper tone; the total count wears the paper (more folds → more
     interference sheen). Flattened region (fold_factor→0) fades it out.
  4. Whitened crease lines — §12.2E "SDF curvature": κ ≈ (Σ d(p±e·axis) − 6d)/e² on map();
     high positive bend = broken fibres → a thin pale crease line, riding Crease Glow (y),
     which is the slider's existing role.
FORBID on this file: springs, click fronts, a new palette, a different fractal, new params.
A PACKING: ACES display RGBA (C read as colour history) — unchanged.
```

## gen-neural-fractal

```
SHADER: gen-neural-fractal
IDENTITY (one sentence): a Julia-style escape iteration where each layer is a neural activation
  (sigmoid / tanh / swish / mixed), coloured by two orbit-trap "somata", dendritic stalk traps
  with a growth cone, firing-rate glow, inhibitory surround and Hebbian C persistence.
KEEP VERBATIM: neuralLayer() and activation cycling (iter/10 % 4); domain warp, pointer pull,
  click stimulus; juliaC; trap1/trap2/minZ/sumZ; multiTrapColor; existing Ideas 1–4 (dendrite
  stalk + growth cone, firing-rate glow, inhibitory ring, Hebbian C mix); vignette; ACES; alpha;
  params x Zoom / y Color Cycling / z Iteration Depth / w Mutation.
MECHANISM INTERROGATION:
  t1 (deepen the kernel): the dendrite trap stores only the distance to the stalk and the
    iteration; the position *along* the stalk at that iteration is computed and discarded, so
    the dendrite is a featureless tube.
  t2 (biology one step further): myelinated fibres conduct saltatorily — the impulse jumps
    between nodes of Ranvier; dendrites end in synaptic boutons on another cell's soma, and the
    postsynaptic response lags the spike by a synaptic delay.
  t3 (promote an intermediate): z along the stalk at the dendTrap iteration; d2 (distance to the
    second soma trap) at that same iteration.
  t6 (history): C is display RGBA and is already used for Hebbian persistence; no new
    continuity is taken from it (keeps the new ideas distinct from Idea 4).
ADD (2 native ideas):
  5. Nodes of Ranvier / saltatory conduction — record the along-stalk coordinate at the trap
     minimum; bright node beads at fixed spacing, myelin dims between them, and the impulse
     lights one node at a time (quantised node index → it hops, not glides).
  6. Axo-somatic synaptic boutons with synaptic delay — record d2 at the trap minimum; where a
     dendrite terminates on soma 2, a bouton knob flashes on the spike train phase-delayed by
     a fixed synaptic lag.
FLOOR: replace pow((dendTrap-0.08)*22, 2) (negative base) with a square; clamp ≥0 before ACES.
FORBID on this file: springs, new click fronts, a new palette, another fractal, new params.
A PACKING: ACES display RGBA in A (unchanged).
```

## gen-fractal-bioluminescence-spore-network

```
SHADER: gen-fractal-bioluminescence-spore-network
IDENTITY (one sentence): a glow-accumulation march through a KIFS-folded field of two Clifford
  spores joined by a filament and a hypha capsule, with light packets on the hypha, quorum pulse,
  marine snow, pointer nutrient injection and click rings, hue-drifted and depth-absorbed.
KEEP VERBATIM: map() (KIFS abs/rot loop, Clifford spores, filament, hypha capsule, packet);
  64-step 0.5× march with glow += 0.01/(0.01+d²)·density; col_base/col_hot mix; injection;
  click rings; quorum; packets; marine snow; hueShift drift; depth-texture absorb; max(prev·decay)
  persistence; params x Spore Density / y Network Complexity / z Bioluminescence / w Audio.
MECHANISM INTERROGATION:
  t1 (deepen the kernel): the march accumulates scalar glow per step with no regard to how far
    that light travelled to the eye; every step's emission arrives at full strength.
  t2 (physics one step further): bioluminescence is seen through seawater, which absorbs red
    fastest and blue-green slowest; and luciferin is consumed by a flash — a dinoflagellate
    that keeps being stimulated flashes, then dims while it recharges.
  t3 (promote an intermediate): the per-step march distance t inside the glow loop.
  t6 (history): C is display RGBA used as a max(prev·decay) afterglow; its luma is a direct
    record of how hard this pixel has been glowing — i.e. how depleted it is.
ADD (2 native ideas, numbering continues after the 4 listed ideas):
  5. Seawater spectral extinction — §12.2F "Beer–Lambert": each glow step's contribution is
     weighted by exp(−σ_rgb·t) with σ_r ≫ σ_g > σ_b; the normalised result tints the glow so far
     spores read blue-green and near ones keep the warm hot core.
  6. Luciferin depletion — fresh emission is reduced where C luma is already high, so a held
     injection or a hot quorum zone flashes and then settles to a lower steady glow; the existing
     max(prev·decay) afterglow still holds the trail.
FLOOR: clamp ≥0 before ACES (hueShift can go negative).
FORBID: springs, new click fronts, IQ palette, replacing the march, new params.
A PACKING: ACES display RGBA (unchanged).
```

## voxel-grid

```
SHADER: voxel-grid
IDENTITY (one sentence): the photo rebuilt as a 24-layer hashed voxel volume inside a box;
  each hit voxel is a rotating rounded cube tinted from the photo at its cell centre plus an
  axis-face sample, lit by key/fill + Fresnel, with mortar AO, C trails and chromatic shift.
KEEP VERBATIM: rayBoxIntersect; 24-layer occupancy loop (hash21 < threshold); curl/warp shift;
  rotation by pointer influence + curl + bass; sdBox2 cell with pop; fake normal; key/fill/
  Fresnel; cellColor/faceColor/palette mix; existing mortar AO and axis-face tint; C trail mix;
  chromatic shift; ACES; premultiplied alpha; params Grid Density / Touch Radius / Rotation
  Force / Cell Gap.
MECHANISM INTERROGATION:
  t1 (deepen the kernel): lighting is per-voxel only (n·l); the occupancy volume that the
    loop already samples is never asked whether the light can reach the voxel.
  t2 (physics one step further): a real voxel/block render shows cast shadows from neighbouring
    voxels in front, and a bevel catch-light along the light-facing edge of each cube.
  t3 (promote an intermediate): the occupancy test (hash < threshold) per layer and hitLayer;
    the signed cell distance `box` (only used for mask and mortar AO, both outside the edge).
  t6 (history): C is premultiplied display history; no extra continuity needed.
ADD (2 native ideas, numbering continues after existing 2):
  3. Voxel cast shadow — march 3 layers back toward the camera from the hit layer, shifted
     toward the key light, re-running the same hash occupancy test; occupied cells shadow the
     hit voxel's key light.
  4. Bevel catch-light — inside the cube edge (−box small), the light-facing side of the bevel
     gets a thin highlight (cell-gap scaled width), the shadow side a soft darkening.
FLOOR: clamp ≥0 before ACES.
FORBID: springs, ripples, new palette, replacing the layer loop, new params.
A PACKING: ACES display RGBA, premultiplied (unchanged).
```

---

---
<!-- group C -->
# Agent C — Idea Cards (written before WGSL edits, 2026-10-19)

Files: gen-bioreactor-bloom, gen-luminous-cauldron, gen-xeno-botanical-synth-flora.
All three already carry `Ideas:`; prior ideas stay, new ideas continue the numbering.
§12.2 rows used: Beer–Lambert (F) on bioreactor only; Snell vector refraction (F) on cauldron only;
golden-angle layout (E) on xeno only. No row is shared between my files.

## gen-bioreactor-bloom

```
SHADER: gen-bioreactor-bloom
IDENTITY (one sentence): a scrolling, fbm-warped grid of glowing green culture cells (nucleus +
  membrane + mitosis bud), with cyan nutrient tendrils, pulsing bloom rings, a red toxin cloud at
  the cursor that necrotises tendrils, and treble spores.
KEEP VERBATIM: param roles (Cell Scale -> grid density 6..52, Mitosis -> centre spread + bud event,
  Reactivity -> nucleus sharpness / tendril + bloom gain / ring speed, Toxicity -> poison cloud);
  fbm warp; per-cell hash22 seed; nucleus/membrane/pulse formulae; mitosis bud (Idea 1);
  necrosis creep (Idea 2); reactivity bloom rings (Idea 3); colour palette; 3% exact-C blend;
  ACES; alpha and depth formulae (extended additively).
MECHANISM INTERROGATION:
  t1 (deepen the kernel): each cell is evaluated in isolation in its own grid cell; neighbouring
    cells never influence one another. The next-better model of a culture is one where cells sense
    their neighbourhood — a 3x3 neighbour read of the same hash22 seeds.
  t2 (physics one step further): a real culture signals by quorum sensing — when local cell
    density passes a threshold, the autoinducer synchronises gene expression and the colony
    luminesces in unison (V. fischeri). Also: a bioreactor's growth is measured by optical density
    — a dense culture makes the medium turbid and attenuates light behind it.
  t3 (promote an intermediate): `dividing`, `divisionAxis`, `center2` exist only to place the bud
    nucleus; the membrane ignores the division, so the bud floats inside an unbroken circle.
  t6 (history the shader owns): C is read as display colour (3% blend). Its luminance is a
    running memory of where biomass has glowed — an optical-density proxy without new state.
ADD (3 native ideas, numbered after the existing 3):
  4. Cleavage furrow — while `dividing`, the membrane becomes a dumbbell wrapping both nuclei and a
     contractile ring pinches the cytoplasm along the plane perpendicular to `divisionAxis` at the
     parent/bud midpoint. Mitosis slider gets a real division silhouette.
  5. Quorum-sensing pulse lock — mean seed of the 3x3 neighbourhood = autoinducer level; above a
     Reactivity-scaled threshold each cell's pulse phase is pulled toward the neighbourhood phase,
     so dense patches blink in sync and gain a shared bioluminescent wash.
  6. Culture turbidity (Beer–Lambert, §12.2F) — OD from exact-C luminance; transmittance
     T = exp(-OD) dims the layers behind the colony plane (bloom rings, poison cloud), scattered
     light becomes a faint green haze, and (1-T) adds to alpha as semantic opacity.
FLOOR: smoothed-bass envelope moved off extraBuffer[0] (triaged baseline violation) to guarded
  extraBuffer[133], single writer at (0,0); clamp before ACES.
FORBID on this file: springs, click shockwaves, IQ palettes, replacing the grid cells with a
  Voronoi/RD sim, new params.
A PACKING: display RGBA (ACES colour + semantic alpha), C read as colour — unchanged.
```

## gen-luminous-cauldron

```
SHADER: gen-luminous-cauldron
IDENTITY (one sentence): a top-down glowing pot of violet/orange swirling plasma brew with
  caustics, three layers of rising bubbles and froth, Minnaert burst rings, a meniscus rim caustic
  and treble sparks; mouse offsets/stirs, clicks drop bubbles.
KEEP VERBATIM: param roles (Boil Rate -> swirl/rise/pop speed, Convection -> shimmer + wave speed,
  Foam -> froth/collapse gain, Radiance -> brew/caustic/meniscus brightness); heatShimmer; swirl
  convectionWaves; causticPattern; 3-layer bubble grid; collapseRing (Idea 1); meniscus (Idea 2);
  palette; 3% exact-C blend; ACES; alpha/depth formulae (extended additively).
MECHANISM INTERROGATION:
  t1 (deepen the kernel): bubbles are flat discs (`smoothstep` of a 2D sphere SDF); the bubble
    already has a radius and centre, so it has a hemispherical normal — the next-better bubble is a
    lens, not a sticker.
  t2 (physics one step further): a boiling pot nucleates bubbles where the hot plume upwells, not
    uniformly; and a boil throws steam off the surface which veils and scatters the glow below.
  t3 (promote an intermediate): `convectionWaves` (the hot-orange vs cool-violet band) only tints;
    the caustic net is computed but never interacts with bubbles; `collapse` bursts only draw rings.
  t6 (history): C is display colour, 3% blend — no extra continuity needed for these ideas.
ADD (3 native ideas, numbered after the existing 2):
  3. Bubble lensing of the caustic net (Snell vector refraction, §12.2F) — each bubble's hemisphere
     normal refracts the view ray (eta = 1/1.33, gas in liquid) and offsets where the caustic net is
     evaluated, so caustics bend/magnify inside bubbles.
  4. Plume-gated nucleation — bubble survival threshold lowered in the hot (orange) convection
     band and raised in the cool violet band, so bubbles stream from upwellings.
  5. Steam veil — fbm wisps drifting along the swirl, densest over the hot band and over burst
     rings, that lift and soften the brew glow (forward scatter of the brew colour, not white fog).
FLOOR: two `pow(x, 2.0)` with possibly-negative bases in the meniscus replaced by x*x.
FORBID on this file: new ripple systems, springs, IQ palette, replacing the swirl with a fluid
  solver, new params.
A PACKING: ACES display RGBA in A — unchanged.
```

## gen-xeno-botanical-synth-flora

```
SHADER: gen-xeno-botanical-synth-flora
IDENTITY (one sentence): an alien flora layer over the input — rotating L-system branch fan from
  the centre, Turing-venated leaves tiled on a 4x4 grid, conductive filaments on branch ridges,
  bioluminescent pulse; R=branch ID, G=nutrient, B=bioluminescence colour encoding.
KEEP VERBATIM: param roles (x growth, y complexity, z depth weight, w glow spread); branchDensity;
  turingPattern; sdLeaf + leafVeinMask; lSystemIterate; ideas 1-5 (veins, filaments,
  phototropism + spores, stomata, prickles); colour encoding; 0.85 input mix; 6% exact-C blend;
  depthLayered/volumetric alpha; ACES.
MECHANISM INTERROGATION:
  t1 (deepen the kernel): leaves are a single identical blade per fract(uv*4) tile, all pointing
    +x. A plant places successive leaves by phyllotaxis — the golden angle.
  t2 (physics one step further): the branches are vascular — xylem carries sap outward from the
    root; the G channel is already "nutrient" but is static fbm.
  t3 (promote an intermediate): `radius` (distance from the centre/root) and `ridge` (branch crest
    mask) are computed; ridge is only used for filaments/prickles.
  t6 (history): C is display colour at 6% — no new continuity needed.
ADD (2 native ideas, numbered after the existing 5):
  6. Golden-angle phyllotaxis (§12.2E) — each tile carries a rosette of up to 3 leaves at
     successive golden-angle (2.39996 rad) turns, sizes ~sqrt(i); later leaves unfurl as Growth
     rises. Veins/stomata follow the nearest leaf's frame.
  7. Xylem sap pulses — travelling fronts (sharp leading edge, decaying tail) run outward from the
     root along `ridge`, pumped faster by bass, written into the G (nutrient) channel.
FORBID on this file: different plant/creature, springs, IQ palette, new params.
A PACKING: ACES display RGBA — unchanged.
```

---

---
<!-- group D -->
# Batch D — Idea Cards (written before WGSL edits, 2026-10-19)

Files: sand-dunes, neon-edge-pulse, generative-turing-veins (served by two defs:
generative/generative-turing-veins.json and generative/turing-veins.json).

## sand-dunes

```
SHADER: sand-dunes
IDENTITY (one sentence): a warm desert of wind-aligned, domain-warped fBm dunes lit by a
  blackbody sun (GGX glints, rim, SSS on crests), with superposed ripple bands, treble
  saltation sparkles, a pointer wind-shadow, depth haze and a slow trail feedback.
KEEP VERBATIM: anisotropic fBm height along windDir (x2.5), finite-difference `slope` along the
  wind axis (slope < 0 = lee/shadow side, the file's convention), crest/bubble, ripple1*ripple2
  ripple mask, OkLab lit/mid/shadow/umber palette, blackbody key/fill/rim lights, GGX + Schlick
  spec, SSS, treble sparkles, mouse wind shadow, Rayleigh/Mie haze, trail = mix(prev*decay, hdr),
  alpha = bloomWeight, depth = height*0.5 + bubble, bass envelope in A.a.
  Param roles: x = Dune Scale (duneScale), y = Wind Speed (windBase/roughness),
  z = Erosion (ripple amount), w = Shadow Depth (shadowMask + trail decay).
MECHANISM INTERROGATION:
  t1 (deepen the kernel): the "kernel" is a single-axis slope; the shading treats the lee side as
    a smooth falloff. A real dune profile has a discontinuity: the brink, where the gentle stoss
    slope meets the slipface at the angle of repose. The next-better profile has a sharp terminator
    exactly where `slope` changes sign on high ground.
  t2 (physics one step further): sand piled past the angle of repose on the slipface fails in
    avalanches — grainflow tongues that run straight downslope and wipe out wind ripples (real
    slipfaces are ripple-free). Strong wind also lifts grains over the brink as spindrift
    streamers that trail downwind of the crest.
  t3 (promote an intermediate): `slope` and `height` (computed, used only for masks) give the
    slipface mask and the brink; `aniso` (wind-aligned coordinates) gives the downslope axis for
    the tongues without new geometry.
  t6 (history the shader owns): C is read at the same pixel as colour trail (rgb) + bass envelope
    (a). The same colour history read a few texels UPWIND (exact textureLoad) is the sand that was
    just blown over the brink — a streamer behind each crest, no new packing.
ADD (3 native ideas):
  1. Slipface grainflow tongues — past an angle-of-repose threshold on the lee side, narrow
     avalanche lobes elongated downslope (aniso.x) and thin across-wind (aniso.y), slightly
     lighter loose sand, sliding with the wind clock; grainflow erases the ripple mask there.
     Amount rides Wind Speed (more wind, more loading, more avalanching).
  2. Brink terminator — a sharp, sun-catching line where `slope` crosses zero on high ground, with
     a thin darker lip just over the edge; contrast scales with Shadow Depth (its existing role).
  3. Brink spindrift from history — on crests/brinks, blend in the exact C trail fetched a few
     texels upwind along windDir, a pale veil streaming downwind of the brink; length grows with
     wind speed + bass envelope.
FORBID on this file: springs, click shockwaves, IQ palettes, scanlines, a sand-particle sim,
  replacing the fBm dunes, changing any param's role.
A PACKING: unchanged HEAD packing — A.rgb = trail * alpha (colour history), A.a = smoothed bass
  envelope (read back as prev.a). ACES only on writeTexture.
```

## neon-edge-pulse

```
SHADER: neon-edge-pulse
IDENTITY (one sentence): five mirrored zoom layers of the photo centred on the pointer, each
  outlined by hue-shifted neon edges that pulse inward with the bass; hold to spin the tunnel.
KEEP VERBATIM (incl. Ideas 1–3 from 2026-10-05): ping-pong layer zoom law with 0.8 phase stagger,
  click vortex, 0.015 noise flow, depth-chroma split, exp(-1.5d) layer weights, per-layer 4-tap
  central-difference edges (Idea 1), inward bass pulse (Idea 2), centre proximity gain (Idea 3),
  fog chain, calculateVolumetricAlpha + calculateAdvancedAlpha, depth out.
  Param roles: x = Edge Threshold (edgeLo/edgeHi), y = Pulse Speed (zoom rate + pulse clock),
  z = Glow Intensity (neon gain + alpha), w = Color Shift (hue).
MECHANISM INTERROGATION:
  t1 (deepen the kernel): the edge is a flat-coloured smoothstep. A neon tube's emission profile is
    not flat: the gas column is so dense at its axis that it reads white-hot, with the saturated
    gas colour only in the surrounding glass glow. The gradient magnitude already measured says
    how far above threshold the edge is — that excess is the tube's current density.
  t2 (physics one step further): a low-pressure glow discharge is not uniform along the tube; it
    shows striations — standing/travelling bright-dark bands along the positive column.
  t3 (promote an intermediate): the central-difference gradient VECTOR (lumR-lumL, lumB-lumT) is
    reduced to a length and thrown away; its perpendicular is the tube's axis — the direction the
    striations run.
  t6 (history the shader owns): A is ACES display RGBA but C is never read. Phosphor-coated tubes
    keep glowing briefly after the drive drops; the display history gives that afterglow with an
    exact textureLoad, no packing change (C read as colour = what A stores).
ADD (3 native ideas, numbering continues):
  4. Plasma-core whitening — per layer, gradient excess over edgeHi pushes that layer's neon colour
     toward a white-hot core (desaturated, a little brighter); weak edges keep the pure gas hue.
  5. Discharge striations — bands along the tube axis (perpendicular of the existing gradient),
     travelling along the edge at the Pulse Speed clock; modulates the per-layer edge amplitude.
  6. Phosphor afterglow — exact C load; the neon part of last frame's display (above this frame's
     ACES base) decays at a fixed rate and is kept with max(), so pulse troughs and moving tunnel
     edges leave short glowing tails instead of snapping off.
FORBID on this file: springs, click shockwaves, IQ palettes, scanlines/hologram, a new edge
  detector, changing the layer law or param roles.
A PACKING: ACES display RGBA (unchanged); C now read back as display colour (truthful).
```

## generative-turing-veins

```
SHADER: generative-turing-veins
IDENTITY (one sentence): a dark field of organic, bioluminescent vein networks from three
  coupled Gray-Scott-stepped activator/inhibitor fields, with nutrient pulses in the vessels,
  bass feed waves and click-planted activator colonies.
KEEP VERBATIM: activatorField/inhibitorField fbm, one explicit Gray-Scott step per layer with the
  slider-driven kernel radius, 3-layer coupling (coarse/fine/micro), veinThickness, ridge mask,
  nutrientFlow, act/inh colour mixing (incl. the HSV-as-RGB quirk), bass radial feed pulse,
  click colony in extraBuffer[133..136], semantic alpha.
  Param roles (both defs): x = Primary Scale -> kernel radius (clamped 0..1, so the alias's
  0..2 range saturates as today), y = Secondary Scale -> layer-2 scale, z = Feed Rate -> feed in
  0.03..0.07, w = Vein Glow -> bioGain (clamp 0..1.5 / 1.5; alias max 1.0 just reaches less).
  Alias defs differ (alias: x default 1, max 2; w default 0.5, max 1) — no new idea reads a
  param outside its existing role, so both saved sets behave as before plus the ideas.
MECHANISM INTERROGATION:
  t1 (deepen the kernel): the RD step uses a 5-point Laplacian (mean of 4 - centre) — axis-biased,
    so veins favour 0/90 degrees. The next-better operator of the same stencil family is the
    isotropic 9-point (Mehrstellen) Laplacian, normalised to the same h^2 coefficient (0.25) so the
    Primary Scale -> diffusion relation is unchanged.
  t2 (physics one step further): in Gray-Scott, growth happens where the reaction a*b^2 peaks —
    the advancing tips/fronts of veins; real vascular sprouting is brightest at tip cells.
  t3 (promote an intermediate): `reaction = a*b*b` is computed inside turing_pattern and thrown
    away; multi_scale_turing's .w just echoes `feed` and is unused.
  t6 (history the shader owns): C is read as colour history but through a FILTERING sampler
    (floor violation). With an exact textureLoad, last frame's vessel luminance is the "flow" a
    vessel carried — vascular remodelling: vessels that carried flow persist, unused ones regress.
ADD (3 native ideas):
  1. Isotropic 9-point RD stencil (§12.2D "Isotropic 9-point Laplacian") in turing_pattern for both
     activator and inhibitor — vein branching loses its axis bias.
  2. Reaction-front sprouting tips — reaction a*b^2 of the coarse + fine layers returned via the
     unused .w slot; normalised and gated by the vein ridge, it lights growing vein tips in the
     activator green, gain from Vein Glow (bioGain).
  3. Flow-driven vessel remodelling — exact C luma feeds a small extra activator into veinsRaw
     where a vessel was lit last frame, and the history blend is held a little longer on ridges,
     so established vessels persist while new branches fade in.
FLOOR: exact textureLoad on C (was textureSampleLevel with u_sampler); clamp -> ACES on display RGB
  (writeTexture); A keeps the linear clamped colour history so C is read the same way;
  depth gets a truthful vein relief instead of 0.
FORBID on this file: springs, click shockwaves, IQ cosine palette, scanlines, a different RD model
  (no swap of Gray-Scott constants), new params.
A PACKING: linear (pre-ACES, clamped 0..2) colour history RGB + semantic alpha; C read as colour.
```

---

---
<!-- group B (cards and NOTES inline) -->
# Batch B — Idea Cards (written before WGSL edits, 2026-10-19)

Files: gen-nebular-chrono-astrolabe, gen-murmuration-phantom, spore-galaxy, aurora-curtain.
§12.2 rows used (each on one file only): §12.2E step-count AO (astrolabe); §12.2F Beer–Lambert
(spore-galaxy); §12.2E golden-angle layout (spore-galaxy). Murmuration and aurora use no row.

## gen-nebular-chrono-astrolabe

```
SHADER: gen-nebular-chrono-astrolabe
IDENTITY (one sentence): a raymarched brass astrolabe — glowing core sphere, up to 5 gimballed
  rete rings and a box satellite pointer — inside a domain-warped, Strömgren-stratified nebula,
  with a sprung-mouse gravity well and click gravity rings.
KEEP VERBATIM: map() (gravity well, curl warp, core sphere, ring loop with Keplerian gearing,
  smin, satellite); raymarch() (0.8 under-relaxed, glow accumulation, Beer transmittance);
  sampleNebula() 8-sample Strömgren emission; material colours per mat id; spring in
  extraBuffer[133..138]; click gravity rings; 4% exact-C history; param roles
  (x rotation speed, y ring count, z glow, w gravity well).
MECHANISM INTERROGATION:
  t1 (deepen the kernel): the marcher only returns distance/material; the same march also knows
    how hard it had to work (iteration count) — a free occlusion estimate.
  t2 (physics/device one step further): a real astrolabe's rete and limb are engraved with a
    degree scale (5° minor, 30° major ticks); the rings here are smooth tori.
  t3 (promote an intermediate): map() computes each ring's local frame `pr` (after both gimbal
    rotations) and throws it away; its azimuth atan2(pr.z, pr.x) is exactly the limb angle the
    graduations need, and it rotates with the gearing. raymarch's loop count is discarded too.
  t6 (history): C is display colour blended at 4%; no extra continuity needed for these ideas.
ADD:
  3. Engraved limb graduations — 5° minor / 30° major ticks cut into each rete ring, read from
     the ring-local azimuth map() already computes, so the scale turns with the Keplerian gearing;
     grooves darken the brass, major ticks catch a gilded fresnel glint.
  4. March-count crevice occlusion (§12.2E step-count AO, march-count form) — the raymarch's own
     iteration count darkens where the rings smin into the core and where rings cross.
FORBID: new springs, ripple shockwaves, IQ palettes, new rings/primitives, changing gearing.
A PACKING: ACES display RGBA in A (unchanged; C read as colour history).
```

NOTES
- Kept verbatim: everything listed above; Ideas 1–2 (Keplerian gearing, Strömgren emission) untouched.
- A packing: ACES display RGBA in A (unchanged).
- §12.2 rows: §12.2E step-count AO (march-count form).
- Idea 3: map() ring loop stores the ring azimuth in `g_ringAz` (private) when a ring wins;
  main() shading branch `mat >= 2.0 && mat < 5.0` applies the graduations.
- Idea 4: raymarch() counts steps into `g_steps`; main() hit branch multiplies `col` by `occl`.
- Floor fix: `exp(-pow((r - stromgren) * 1.3, 2.0))` had a possibly negative pow base → `sd*sd`
  (identical value).

## gen-murmuration-phantom

```
SHADER: gen-murmuration-phantom
IDENTITY (one sentence): a dark starling murmuration — curl-noise-advected flock silhouette
  morphing sphere→torus→wave→fbm against a twilight gradient, with silver edge glints, predator
  disturbance under the pointer and click scatter.
KEEP VERBATIM: curl/pot flow, scale-free correlated turn, shape morph chain, golden spiral mask,
  fbm density; Ideas 1–4 (banking agitation, marginal opacity, scale-free turn, heading-defect eye);
  palette (indigo/violet/sunset/silver); trail decode densityFromCoverage(C.a); param roles
  (x flock size, y shape morph, z glint, w cohesion).
MECHANISM INTERROGATION:
  t1 (deepen the kernel): density is a continuum field everywhere; the real flock is a point
    process — continuous only where birds overlap. The next-better model of the same density is
    a Poisson-ish bird count per cell with probability = density.
  t2 (physics one step further): at the thin fringe of a murmuration individual starlings resolve
    against the sky; in the core they merge. Also: the dark "smoke" a flock leaves is carried by
    the same air flow the birds steer in, not frozen in place.
  t3 (promote an intermediate): `flow` (curl velocity) and `density` are already computed; flow
    is only used to warp p, never to move the trail.
  t6 (history): C.rgb is colour history and C.a is decoded as trail density — but it is read at
    the same pixel, so the trail never drifts. Reading C at the flow back-trace gives a drifting
    wake without changing the packing.
ADD:
  5. Fringe birds resolve — in the thin margin (low density), the continuous density is replaced
     by individual bird specks on a jittered grid in flock space, each present with probability
     ∝ density; the core stays continuous.
  6. Flow-carried wake — C (colour + trail density) is fetched at the flock-flow back-trace
     (semi-Lagrangian, exact textureLoad, ≤3 px), so the trail streams with the curl flow.
FORBID: springs, new ripples, IQ palettes, boids solver, changing shape chain or palette.
A PACKING: ACES display RGBA in A (alpha = sky coverage 1−T + glint/scatter; C.rgb colour
  history, C.a decoded as trail density) — unchanged.
```

NOTES
- Kept verbatim: all of the above; Ideas 1–4 untouched.
- A packing: unchanged.
- §12.2 rows: none.
- Idea 5: main(), after the heading-defect eye, before the glint `dx` (search `Idea 5`).
- Idea 6: main(), trail block — `prevTrail` load coordinate now back-traced by `flow`.
- Floor: `col` clamped ≥0 before huePreserveClamp/ACES (chroma offset could push blue negative).

## spore-galaxy

```
SHADER: spore-galaxy
IDENTITY (one sentence): a glowing log-spiral galaxy of 2–8 swirling arms over a drifting
  jittered grid of spores and hashed dust, blackbody-tinted, fogged by radius, with click spore
  burst rings and star-trail feedback.
KEEP VERBATIM: arm angle/phase/armCore formula, slider contract (x arms+sharpness, y swirl+rotation
  +trail persistence, z spore density+gate, w nebula dust+fog); jittered spore grid + gate;
  dust hash; blackbody warm/cool; palette+OkLab arm hue; Beer fog; burst rings; hue-preserve
  clamp → ACES → dither; premultiplied gamma writeTexture; A = linear display colour, B = masks.
MECHANISM INTERROGATION:
  t1 (deepen the kernel): armDist = |armPhase − 0.5| folds the arm profile symmetric; the signed
    phase offset (which side of the crest) is computed and thrown away.
  t2 (physics one step further): real spiral arms are density waves — dust lanes sit on the
    upstream (concave) edge and absorb/redden the arm light; young clusters ignite just downstream
    as the wave sweeps through gas. Spores here are the "young stars".
  t3 (promote an intermediate): the signed arm offset (armPhase − 0.5) and the spore grid already
    exist; the arm sweeping over a fixed spore grid is exactly the density-wave geometry.
  t6 (history): C is display colour but was read with a filtering sampler — fix to exact
    textureLoad; no extra continuity needed.
  name: "spore" — a sporangium/puffball releases spores from a phyllotactic cap.
ADD:
  1. Wavelength-dependent dust lane (§12.2F Beer–Lambert) on the upstream edge of each arm,
     τ ∝ Nebula (the slider's existing "dust amount" role), extinction stronger in blue
     (interstellar reddening).
  2. Density-wave spore ignition — spores just downstream of the arm crest flare and cool toward
     the blue blackbody, so arms visibly light spores as they sweep over the grid.
  3. Golden-angle sporangium core (§12.2E golden-angle layout) — the bulge resolves into a slowly
     spinning phyllotactic cap of spore seeds (θ = i·2.39996, r = c·√i), fading outward.
FORBID: springs, extra ripple systems, new IQ palettes, replacing the spore grid or arm formula.
A PACKING: A = linear hue-preserved display colour (pre-ACES, ≤4 lum) + alpha, read back as colour
  history via exact C; B = (armCore, spore, dust, burst) masks — unchanged.
```

NOTES
- Kept verbatim: all of the above.
- A packing: unchanged (A colour, B masks — HEAD already owns B, documented).
- §12.2 rows: §12.2F Beer–Lambert; §12.2E golden-angle layout.
- Ideas 1–2: main(), right after armCore/armBand (signed `armSigned`), applied in HDR accumulation.
- Idea 3: `sporangium()` helper, called in main() after spore/dust.
- Floor fixes: C read with `textureSampleLevel` → exact `textureLoad`; audio clamped; per-arm
  "FFT" read `plasmaBuffer[1..8]` (never written by the host — only [0] is) → per-arm voice from
  plasmaBuffer[0].xyz (bass/mids/treble by arm index), keeping the July per-arm intent truthful;
  burst ring compared 0..1 uv with a centred click position → both centred/aspect (ring now
  centred on the click); `pow` bases guarded (OkLab cube roots, final 1/2.2 after dither).

## aurora-curtain

```
SHADER: aurora-curtain
IDENTITY (one sentence): stacked auroral curtains whose altitude sets the emission colour (red top,
  green, blue/pink bottom) via OkLab, folded by Kelvin–Helmholtz waves and domain warp, with
  treble ray bands, blackbody stars, sky scatter and a mouse-dragged magnetic zenith.
KEEP VERBATIM: layer loop (count = p1, flow speed = p2, width = p3, colour shift = p4); KH fold
  formula; altitude → colour OkLab ramp; ray bands; blackbody shift; rim; stars; atmos/moon/Mie;
  depth extinction; C trail mix; hue clamp → ACES → gamma → chroma shift; alpha compositor.
MECHANISM INTERROGATION:
  t1 (deepen the kernel): the curtain profile is symmetric (smoothstep of |p.y − curtainY|);
    the signed offset is thrown away.
  t2 (physics one step further): precipitating electrons stop at a fairly sharp altitude, so a real
    curtain has a sharp LOWER border and a long, field-aligned rayed glow UPWARD; in strong events
    the lower border gets a magenta N2 fringe (type-B aurora). The red O(1D) 630 nm line is
    metastable (~110 s) while green O(1S) 557.7 nm decays in ~0.7 s, so red lingers after green moves.
  t3 (promote an intermediate): signed `p.y − curtainY`, `rayBands`, `layerIntensity` exist.
  t6 (history): C is display colour history mixed into HDR; a per-channel decay on the same read
    gives the red afterglow without changing packing.
ADD:
  1. Sharp lower border, rayed upper tail — profile becomes asymmetric: crisp below, exponential
     upward tail modulated by the existing ray bands (field-aligned rays).
  2. N2 pink lower fringe — a thin magenta/purple border just under each curtain, scaled by
     layer intensity and bass (type-B aurora).
  3. O(1D) red afterglow — C history decays per channel (red slow, green fast), so curtains
     leave a lingering red trail where they moved.
FORBID: springs, IQ cosine palette, full-screen concentric rings, scanlines, new click systems.
A PACKING: display RGBA (premultiplied, gamma) in A; C read as colour history — unchanged.
```

NOTES
- Kept verbatim: all of the above.
- A packing: display RGBA (premultiplied gamma) in A, C.rgb colour history, C.a trail weight — unchanged.
- §12.2 rows: none.
- Ideas 1–2: layer loop, replacing the use of `dist`/`glow` (search `Idea 1`, `Idea 2`).
- Idea 3: trail block (`decay` → per-channel `decayRGB`).
- Naga fix: second `let aspect` (redefinition) removed; reserved-style `__finalRGB` renamed.
- Overlay removal (flag for coordinator): a prior pass appended a full-screen concentric
  `clockRings` IQ-cosine `spectral` rainbow on top of the ACES output (§4.3 generic overlay, not
  aurora). Removed; the click fronts that rode it are kept and now emit the oxygen-green line
  into HDR before ACES (so mouse-driven stays truthful). Output clamped; ACES input clamped ≥0.
