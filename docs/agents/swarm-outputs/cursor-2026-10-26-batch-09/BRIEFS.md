# Idea Cards — cursor/batch-09 liquid, ferrofluid, fluid (2026-10-26)

Written before WGSL edits. Twelve shaders. Each card adds **two** new ideas. Earlier ideas stay. Saved `params` stay byte-exact. No shared spring, ripple stamp, or IQ palette.

Formula cap: MacCormack on `liquid-warp-interactive` and `hyper-tensor-fluid` only. Surface-tension rounding on `honey-melt` and `ferrofluid` only. Every other §12.2 row is on one file.

Seven pasted headers are migrated to `#include "_prelude.wgsl"` as infrastructure (`liquid-warp-interactive`, `ink-bleed-fluid`, `liquid-swirl`, `ferrofluid`, `hyper-tensor-fluid`, `sim-fluid-feedback-coupled`, `mouse-fluid-coupling`). That swap is not the upgrade.

---

## liquid-tensor-vortex

IDENTITY: a spectral, divergence-free metal film whose velocity-gradient tensor paints Q-criterion cores and principal-strain ridges, with a Rankine pointer vortex.

KEEP VERBATIM: 6-wave `spectralTensorFlow`; Rankine core and circulation; analytic Jacobian plus pointer finite differences; Q, strain eigenvalues, principal axis; surface-tension cohesion on the displacement; metal cosine from vorticity; click rings; params flow scale / surface tension / specular / transmission. A stays display RGBA.

MECHANISM INTERROGATION:
- tactic 1: the Jacobian is already exact. The missing operator is the pressure it implies.
- tactic 2: a vortex core is a pressure well, so the film sags and the eye darkens.
- tactic 3: `principal` is computed and used only as a chromatic offset. It is also the stretch direction of a material line.
- tactic 6: C is display history. No new field.

ADD:
1. Q pressure-well dimple — tilt the existing normal toward the vortex eye where Q > 0 and darken the plate there. Surface tension still only scales cohesion and the specular power.
2. Stretch filaments — thin threads along `principal`, gated by the existing anisotropy ridge.

FORBID: a new solver, a spring, an IQ palette swap, Gray-Scott.
A PACKING: ACES display RGBA (unchanged).

---

## liquid-warp-interactive

IDENTITY: RK2 spectral-curl warp of the photo, sucked and spun at the pointer, attached to depth silhouettes (Coanda), with strain caustics and viscous C memory.

KEEP VERBATIM: 4-wave `spectralFlow`; RK2 midpoint; tangent stir and held radial suck; depth-gradient Coanda mix; strain caustic; viscosity as the C memory weight; B = (vorticity, shear, boundary, caustic). Params distortion / flow speed / flow scale / viscosity.

MECHANISM INTERROGATION:
- tactic 1: the history sample is one forward semi-Lagrangian step.
- tactic 2: flow that attaches to a silhouette leaves a meniscus on that edge.
- tactic 3: `boundary` is computed and only tints a flat green. It can peak as a waterline.
- tactic 6: C is display color. One back-sample sharpens it without a new packing.

ADD:
1. MacCormack corrector on the viscous history (§12.2D) — forward sample at the departure, back sample one step further, clamp to the three-tap neighborhood. Viscosity still sets the mix.
2. Coanda waterline — a bright bead peaked on `boundary`, modulated along the depth tangent the shader already uses.

FORBID: replacing the spectral field, a spring, dye packing in A.
A PACKING: ACES display RGBA. B aux unchanged.

---

## ink-bleed-fluid

IDENTITY: mouse-painted ink advected by a tiny velocity/pressure solver on paper, with capillary spread into the paper and a wet rim.

KEEP VERBATIM: A = (vel.xy, pressure, ink density); semi-Lagrangian backtrace; Jacobi pressure; the existing vorticity kick; mouse brush and click injection; paper capillary; wet-edge darkening; params hue / viscosity / spread / density. ACES on display only.

