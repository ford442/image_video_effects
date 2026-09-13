# BRIEFS — claude-2026-09-13 gen mid/high ten

Idea Cards (each written to cards/ before its WGSL edit).

---

## gen-fractal-clockwork

# Idea Card — gen-fractal-clockwork

```
SHADER: gen-fractal-clockwork
IDENTITY: an infinite raymarched checkerboard of counter-rotating brass gears on a floor, orbited by a sprung mouse camera.
KEEP VERBATIM: sdGear (sin-tooth cylinder with axle bore), repeated-cell map with parity-alternating direction, 96-step raymarch,
  shade() brass/steel/gold material thresholds, zoom_params roles (x gear scale, y teeth, z rotation speed, w material),
  sprung orbit camera in extraBuffer[133..138], click-torque ripple rings, temporal C blend, chromatic dispersion.
EXISTING IDEAS (2026-09-06): 1. gear-tooth crest sparks; 2. inter-gear mesh line.
ADD:
  3. Dead-beat escapement tick — gears advance one tooth pitch per tick on top of their continuous turn (stop-go
     stepping fed into map() so geometry, sparks and shading stay in sync), with a brass flash on the tick; native
     because an escapement is literally what makes clockwork tick.
  4. Ruby jewel bearings — a jewel ring around each axle bore on the gear faces with a sharp glint whose
     intensity follows bass; native because real clock movements run their pivots in ruby jewels.
FORBID: IQ cosine palette, new spring/ripple systems (the existing ones stay as-is), fractal/creature swaps,
  holographic scanlines, extra conveyors.
A PACKING: ACES display RGBA (C read back via exact textureLoad as colour history) — unchanged.
```

---

## gen-fractal-ember-lattice

SHADER: gen-fractal-ember-lattice
IDENTITY: triangular/hex crystal lattice with white-hot ember edges over charcoal faces; mouse click shatters it into rigid square shards that fly out and reform (~1.5s), with treble sparks on shard edges.
KEEP VERBATIM: triLatticeDist3 kernel; 5-colour ember palette and hot-ramp mix chain; rigid shard grid + seed/reform state machine (explosion vector, per-shard rotation, 0.987 decay, reform rate); boundary glow, chromatic shard separation, motion streak, treble sparks; semantic alpha formula; CA + ACES + composite over input; slider roles (Glow Intensity, Shard Size px, Lattice Scale, Spark Density); saved params.
EXISTING IDEAS (2026-09-06):
  1. triple-junction glow (all three line families meet -> white-hot node, treble-lifted)
  2. cell-core heat (faces far from every line get a faint inner ember)
ADD:
  3. Heat crawl along lattice lines — bright ember beads travel along each of the three line families (per-line phase from floor() line index, per-family speed, bass-lifted, density follows Spark Density), fused into the edge mask; native because the lattice lines are the heat conductors this effect already draws, and triLatticeDist3 already gives per-family distance.
  4. Shard cooling and re-ignition — a flying shard's lattice glow cools toward deep red/charcoal in proportion to shatterAmt (staggered by the shard seed), and as reform crosses its final stretch a brief incandescent flash re-ignites that shard's edges and junctions; native because it reads the existing seed/reform state (a detached ember loses heat, a rejoined one flares) rather than adding a new field.
FORBID: spring cursor, u.ripples shockwaves, IQ cosine palette, conveyors, new extraBuffer state, dataTextureB, replacing the triangular lattice or the rigid-shard sim.
A PACKING: raw shard state (unchanged): A.rg = displacement, A.b = seed, A.a = reform; C read with exact textureLoad as those fields. Not tone-mapped.

---

## gen-fractured-monolith

SHADER: gen-fractured-monolith
IDENTITY: a tall dark slab, cell-fractured into drifting/rotating shards, levitating and bobbing over a wavy liquid floor, with cyan light accumulating in the cracks; mouse orbits the camera.
KEEP VERBATIM: raymarch (120 steps, t*0.8, 30.0 far), map() SDF (sdPlane floor + wave, sdBox 1.5x4x1.5 base, 1.5 cell grid, hash drift * spread, per-cell rotation, crackNoise carve), crack glow accumulation, mouse camera orbit, floor fake reflection, sky gradient, vignette, C max-feedback (previous*0.82), ACES display packing, param roles (x spread, y levitation speed, z glow, w rotation speed).
EXISTING IDEAS: 1. per-shard identity tint; 2. fracture-plane glints.
ADD:
  3. Seam light pool on the liquid — the crack light leaks down onto the floor beneath the monolith as a pool patterned by the same rotated 1.5 cell grid (bright seams, dark shard shadows), brighter as the bob brings the slab toward the water and wider as Fracture Spread opens the gaps — native because the glow is literally the light escaping through this slab's fractures onto this scene's liquid sea.
  4. Rising seam pulse — a bass-lifted energy band that climbs the monolith's local Y axis and boosts the crack-glow accumulation only where it passes, paced by Levitation Speed — native because it is the existing inner crack light (description: "pulse with an inner, ethereal light"), animated along the slab's own height, not a new overlay.
