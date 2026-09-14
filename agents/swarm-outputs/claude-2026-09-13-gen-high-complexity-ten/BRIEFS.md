# BRIEFS — claude-2026-09-13 higher-complexity generative ten

Claimed IDs (do not run another agent on these):
gen-kaleidoscopic-synapse-bloom, gen-kinetic-neo-brutalist-megastructure, gen-klein-bottle-walk,
gen-kryonic-quantum-aether-fractal-core, gen-liquid-cathedral-dream, gen-liquid-crystal-hive-mind,
gen-liquid-metal-cymatic-resonator, gen-liquid-neon-cyber-metropolis, gen-liquid-neon-topography,
gen-liquid-rainbow-glass

Idea Cards are written to cards/<id>.md before each WGSL edit and collected here at closeout.

---

## gen-kaleidoscopic-synapse-bloom

# Idea Card — gen-kaleidoscopic-synapse-bloom

```
SHADER: gen-kaleidoscopic-synapse-bloom
IDENTITY: a folded-sector neural mandala — radial axon pulses, counter-rotating dendrite web and bridge sparks — twisted by a held drag, with click inoculation rings and a radially-dragged colour history.
KEEP VERBATIM: sector fold (5 + floor(density*8)), axon/branch/runner/nodes formulas, counter-rotating dendrite web + synapseBridge, click ring loop, drag tangent twist, cosine palette hue chain, radial historyLoadUV mix, alpha/depth formulas, ACES, slider roles (x Bloom Density, y Pulse Speed, z Neural Warp, w Color Flux), saved params.
EXISTING IDEAS (2026-08): 1. radial axon runner fronts; 2. counter-rotating dendrite web with synapse bridges.
ADD:
  3. Refractory wake — tissue the axon runner front has just passed is dimmed (action-potential refractory period) and recovers with distance behind the front, so pulses read as travelling depolarisation fronts rather than a uniform glow; bass shortens recovery. Native because it is the existing runnerPhase front, given its physiological tail.
  4. Vesicle release at the synaptic clefts — small quanta dots in the folded (angle, log-radius) lattice that swell and fire where the dendrite web and bridge sparks sit, each on its own continuous release phase, treble-lifted, drifting across the cleft as they fire. Native because the synapse bridges already exist; vesicles are what a synapse releases.
FORBID: spring cursor, new ripple/shockwave systems (the existing click rings stay), new palette function, conveyors, extraBuffer state, dataTextureB, changing the sector fold or replacing the mandala.
A PACKING: ACES display RGBA (unchanged); C read via exact textureLoad as colour history.
```

---

## gen-kinetic-neo-brutalist-megastructure

# Idea Card — gen-kinetic-neo-brutalist-megastructure

```
SHADER: gen-kinetic-neo-brutalist-megastructure
IDENTITY: an endless raymarched grid of swaying concrete blocks (four compound massing types) flown through by a forward camera, lit with GGX concrete, cyan neon server-core buildings pulsing to bass, a mouse repulsion field, fog and colour-history feedback.
KEEP VERBATIM: 4.0 domain repetition, four btype massing compositions (box / slotted box / smin cap / smin side mass), hash-driven height/roughness/neon, GGX+Schlick+Smith shading, neon pulse term, volumetricFog, 100-step march to 50, mouse repulsion push, C colour feedback mix, CA offset, ACES, slider roles (x Block Density, y Repulsion Radius, z Neon Intensity, w Travel Speed), saved updatedParams.
EXISTING IDEAS: none named (June stack was plumbing chunks only).
ADD:
  1. Grinding interlock — the secondary masses (slot cutter, cap slab, side mass) slide along their joint on a per-building phase so blocks visibly grind in and out of each other, with a hot friction seam where the two masses meet; bass nudges the stroke. Native because the description is "colossal blocks that grind and interlock" and these compound SDFs are the interlocks.
  2. Server-core slits — neon buildings get board-form horizontal slits on their vertical faces through which the hidden cyan core shows, with rack LEDs blinking along each slit on continuous per-LED phases (treble-lifted). Native because the description promises "server cores hidden within" and the neon flag already marks them.
FORBID: spring cursor, click ripples, IQ palettes, conveyors, holographic scanlines, replacing the massing types or the camera flight, extraBuffer, dataTextureB.
A PACKING: ACES display RGBA (unchanged); C read via exact textureLoad as colour history. Floor fix: alpha was the material id (0..11) — replaced with coverage/neon semantic alpha; depth now from hit distance.
```