MECHANISM INTERROGATION:
- tactic 1: viscosity is a 5-point stencil, so bleed prefers the axes.
- tactic 2: real ink granulates into paper pits. The paper noise is already computed and only scales absorption.
- tactic 3: `valley` is the paper pit and is only a spread weight.
- tactic 6: C is the sim state. Do not store display in A.

ADD:
1. Isotropic 9-point viscosity (§12.2D) — same viscosity coefficient, 20% of the stencil from the corners, scaled so the param still means the same diffusion.
2. Paper-pit granulation (§12.2C) — where ink is present, pits darken the pigment. Display only, so density does not run away.

FORBID: a new pigment solver, springs, replacing the brush with particles.
A PACKING: raw vel.xy, pressure, ink density (unchanged).

---

## rain-ripples

IDENTITY: rain on a photo — click rings, Voronoi drops, FBM micro-ripples, caustics and thin film on wet patches, spring pointer.

KEEP VERBATIM: cosine click ring (speed, wave width, decay); Voronoi drop displacement; domain-warped micro-ripples; caustics; thin film; wet mask; spring in `extraBuffer[133..138]`; params intensity / speed / scale / detail. A stays HDR display history.

MECHANISM INTERROGATION:
- tactic 1: each click is one front. A pond ring is a train.
- tactic 2: the drop rebounds as a Worthington jet at the impact point.
- tactic 3: `cell.x` / `cell.y` are the drop distance and id, used only for a sine warp.
- tactic 6: C is color history. The train does not need new state.

ADD:
1. Dispersive ring train (§12.2D) — two slower, narrower fronts trail the primary click ring. Detail (p4) scales the train. The primary amplitude is unchanged.
2. Worthington jet — a bright bead at the Voronoi center, phased by the cell id, scaled by Scale (p3) which already owns the drops.

FORBID: a height-field solver, removing caustics or the film, a second spring.
A PACKING: ACES display RGBA; A stores pre-ACES HDR as HEAD did.

---

## liquid-swirl

IDENTITY: a spring-followed Lamb-Oseen vortex with a counter-rotating satellite pair, midpoint transport, and strain caustics.

KEEP VERBATIM: `oseenVelocity`; three-vortex `flowField`; spring `extraBuffer[133..136]`; midpoint step; strain caustic from the analytic tensor; click wakes; params strength / radius / smoothness / auto rotation.

MECHANISM INTERROGATION:
- tactic 1: Oseen's tangential speed peaks at r ≈ 1.121 core radii. The shader never marks that eye wall.
- tactic 2: a vortex pair has stagnation points where the braid cancels.
- tactic 3: `caustic` (high shear) and `length(flow)` (speed) are both computed. Their overlap is the stagnation.
- tactic 6: C is display history. Leave the mix alone.

ADD:
1. Oseen eye wall — a thin ring at 1.12091 × the core radius (the radius param).
2. Pair stagnation beads — bright where shear is high and speed is low, the braid point between the three vortices.

FORBID: replacing Oseen with noise curl, a new palette as the look, moving the spring.
A PACKING: ACES display RGBA (unchanged).

---

## honey-melt

IDENTITY: a hex comb that stays solid until the cursor melts it into sagging amber honey with subsurface scattering.

KEEP VERBATIM: hex grid; melt from radius and softness; gravity sag; honey SSS and Beer-Lambert alpha; params cell size / melt radius / distortion / edge softness. The header already named comb-wall capillary; the body never had it.

MECHANISM INTERROGATION:
- tactic 1: the rim test is a dark line, not a wick.
- tactic 2: honey climbs the shared wall, and the melt boundary holds a surface-tension bead.
- tactic 3: `rim`, `len`, and `melt` are the wall and the front.
- tactic 6: C is not read. Do not invent a sim packing. A stays display.