FORBID: springs, click ripple shockwaves, IQ cosine palettes, conveyors, extra raymarch/shadow inner loops, new materials or a different monolith shape, dataTextureB.
A PACKING: ACES display RGBA (unchanged; C read via exact textureLoad as color history).

---

## gen-ghost-flame

SHADER: gen-ghost-flame
IDENTITY: advected temperature/fuel flame sim rendered through a ghost blue-cyan blackbody palette with a wick column, chemiluminescent ignition band, smoke fringe, cyan age trails and temperature-driven translucency.
KEEP VERBATIM: hash/snoise3/fbm3 kernel; velocityField; advection + Laplacian diffusion + approx vorticity; combustion (ignition 0.15, burnRate from Flame Height); height cooling; base fuel feed; mouse heat + ripple bursts; blackbody/ghostFlameColor palette; smoke/glow/age tint; soft tone map + CA + ACES; alpha curve; slider roles (Flame Height, Turbulence, Cooling Rate, Diffusion); saved params; extraBuffer[133..134] bass/RMS envelopes.
EXISTING IDEAS (2026-09-06):
  1. base wick column (thin Gaussian fuel stem)
  2. ignition chemiluminescence (blue band at ignition temperature)
ADD:
  3. Buoyant puffing pinch-off — a travelling cooling wave along the flame axis (frequency nudged by mids, depth by Flame Height) periodically necks the column so flame packets detach and drift off; native because real buoyant diffusion flames flicker by exactly this ~10 Hz pinch-off, and it acts on the sim's existing cooling term.
  4. Schlieren heat haze — the temperature gradient from the already-loaded 4-neighbour C taps draws faint pale refraction fringes in the cool air around/above the flame (scaled by Diffusion), and depth becomes a truthful thermal relief; native because hot-gas density gradients are what a ghostly flame visibly bends.
FORBID: spring cursor, click shockwave rings, IQ cosine palette, conveyors, new particle system, replacing the palette or sim, dataTextureB use.
A PACKING: raw sim state (unchanged): A = (temperature, fuel, velocityX, age); C read via exact textureLoad as fields. ACES only on writeTexture.

---

## gen-hopf-fibration-fiber-bundle

SHADER: gen-hopf-fibration-fiber-bundle
IDENTITY: 40 Hopf fibers (great circles of S3 over sampled S2 base points) stereographically projected and 4D-rotated into glowing, hue-by-base-point linked loops with crossing bloom, treble specks and click phase-fronts.
KEEP VERBATIM: Hopf lift (z1r/z2r/z2i, psi fiber phase), stereographic projection + rz rotation, 40x32 segment distance loop, hsv hue from (phi, theta), params rotation_4d / fiber_thickness / crossing_bloom / particle_drift and their roles, crossingInt bloom, treble drift specks, click phase-front blooms, A/C display-RGBA feedback blend, alpha formula (alphaAcc*crossing*maxDepth).
EXISTING IDEAS: none (2026-06-06 header had no Ideas: line).
ADD:
  1. Knot-diagram over/under gaps — the nearest fiber at each pixel cuts a dark gap in the strands behind it, so the pairwise LINKING of Hopf circles (the defining topological fact) becomes readable instead of an additive tangle.
  2. U(1) fiber-phase beads — a bright bead travels around each circle at its psi phase (speed = Particle Drift, brightness pumped by bass), visualizing the circle group action that defines each fiber.
  3. Base-space S2 inset — a small orthographic sphere in the lower-left showing the 40 base points in their fiber hues, rotating with 4D Rotation and steered by the pointer, making the projection S3 -> S2 of the bundle explicit.
FORBID: spring cursor, extraBuffer state, IQ cosine palette, new ripple shockwaves beyond the existing click fronts, conveyors, replacing the Hopf lift or projection.
A PACKING: ACES display RGBA (unchanged; C read via exact textureLoad as display history).

---

## gen-hyper-rainbow-vortex