---

## gen-klein-bottle-walk

# Idea Card — gen-klein-bottle-walk

```
SHADER: gen-klein-bottle-walk
IDENTITY: a full-screen parametric (u,v) walk over a Klein-bottle-style tube surface — FBM-textured hue skin,
  finite-difference normal, a slowly orbiting diffuse/specular light, scrolling as time advances the walk.
KEEP VERBATIM: kleinBottlePoint() parametrisation, walkU/walkV = time*speed + uv*2π mapping (0.7 v ratio),
  fbm surface texture, cross(du,dv) normal, orbiting lightDir, hue2rgb colour chain (kb.z / noise / mids hue,
  treble saturation, bass value + radius), semantic alpha formula shape, ACES display.
EXISTING IDEAS: none named (2026-06-06 pass was hygiene: ACES/audio/header).
ADD:
  1. Orientation-reversing seam — every time the walk wraps around v the surface comes back mirror-flipped
     (texture u -> -u, normal inverted so the lit side becomes the unlit side), with a thin incandescent
     glide seam drawn where the flip happens; native because non-orientability is the one thing that makes
     this surface a Klein bottle rather than a torus, and it reuses walkV / the existing normal.
  2. Walker footprint trail — the previous frame is read from C with exact textureLoad a few pixels back
     along the walk direction and its highlights are kept as a decaying streak behind the scrolling surface;
     native because the effect is a *walk*, and the trail follows the existing walkU/walkV velocity.
FLOOR: zoom_params were shifted by one (x unused; Walk Speed slider drove nothing, Light Intensity drove
  texture) — realign to JSON slider names: x Walk Speed, y Texture Density, z Light Intensity, w Color Shift.
FORBID: spring cursor, click ripples, IQ cosine palette, raymarching a different 3D object, conveyors, dataTextureB.
A PACKING: ACES display RGBA (unchanged); C now read via exact textureLoad as colour history.
```

---

## gen-kryonic-quantum-aether-fractal-core

# Idea Card — gen-kryonic-quantum-aether-fractal-core

```
SHADER: gen-kryonic-quantum-aether-fractal-core
IDENTITY: a glacial-blue raymarched fold-and-scale (sorted abs-fold) fractal core slowly tumbling in a black void,
  wrapped in volumetric blue/magenta aether fog; pointer yaws the view and locally melts the core into a smooth sphere.
KEEP VERBATIM: fold() sorted-abs mirror, 5-iteration scale/offset/rotate map(), audio noise shatter offset,
  smin melt sphere under the pointer, 80-step half-step volumetric march + glow accumulation, calcNormal,
  dif/spec/fresnel/chromatic-edge shading, void fog mix, treble tint, t/10 depth, slider roles
  (x Fractal Scale, y Shatter Intensity, z Glow Strength, w Thermal Melt).
EXISTING IDEAS: none named (2026-06-07 pass was header/audio hygiene; no ACES despite the tag).
ADD:
  1. Frost-rime orbit trap — the fold loop's minimum orbit radius is re-evaluated once at the hit point and
     paints icy white rime on the most tightly folded crystal tips, deepening to glacial blue in the recesses;
     native because it is the fractal's own iteration data turned into "hyper-frozen" surface frost.
  2. Aether shatter veins — the minimum distance to the fold's mirror planes (|x-y|, |x-z|, |y-z|, where the
     sorted-abs fold stitches its shards together) becomes thin cyan→magenta plasma cracks, width and brightness
     driven by Shatter Intensity and treble, thawed out inside the pointer melt; native because the description's
     "shatter into luminous aether-plasma shards" happens exactly along these fold seams.
FLOOR: ACES on display RGB (tag claimed it, file lacked it); melt `if` → select with a safe smin k.
FORBID: spring cursor, click ripples, IQ cosine palette, a different fractal (Mandelbox/Menger swap), conveyors, dataTextureB.
A PACKING: ACES display RGBA (C not read; A is display history for the engine).
```