ADD:
1. Comb-wall capillary — partial melt wicks along the hex wall: darker amber, a tangent offset into the fluid UV, thickness held at the rim. Distortion still scales the offset.
2. Melt-front meniscus (§12.2D) — a golden bead on the contour of `melt`, widened by edge softness.

FORBID: a fluid solver, replacing the hex grid, a spring.
A PACKING: ACES display RGBA (unchanged).

---

## magnetic-ring

IDENTITY: three concentric magnetic rings and integer field spokes locked to the cursor, with a wake in C.a and drag-swept spokes.

KEEP VERBATIM: three rings; spoke counts 48/24/16; per-ring FFT bins 2/10/40; wake from exact C; pointer state in texels (0,0) and (1,0); click flux; params base radius / strength / pulse speed / ring thickness.

MECHANISM INTERROGATION:
- tactic 1: each ring is a circle. A moving magnet compresses flux on the leading side.
- tactic 2: a dipole fills the disk with a 1/r³ haze, not only three strokes.
- tactic 3: `vel` and `safeDir` are the drag and the radial. Their dot is the lead.
- tactic 6: A.a stays ring energy. Do not move the pointer texels.

ADD:
1. Upstream flux compression — ring radius shrinks where `dot(safeDir, vel)` is positive.
2. Dipole haze — soft 1/r³ field inside and between the rings, strength still the distortion param, knocked out where the ring stroke already is.

FORBID: a new spring, ferrofluid spikes, changing the spoke integers or the sentinel packing.
A PACKING: display RGB + .a ring energy; texels (0,0) and (1,0) unchanged.

---

## ferrofluid

IDENTITY: image-warping ferrofluid — rosette spikes, rings, and droplet runners around the cursor, with viscous display trails.

KEEP VERBATIM: `domainHeight` rosette and rings; runners; click fronts; hue rotate; C trail along domain motion; params spike scale / attraction / viscosity / color shift. A stays pre-ACES HDR.

MECHANISM INTERROGATION:
- tactic 1: the gaussian envelope kills everything far from the magnet. Zero-field ferrofluid is a labyrinth, not nothing.
- tactic 2: surface tension rounds spike tips into beads instead of cusps.
- tactic 3: height and its four neighbors already exist for the normal.
- tactic 6: C is HDR color. The trail mix stays.

ADD:
1. Labyrinth fingers — a wider maze added outside the spike envelope, gated by `(1 - field)`, folded into the same normal taps.
2. Tip beads (§12.2D) — where the raw height peaks, round the normal and add a softer cap specular. Attraction still owns the field.

FORBID: a raymarched body, replacing the rosette, a spring.
A PACKING: pre-ACES HDR in A; ACES on writeTexture only (unchanged).

---

## hyper-tensor-fluid

IDENTITY: a dye-carrying fluid steered along the image gradient's tangent, with isotropic viscosity, noise turbulence, and a tensor ribbon.

KEEP VERBATIM: A = (velocity.xy, anisotropy, dye); luma gradient and tangent; noise curl; mouse stir; click fronts; spectral tint and ribbon; params tensor strength / viscosity / turbulence / advection speed.

MECHANISM INTERROGATION:
- tactic 1: the viscosity blend treats the four neighbors equally, so the tensor does not actually diffuse along itself.
- tactic 2: dye filaments numerically smear. One corrector step restores them.
- tactic 3: `tangent` is computed and used as a force, then ignored by the blur.
- tactic 6: C is the sim state. MacCormack reads it; it does not become color.

ADD:
1. Tangent-weighted viscosity — the existing four velocity taps, weighted by the tangent so diffusion runs along the edge. Viscosity is still the mix amount.
2. MacCormack dye (§12.2D) — forward dye plus half the (here − back) error, clamped to the three taps, then the same 0.985 fade and source injection.

FORBID: a new tensor field, springs, ACES on the stored velocity.
A PACKING: raw velocity.xy, anisotropy, dye (unchanged).

---

## sim-fluid-feedback-coupled

