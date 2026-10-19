# Claude bio-cosmic-eight — Idea Cards

Written before WGSL edits. 2026-10-19.

Batch: interactive_neural_swarm, cosmic-jellyfish, gen-quantum-fluorescent-aether-moth-swarm,
gen-chrono-mycelial-tapestry, gen-quantum-mycelium, supernova-core, gen-sentient-void-silk-nebula,
gen-aurora-silk. Seven of the eight pasted the 13 bindings; they were migrated to
`#include "_prelude.wgsl"` first (header-only, not counted). Files that already carry `Ideas:` get a
second pass; their prior ideas stay.

```
SHADER: interactive_neural_swarm
IDENTITY: hash-placed neon neurons on a dark field, joined by proximity axons carrying travelling pulses, drawn toward a sprung pointer
KEEP VERBATIM: getNeuronPos hash constants, O(N^2) connectionStrength, signalWave, spring in [133..137], click wavefronts, activationColor HSV ramp, the four sliders, honest depth
ADD:
  1. Myelinated axons — node-of-Ranvier beads along each axon, and the action potential hops node to node (saltatory) instead of gliding
  2. Synaptic bouton flare — a terminal knob at the receiving neuron that flashes when the pulse arrives
  3. Dendritic spines — short tapered hash-angled spokes around each soma, length breathing with activation
FORBID: new palette, a liquid/RD field, a second spring
A PACKING: display RGBA (ACES) + activation in A.a as before; C unused. Floor: ACES replaces Reinhard, semantic alpha.
```

```
SHADER: cosmic-jellyfish
IDENTITY: a single raymarched translucent jelly with a ribbed bell, ten fine tentacles and four oral arms in a star void, with bioluminescent trails
KEEP VERBATIM: map() SDF (bell / scallop / tentacles / oral arms), camera, click pressure wave, cosine glow palette + Hue Shift, temporal trail in A, ACES + hue-preserving clamp
ADD:
  1. Thickness translucency — a short inside probe along the view ray; thin bell regions transmit the glow colour (back-lit jelly)
  2. Horseshoe gonads — four glowing horseshoe loops inside the bell crown (moon-jelly anatomy), showing through the translucent bell
  3. Rhopalia — eight marginal sense-organ beacons in the scallop notches, blinking in sequence around the rim
FORBID: replacing the jelly, adding a spring, an extra palette
A PACKING: HDR trail RGB + alpha (unchanged)
```

```
SHADER: gen-quantum-fluorescent-aether-moth-swarm
IDENTITY: curl-flow fluorescent moth swarm (noise-threshold blobs) with advected HDR trails, mouse lantern and mandala roost
KEEP VERBATIM: snoise/curl2, spawn field, wing flutter/smear/lantern/roost ideas, HDR feedback via textureLoad, sliders
ADD:
  1. Ocellus eyespots — concentric ring bands inside each moth blob (iso-lines of the spawn noise) with a dark pupil
  2. Shed wing-scale dust — sparse fluorescent glitter deposited where moths fly, then carried by the existing trail advection
FORBID: new creature, spring, ripples
A PACKING: raw HDR RGB + semantic alpha (unchanged)
```

```
SHADER: gen-chrono-mycelial-tapestry
IDENTITY: three generations of 2D hyphal networks (ancient/mid/fresh) overlaid with max-trail persistence
KEEP VERBATIM: myceliumLayer growth, three-layer timing, colours/tint, anastomosis knots, streaming beads, max-trail feedback
ADD:
  1. Rhizomorph cords — the ancient layer reads as a cord: dark melanised core with a bright cortex rim
  2. Chrono-sepia aging — the stored trail drifts toward amber/sepia as it decays, so older growth looks older
FORBID: new solver, spring, ripples
A PACKING: HDR display RGB + coverage alpha (unchanged, C read as max-trail)
```

```
SHADER: gen-quantum-mycelium
IDENTITY: raymarched domain-repeated fleshy hyphal lattice flown through, with septa, fusion bridges, granules, wound rim
KEEP VERBATIM: map() fold/repeat, all four prior ideas, cursor repulsion sphere, sliders
ADD:
  1. Clamp connections — a small hook bulge beside each septum (dikaryotic hyphae), smoothly unioned into the thread
  2. Compartment-quantized pulse — the teal pulse lights whole septal compartments, stepping one compartment at a time
FORBID: new scene, palette swap
A PACKING: ACES display RGBA (C unused)
```

```
SHADER: supernova-core
IDENTITY: 2D supernova — blackbody nickel core, Sedov shells, RT fingers, spectrum rays, companion star, click Sedov rings
KEEP VERBATIM: blackbody/OkLab colour, Sedov radius, decay cycle, ray loop, spring companion [133..134], alpha compositor
ADD:
  1. Light echoes — faint dust-modulated rings beyond the blast, travelling faster than the shock (light on interstellar dust)
  2. Companion shadow cone — the companion star carves a conical hole in the ejecta behind it (Type Ia companion shadowing)
  3. Reverse shock — an inward-travelling shell inside the blast that brightens RT fingers it crosses
FORBID: a pulsar/new object, a palette swap
A PACKING: premultiplied display RGBA (C unused)
```

```
SHADER: gen-sentient-void-silk-nebula
IDENTITY: curl-noise silk field with three-strand braids and tension knots, slow display-history blend
KEEP VERBATIM: curl field, braid, knots, palette, mouse vortex, A/C blend
ADD:
  1. Dew beads — droplets of light strung along each fibril at a regular spacing, sparkling with treble
  2. Void pockets — low-tension regions sink into deep void with a thin lit rim at the pocket edge
FORBID: spring, ripples, new palette
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: gen-aurora-silk
IDENTITY: domain-warped aurora curtains of silk ribbons with satin sheen, warp threads, fold creases, rays and fog
KEEP VERBATIM: wind warp, ribbon bands, satin/threads/crease ideas, grading chain, sliders
ADD:
  1. Field-aligned rays — fine vertical streaks within the curtain (auroral rays along magnetic field lines), flickering with treble
  2. Nitrogen hem — the lower border of each ribbon gets a magenta/pink fringe (N2 emission), the crest keeps green
FORBID: spring, ripples
A PACKING: ACES display RGBA (unchanged)
```