---

## gen-liquid-cathedral-dream

# Idea Card — gen-liquid-cathedral-dream

```
SHADER: gen-liquid-cathedral-dream
IDENTITY: tiers of melting stained-glass arch windows, spires and rose tracery over racing floor caustics, drag-refracted by the pointer, with click rose-window shock fronts and melt-offset colour history.
KEEP VERBATIM: melt warp field, columns/tier cell grid, arch/spire/window/roseTracery/floorCaustic masks, cosine stained-glass palette(), ripple rose fronts, pointer drag refraction + pink drag glow, melt-offset exact C history blend, structure-based alpha/depth, slider roles (x spire density, y melt speed, z refraction, w stained hue).
EXISTING IDEAS: none named (no Ideas: line).
ADD:
  1. Lead cames — each window is divided into leaded panes (radial + tier-ring came lines in window-local polar coords); the lead lines darken the glass and each pane gets its own hue offset, so windows read as real leaded stained glass. Native: this effect is stained glass; cames are how it is built.
  2. Molten glass drips — per-column hashed drips hang below each arch window, lengthening with Melt Speed and bass, their bead tips glowing in the pane colour and feeding the floor caustic. Native: the cathedral is "melting"; drips are the melt made visible on the existing arch grid.
FORBID: springs, extra ripple systems, new palettes (reuse palette()), extraBuffer state, dataTextureB, replacing the arch grid.
A PACKING: ACES display RGBA (C read via exact textureLoad as colour history) — unchanged.
```

---

## gen-liquid-crystal-hive-mind

# Idea Card — gen-liquid-crystal-hive-mind

```
SHADER: gen-liquid-crystal-hive-mind
IDENTITY: a top-down raymarched honeycomb of dark glossy hex-prism walls, each cell filled with curl-noise turbulent iridescent liquid crystal accumulated volumetrically; pointer disrupts/rotates cells, clicks inject chemotactic fronts into a persistent hive-pulse state.
KEEP VERBATIM: opRepHex + hollow sdHexPrism walls, per-cell height pulse with Sync Pulse phase alignment, curlNoise/fbm fluid glow, 80-step wall/fluid march, IQ fluid palette (pre-existing, not new), wall diffuse/spec/rim shading, vignette, click fronts, membrane/alpha/depth formulas, chroma shift + huePreserveClamp + ACES, composite over input, slider roles (x Cell Density, y Fluid Turbulence, z Sync Pulse, w Disruption Radius).
EXISTING IDEAS: none named (June hygiene pass only).
ADD:
  1. Crossed-polariser birefringence — map() exposes the local nematic director angle (from the curl flow it already computes); the fluid accumulation adds Michel-Lévy interference colour, sin²(2θ) extinction times a per-wavelength retardance fringe driven by turbulence and march depth. Native: this is literally liquid crystal; birefringent director textures are how LC looks under polarised light.
  2. Hive relay wave — a cell-quantised signal ring spreads outward from the pointer's hex cell, lighting whole cells in sequence (hex-id distance, paced by Sync Pulse, bass-lifted); it brightens the cell fluid and wall rims and feeds the persistent hive-pulse state. Native: the "hive-mind" synchronises cell-to-cell; it extends the existing Sync Pulse / hivePulse mechanism rather than overlaying ripples.
FORBID: springs, new ripple systems, replacing the IQ palette with another palette, extraBuffer state, dataTextureB, changing the A packing.
A PACKING: raw sim state (unchanged): A.r/g/b = bass/mids/treble envelopes, A.a = hive pulse; C read with exact textureLoad at coord. Not tone-mapped.
```

---

## gen-liquid-metal-cymatic-resonator

# Idea Card — gen-liquid-metal-cymatic-resonator