SHADER: gen-hyper-rainbow-vortex
IDENTITY: multi-layer neon rainbow spiral vortex around a mouse-steered Rankine core, with hot singularity glow and counter-rotating arms.
KEEP VERBATIM: 4 spiralArm/interference layers, neonRainbow + hsv2rgb palettes, Rankine swirl (coreR = 0.2+bass*0.1, omega = 2+mids*3), mouse secondary vortex, click energy fronts, param roles (intensity / speed / scale / colorShift), A/C = raw HDR display RGBA history.
EXISTING IDEAS (2026-09-06):
  1. Rankine core / irrotational seam glow at r = a
  2. Counter-arm braid beads where spiral1 x spiral2 cross
ADD:
  3. Differential-rotation feedback advection — C history is textureLoad'ed at the back-rotated pixel using the Rankine angular velocity (rigid Omega inside the core, Omega*a^2/r^2 outside), so the core smears as a rigid disc and the outer flow shears into trailing streaks; native because it is the vortex's own velocity field driving its own history.
  4. Cyclostrophic pressure-deficit condensation funnel — Rankine pressure deficit q (2-(r/a)^2 inside, (a/r)^2 outside) condenses a swirl-striated violet-white haze where q passes a bass/intensity dew point, and the same q carves the depth funnel; native because the pressure well is implied by exactly the Rankine profile already in the file.
FORBID: spring cursor in extraBuffer, new ripple overlay, IQ cosine palette, conveyors, replacing the spiral layers or palettes.
A PACKING: raw HDR display RGBA history (pre-ACES), alpha = vortex energy coverage (unchanged).

---

## gen-hyper-refractive-rain-matrix

SHADER: gen-hyper-refractive-rain-matrix
IDENTITY: an orbiting camera raymarching a falling lattice of viscous, smooth-min-merged capsule rain drops that refract a cosine/blackbody sky, with Fresnel rims, surface caustics, pointer repulsion and click caustic rings over HDR temporal trails.
KEEP VERBATIM: map() capsule lattice + 3x3 smin neighbour merge; rainDensity/dropSpeed/fluidViscosity/stormIntensity roles on zoom_params.xyzw; pointer repulsion in world XZ; 100-step march; cosinePalette+blackbody OkLab sky; Fresnel rim + caustics; click caustic rings from u.ripples; raw HDR A/C history; ACES on display only.
EXISTING IDEAS: viscous drop merging (smin), pointer repulsion, treble caustics, click caustic rings, temporal HDR trails.
ADD:
  1. Storm lightning flashes — hash-gated, time-bucketed double-strobe (bass-triggered, rate/brightness scaled by Storm Intensity) that floods the sky with ~11000K blackbody light and back-lights the drops' Fresnel rims; native because the description already promises "storm flashes" and Storm Intensity is the storm, yet no flash exists.
  2. Spectral dispersion in the drops — refract R/G/B with separate eta (spread by Fluid Viscosity and mids) and sample the refraction palette per channel, so drop rims split into prismatic fringes; native because the whole effect is "hyper-refractive" and the refraction step is already there.
  3. Fall-aligned streak history — the C history is read (exact textureLoad) from pixels displaced up along the fall direction by an amount set by Drop Speed, so trails smear into vertical rain streaks instead of static ghosting; native because the rain falls in -Y and the temporal trail is existing machinery.
FORBID: spring cursor in extraBuffer, new ripple shockwave system, replacing capsules with other primitives, IQ palette as a new overlay, conveyors, changing param roles.
A PACKING: raw HDR refractive rain RGB + semantic coverage alpha (unchanged; C read as raw HDR via exact textureLoad; ACES on writeTexture only).

---

## gen-hyper-warp

SHADER: gen-hyper-warp
IDENTITY: two-layer fBm domain warp (q -> r -> val) mapped through two cosine palettes, with a centered radial burst and a stabilized, flow-advected sharpen feedback loop.
KEEP VERBATIM: rand/noise/fbm kernel and octave counts; q/r/val warp chain; two palettes + smoothstep(0.4,0.6) blend; radial burst; stabilizeHistory + cold-start seed; opacity 0.85 blend, CA, vignette; slider roles (Intensity=warp amp, Speed=time mult, Scale=palette freq/hue, Detail=feedback mix); saved params.
EXISTING IDEAS (2026-09-06):
  1. first-warp fold caustics (mid-range |q-0.5| band brightens)
  2. second-layer flow stretch (|r-q| shear adds mid-palette glow)