IDENTITY: a velocity/pressure/dye solver with vorticity confinement, mouse stir, buoyant dye, and schlieren from the pressure field.

KEEP VERBATIM: A = (velocity.xy, pressure, density); one Jacobi pressure step; confinement; buoyancy `velocity.y += max(density - ambient)`; schlieren refraction and knife edge; params viscosity / turbulence / fade / glow.

MECHANISM INTERROGATION:
- tactic 1: divergence is computed for pressure and then discarded. Continuity should move the dye.
- tactic 2: buoyancy without baroclinic torque does not roll the plume up. Density and pressure neighbors are both in hand.
- tactic 3: `divergence`, `right.w/z` are already loaded.
- tactic 6: C stays the sim. Schlieren stays a display bend, not a stored field.

ADD:
1. Shallow-water continuity (§12.2D) — density drops where divergence is positive and piles where the flow converges, before the existing fade.
2. Baroclinic torque — (∇density × ∇pressure) adds a along-isobar kick so the buoyant plumes curl. Clamped with the existing velocity limit.

FORBID: removing buoyancy or schlieren, a spring, display RGBA in A.
A PACKING: raw velocity.xy, pressure, density (unchanged).

---

## mouse-fluid-coupling

IDENTITY: the pointer drags a viscous fluid across the photo; thickness warms and blurs the image; fast motion sheds vortices; clicks inject fluid.

KEEP VERBATIM: viscosity as the decay; stir radius; color absorption tint; vortex strength on the perpendicular kick; click injection; edge damping; A = (vel.xy, vorticity, density). The (0,0) mouse texel was overwritten every frame by the fluid store, so the drag velocity never persisted.

MECHANISM INTERROGATION:
- tactic 1: the "vortex street" in the header is one perpendicular kick inside the radius, not a street.
- tactic 2: a fast stroke lays a thin trail; a slow stroke pools. Density is currently only injected by clicks.
- tactic 3: `mouseSpeed` is computed and only scales the single vortex kick.
- tactic 6: C must be read with `textureLoad`. The filtering sampler on `rgba32float` is illegal. Bilinear is four loads.

ADD:
1. Speed-thinning (§12.2C) — the drag deposits density, thinner as `mouseSpeed` rises, so slow strokes pool and fast strokes leave a thread. Viscosity still decays it.
2. Kármán street — alternating shed vortices in the wake behind the pointer, scaled by vortex strength, quiet when the pointer is still.

POINTER STATE: previous mouse moves to `extraBuffer[133..134]` with a seeded flag at `[136]`, single writer `(0,0)`. A is fluid at every texel, including (0,0).

FORBID: a pressure solver, packing display into A, a second spring model.
A PACKING: raw vel.xy, vorticity, density. ACES on writeTexture only.

---

## gen-abyssal-ferrofluid-singularity

IDENTITY: a raymarched ferrofluid sphere displaced by a gyroid, magnetically warped by a held pointer, with fresnel iridescence.

KEEP VERBATIM: sphere + gyroid `smin`; held mouse warp; orbiting camera; march; params spike density / pulse speed / iridescence / glow. Bass still scales the gyroid. Treble still scales the core glow.

MECHANISM INTERROGATION:
- tactic 1: the march hits a surface and shades it with one Lambert term. The folds have no occlusion.
- tactic 2: ferrofluid tips are high curvature and should take the specular; the creases should go dark.
- tactic 3: `getDist` and the normal are the whole SDF. Curvature is the Laplacian of that distance.
- tactic 6: C is not read. A becomes ACES display, matching the write.

ADD:
1. Step-count AO (§12.2E) — five taps along the normal darken diffuse and the core glow in the gyroid folds.
2. SDF curvature wear (§12.2E) — positive curvature keeps and boosts the specular (spike tips); negative curvature darkens creases.

FORBID: a different primitive, replacing the gyroid, a palette swap as the look.
A PACKING: ACES display RGBA.