```
SHADER: gen-liquid-metal-cymatic-resonator
IDENTITY: a fixed-camera, raymarched silver heightfield pool whose surface is a polar Fourier sum of standing waves
  (radial sin x angular cos) forming a cymatic mandala, perturbed by the pointer, with grazing-angle thin-film iridescence.
KEEP VERBATIM: mapHeight polar standing-wave series (resonance base freq, complexity harmonic count, 1/(1.5 i) falloff,
  central peak, smax floor, *0.2 scale), mouse frequency perturbation, getNormal, fixed camera (0,2.5,-2.5), 100-step
  half-step heightfield march, getEnvColor sky + sun, iridescence(), Schlick fresnel f0=0.8, grazing iridescence mix,
  flat-pool darkening by viscosity, gamma. Param roles: x Resonance, y Viscosity, z Iridescence, w Complexity.
EXISTING IDEAS: none named (first idea pass).
ADD:
  1. Real viscosity drag — the file's own comment says Viscosity "can't read history" and fakes it with darkening;
     now the display blends with exact textureLoad(dataTextureC) history weighted by Viscosity (thicker metal =
     slower-settling reflections), keeping the existing pool darkening. Native: it is the slider's literal meaning.
  2. Chladni nodal crystallization — where the standing-wave sum crosses zero relative to its local slope (nodal
     lines of the cymatic plate) the metal "crystallizes" into thin bright filigree with a sharper, cooler specular;
     treble adds glints along the nodes. Native: the description promises crystallizing mandala patterns, and nodal
     lines are exactly where real cymatic sand/particles gather.
  3. Ferrofluid Rosensweig spikes under the pointer — the existing mouse perturbation also raises a small hexagonal
     spike field (ferromagnetic liquid under a magnet) whose height follows bass. Native: the description says
     ferromagnetic liquid and the pointer already acts as the field source.
FORBID: spring cursor, u.ripples shockwaves, IQ cosine palette, conveyors, camera orbit, replacing the Fourier
  heightfield or the iridescence model, dataTextureB.
A PACKING: display RGBA (post-ACES, post-gamma) in A; C read back via exact textureLoad as colour history.
  (HEAD sampled C.r with a filtering call and treated it as "audio" — that was a packing lie; audio now plasmaBuffer[0].)
```

---

## gen-liquid-neon-cyber-metropolis

# Idea Card — gen-liquid-neon-cyber-metropolis

```
SHADER: gen-liquid-neon-cyber-metropolis
IDENTITY: an orbiting aerial view over an infinite repeated grid of dark concrete towers with KIFS crowns, wrapped in
  pulsing neon-vein shells that accumulate volumetric glow, with a pointer gravity warp bending the city apart.
KEEP VERBATIM: map() (gravity warp radius 12 x6, cell repetition, hashed tower heights + audio extrusion, box tower,
  4-iter KIFS crown, neon shell with sin(q.y*14) ripple, smin floor, material pick), calcNormal, orbit camera + mouse
  offset, 160-step 0.75 march with neon glow accumulation, concrete diffuse/amb + radial scan lines, neon hue ramp
  cyan->magenta, concrete sky spec, global bloom, fog. Param roles: x Neon Intensity, y City Density,
  z Audio Reactivity, w Gravity Warp Strength (UI labels Intensity/Speed/Scale/Mouse Influence unchanged).
EXISTING IDEAS: none named (first idea pass).
ADD:
  1. Liquid neon rivers — bright packets of neon flow DOWN each tower's vein shell (per-tower phase from the cell hash,
     speed lifted by bass) and pool as a glowing apron where the vein meets the ground. Native: the description is
     "rivers of hyper-luminescent liquid neon"; today the veins only pulse in place.
  2. Wet-street neon reflections — ground hits cast a short glossy reflection march that re-accumulates the same neon
     glow term the primary march uses, rippled by a cheap puddle normal. Native: liquid neon city at night = wet
     asphalt mirroring the veins; reuses map()/glow accumulation, no new material.
  3. Warp horizon lensing ring — where the gravity warp's 12-unit radius edge lies on the ground, a thin neon event
     horizon ring glows (strength = Gravity Warp slider, mids shimmer). Native: makes the existing pointer warp
     readable instead of adding a new cursor.
FORBID: spring cursor, u.ripples shockwaves, IQ cosine palette, conveyors, different city layout/fractal,
  the generic applyGenerativePrimaryControls shim (removed: shared intensity/speed/contrast shim is below floor),
  dataTextureB.
A PACKING: display RGBA (ACES + gamma) in A. C read as colour history via exact textureLoad for a light neon
  persistence trail (neon-only, bounded).
```

---

## gen-liquid-neon-topography