ADD:
  3. Warped level-set etching — thin anti-aliased isolines of final_val (count follows Scale) darken/brighten as contour engraving; native because the level sets of the warped fBm scalar are the literal structure the warp chain bends.
  4. Flow-dispersed feedback — the flow-advected history is loaded per channel with red lagging and blue leading the green tap along the flow direction (spread grows with flow speed and bass), so the reaction-diffusion echo splits into prismatic trails along the warp flow; native because it extends the existing flow-advected C read rather than adding a new field.
FORBID: spring cursor, click ripple shockwaves, new IQ palette, conveyors, replacing fBm with another fractal, touching dataTextureB/extraBuffer.
A PACKING: raw HDR history RGBA (unchanged): A.rgb = pre-ACES chromatic, vignetted color clamped [0,6]; A.a = coverage alpha. C read with exact textureLoad as rgb history.

---

## gen-hyperbolic-crystal-symbiosis

SHADER: gen-hyperbolic-crystal-symbiosis
IDENTITY: Poincare-disk crystal garden — 7 hyperbolic Voronoi seeds over a p-fold reflection tiling, cosine jewel coloring, bright facet borders, treble growth-front runners, click fronts, disk-edge vignette and drifting HDR trail history.
KEEP VERBATIM: hash12/hash22, hyperbolicTranslate (Mobius), hyperbolicDist, hyperbolicTiling (p = 5..7 from competition, 8 reflection iters), crystalFacet 7-seed hyperbolic Voronoi, jewelColor, mouse focus Mobius translation, audio curvature, front wave / edge glow / tiling edge / growth front / ripple click fronts, vignette, drifting exact C history mix, alpha/depth formulas as base; slider roles (Growth Speed, Competition, Curvature, Mutation); saved params.
EXISTING IDEAS: none (never received an idea pass).
ADD:
  1. Hyperbolic growth zoning — concentric growth bands around each facet's winning seed, spaced evenly in hyperbolic distance (so they crowd toward the ideal boundary like Circle Limit), with Mutation jittering band spacing per seed and bass pushing the zones outward; native because it is the crystal-growth record measured in the effect's own metric.
  2. Symbiotic twin lamellae — crystalFacet now also reports the runner-up seed id; in the contested band between two seeds, thin alternating stripes (indexed by minD+secondD, a hyperbolic level set parallel to the border) interleave both seeds' jewel colors, width/reach from Competition; native because it is the literal "symbiosis" of two competing crystals meeting (polysynthetic twinning).
  3. Hyperboloid lift relief — each pixel is lifted onto the hyperboloid sheet (z = (1+r^2)/(1-r^2) inverted to a dome height), giving a truthful depth and a facet sheen from the lift gradient combined with growth-zone ridges; native because the Poincare disk is a projection of that surface.
FORBID: spring cursor, new ripple shockwaves, IQ palette swaps, conveyors, extraBuffer state, dataTextureB, replacing tiling/Voronoi with another fractal.
A PACKING: raw HDR display-history RGBA (unchanged meaning): A.rgb = pre-ACES temporal color clamped [0,6.5], A.a = coverage alpha. C read with exact textureLoad as rgb history. Outside-disk path now goes through the same single write set (no early return).

---

## gen-hyperbolic-tessellation

SHADER: gen-hyperbolic-tessellation
IDENTITY: Poincare-disk kaleidoscope tessellation — Mobius-translated, rotating disk folded 8x by sector symmetry, palette colored by recursive depth, with a glowing ideal boundary circle.
KEEP VERBATIM: 13 bindings; Mobius translation (drift / held mouse); rotation; 8-step angular fold + scale recursion; palette(depthPhase); tilePulse; boundary glow; click ripple rings; C feedback blend (raw HDR in A/C, ACES on display only); params tileSymmetry / depthColor / rotationSpeed / boundaryGlow.
EXISTING IDEAS (2026-09-06):
  1. Kaleidoscope ideal vertices at fold corners
  2. Horocycles (constant hyperbolic radius rings from origin)
ADD:
  3. True {p,5} geodesic edges via repeated circle inversion — p = the existing symmetry count; each tile edge is a circle orthogonal to the unit circle (the defining line of a Poincare-disk tiling), drawn with Jacobian-corrected width so edges thin toward the ideal boundary exactly as the hyperbolic metric demands.
  4. Escher two-coloring from inversion parity — every inversion crosses to a neighbouring tile, so odd/even parity alternates tile hue (checkerboard of the hyperbolic tiling), strength on Depth Color.
FORBID: spring cursors, extraBuffer state, IQ-palette swaps, new sim, changing fold recursion or modes, new params.
A PACKING: raw HDR tessellation RGB + coverage alpha in A (C read as exact textureLoad raw history); ACES on writeTexture only. Unchanged.