# Idea Card — gen-liquid-neon-topography

```
SHADER: gen-liquid-neon-topography
IDENTITY: a forward-flying heightfield raymarch over domain-warped ridged-fBm terrain; dark metallic valleys, neon palette ridges with fresnel liquid edge glow and fog; mouse steers camera (x) and height (y).
KEEP VERBATIM: simplex noise + mapTerrain (domain warp 0.4, rotated octaves, 1-|h| squared ridges, *ridgeHeight*0.5),
  getDist floor offset, 100-step rayMarch, getNormal, neonPalette, camera rig (camTime, mx lookAt, my height),
  shading chain (baseColor, ridgeIntensity, fresnel^4, emission, fake SSS, fog), sky glow, slider roles
  (x Ridge Height, y Flow Speed, z Emissive Glow, w Contour Detail = octave count).
EXISTING IDEAS: none (no Ideas: line; file never upgraded).
ADD:
  1. Neon iso-height contour lines — thin glowing topographic contour bands on world height p.y, AA'd by
     distance, spacing densified by Contour Detail, flowing hue along the ridge palette; native because the
     effect is literally a *topography* with a "Contour Detail" slider that today draws no contours.
  2. Liquid neon pooling in the valleys — a flat, bass-lifted fluid level fills terrain below it; pooled
     pixels get a mirror-ish sheen that reflects the ridge palette (fresnel on the flat surface normal) plus
     slow ripple shimmer from the same simplex noise; native because "neon currents carve through" liquid
     terrain — the liquid now settles where the currents cut.
FORBID: springs, u.ripples shockwaves, IQ palette swaps (neonPalette stays as-is, not added), conveyors,
  new raymarch loops, extraBuffer state, dataTextureB.
A PACKING: ACES display RGBA (HEAD blended "history" from readTexture = the input image and sampled
  dataTextureC as fake audio — both packing lies. Now: display RGBA written to A, C read back via exact
  textureLoad as colour history for the existing 0.7 temporal blend; audio from plasmaBuffer[0].xyz).
```

---

## gen-liquid-rainbow-glass

# Idea Card — gen-liquid-rainbow-glass

```
SHADER: gen-liquid-rainbow-glass
IDENTITY: a 2D stack of nine flowing, saturated rainbow liquid layers seen through thick glass — fbm flow
  layers, oil-film interference, refraction-offset layer, chromatic bubbles, edge glow, ribbons, caustics —
  with a mouse-held vortex stir.
KEEP VERBATIM: noise/fbm/fbm3, liquidRainbow, liquidLayer, glassRefraction, oilFilm, vortexStir, all 9 layer
  compositions and weights, post chain (0.85 curve, bloom, saturation push, Sellmeier CA), acesToneMap,
  temporal mix(prev*0.96, color, 0.25), alpha formula, slider roles (x Intensity, y Speed, z Scale,
  w Color Shift), bass/mids/treble mapping.
EXISTING IDEAS: none named (no Ideas: line).
ADD:
  1. Meniscus rims — a bright refractive lip where the thick main liquid (layer 3) meets clear glass: a
     narrow band around layer3.a≈0.5 with per-channel offset bands (R outside, B inside) so the rim itself
     splits into a rainbow; native because the glass/liquid interface is where real refraction and
     dispersion concentrate, and it reuses the layer-3 alpha the file already computes.
  2. Viscous stir memory — the existing (but never displayed) C history is read back advected around the
     pointer by a slow swirl, so a stir leaves a lingering curl in the liquid that relaxes after release;
     native because the effect's one interaction is "mouse stirs the liquid" and liquid has viscosity —
     HEAD computed the temporal field then threw it away.
FORBID: springs, u.ripples shockwaves, new cosine/IQ palettes, conveyors, extraBuffer state, dataTextureB,
  replacing the layer stack.
A PACKING: display-history RGBA (HEAD packing kept: A = mix(prev*0.96, color, 0.25), alpha = effect
  strength); C now read via exact textureLoad (HEAD used filtering u_sampler). Floor fixes: mouse uv was
  divided by resolution a second time (pointer stuck at corner) → use zoom_config.yz directly; depth was
  written as constant 0 → glass thickness from layer coverage.
```
