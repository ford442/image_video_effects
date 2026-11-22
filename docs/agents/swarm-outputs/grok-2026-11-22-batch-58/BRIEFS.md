# Idea Cards — cursor/batch-58 (grok, 2026-11-22)

Cards written before the WGSL edits. Two parts: the multipass nodes whose display pass was already upgraded, and six dense shaders whose contract floor is broken.

No shared spring, shockwave, or IQ palette is added. §12.2 rows are not reused across the batch. Saved `params` on definitions that already have them stay byte-exact. Definitions that only named sliders under `x-meta` gain a top-level `params` array copied from that block.

---

### dla-walkers

```
SHADER: dla-walkers
IDENTITY: sim-ring walkers that drift, stick to a frozen neighbor, and leave a visit trail. The catalog picture is still DLA.
KEEP VERBATIM: workgroup 64×1×1; simState xy / hue seed / alive; A/C (frozen, time, hue, branch); spawn; random step plus pointer/centre pull; freeze-then-respawn; trail stamp on free pixels; no extraBuffer; walker speed / attract / stickiness / branch angle roles
MECHANISM INTERROGATION:
  tactic 1: the stick test is a flat probability on any frozen neighbor. A real aggregate screens fjords.
  tactic 2: growth prefers a small set of facet directions (the branch-angle slider is stored and otherwise unused as a direction).
  tactic 7: the step only sees the cell it lands on. Faster walkers should sense crystal farther away.
ADD:
  1. tip screening — a fjord (many frozen neighbors) sticks less than a tip
  2. branch-angle facets — stick chance peaks on a 2-to-6-fold set of incoming directions
  3. attraction reach — walker speed sets how far a probe looks for crystal, and that direction joins the step
FORBID: extraBuffer; workgroup change; replacing the random walk with an SDF crystal
A PACKING: raw sim (frozen, time, hue, facet angle). This pass does not write display.
```

### dla-render

```
SHADER: dla-render
IDENTITY: seeds the field, draws the frozen crystal and the fading walker trail over the photo, carries the field forward.
KEEP VERBATIM: frame-0 centre seed; ripple seeds; held-pointer seed; hue from st.b; trail fade from st.g; field carried in dataA; attract radius on the pointer seed
MECHANISM INTERROGATION:
  tactic 3: neighborFrozen is already computed and only adds a flat white edge.
  tactic 6: freeze time and the facet angle written by the walkers are in C and barely shown.
ADD:
  1. tip glow — exposed tips (few frozen neighbors) take a cool highlight; the interior stays the body color
  2. facet glint — brightness follows the stored growth angle against a fixed light
  3. growth rings — freeze age lays faint annuli so each shell reads as a generation
FORBID: springs; rewriting the seed rules; ACES on the stored field
A PACKING: raw sim, unchanged meaning. ACES on writeTexture only. Alpha is crystal coverage plus trail, not 1.
```

### physarum-agents-diffuse

```
SHADER: physarum-agents-diffuse
IDENTITY: toroidal 3×3 decay of the trail the agents will sense next, plus click blooms.
KEEP VERBATIM: blur3×3 * keep; torus wrap; TRAIL_CAP; persistence → keep mix(0.80, 0.985); bloom from ripples; .r trail .g last deposit time; frame-0 clear
MECHANISM INTERROGATION:
  tactic 1: the blur is isotropic, so veins fatten sideways as fast as they spread along themselves.
  tactic 6: .g is the last deposit time and is only copied through.
ADD:
  1. sheath anisotropy — cardinal taps aligned with the trail gradient count more than the cross-tube taps
  2. fresh-front sparing — a texel deposited recently decays less, so the growing tip stays while abandoned tubes thin
FORBID: replacing the 3×3; changing TRAIL_CAP; springs
A PACKING: raw trail (.r amount, .g last deposit time). No display write.
```

### physarum-agents-step

```
SHADER: physarum-agents-step
IDENTITY: Jones agents — sense forward/left/right, steer, move on a torus, deposit one shared value per texel.
KEEP VERBATIM: FOOD_W, WANDER, DEP0, TRAIL_CAP, KEEP_DEFAULT; the three-way steer; deposit race (every agent on a texel writes the same value); food is image red; held pointer lure; sense angle / distance / speed / persistence roles; workgroup 64×1×1
MECHANISM INTERROGATION:
  tactic 2: a saturated tube should be left, which is why real physarum doesn't pile into a blob.
  tactic 8: deposit on a texel that is already thick wastes chemoattractant.
ADD:
  1. crowded-tube avoidance — a forward cell near the trail cap forces the existing random U-turn
  2. deposit satiation — the added trail shrinks as the texel is already full, still one value per texel
FORBID: changing the named constants; per-agent deposit values; extraBuffer
A PACKING: raw trail (.r, .g time). No display write.
```

### chromatographic-diffuse

```
SHADER: chromatographic-diffuse
IDENTITY: Jacobi diffusion with a different viscosity per dye channel. Red stays sticky, blue runs.
KEEP VERBATIM: visR / visG / visB from the viscosity-split slider; 5-point Laplacian; temperature copied in .a; clamp to 4
MECHANISM INTERROGATION:
  tactic 2: wet paper saturates, so dense dye moves less. Warm solvent runs farther.
  tactic 4: the temperature field is already in .a and this pass ignores it.
ADD:
  1. paper saturation — diffusivity falls as the local dye mass rises
  2. heat run — the same viscosities scale up with the temperature already stored in .a
FORBID: replacing per-channel viscosity; 9-point stencil (saved for nowhere else this batch); springs
A PACKING: raw dye.rgb + temperature. No display write.
```

### chromatographic-interact

```
SHADER: chromatographic-interact
IDENTITY: dyes drag toward their mean and treble pulls them back apart.
KEEP VERBATIM: drag from the split slider; mean mix; treble on the separation term; temperature copied
MECHANISM INTERROGATION:
  tactic 2: co-eluting dyes compete; the strongest spot displaces the others.
  tactic 1: the mix blurs bands. A chromatogram keeps a sharp front.
ADD:
  1. Rf competition — the peak channel keeps more of itself and suppresses the other two
  2. band edge — a small unsharp against the four-neighbor mean, so spots stay bands
FORBID: a new solver; IQ palette; springs
A PACKING: raw dye.rgb + temperature. No display write.
```

### chromatographic-phase

```
SHADER: chromatographic-phase
IDENTITY: hot dye evaporates, cold dye condenses, vapor is blue-biased.
KEEP VERBATIM: temperature slider on the evaporation amount; cool-region condensation; blue vapor tint; .a stays temperature
MECHANISM INTERROGATION:
  tactic 2: blue is the volatile fraction; red stays on the paper.
  tactic 8: evaporation spends heat. A hot spot should cool as it boils.
ADD:
  1. differential volatility — blue leaves fastest, red slowest, on the existing evaporation amount
  2. latent-heat cooling — the evaporated fraction lowers the temperature stored in .a
FORBID: deleting the blue vapor tint; springs
A PACKING: raw dye.rgb + temperature. No display write.
```

### sph-fluid-density

```
SHADER: sph-fluid-density
IDENTITY: WCSPH density and vorticity on aux records. Positions do not move. The hash is kept.
KEEP VERBATIM: POLY6 / SPIKY / VISIT_CAP / RHO_LO / RHO_HI / OCC_MAX / ACTIVE_MAX; self-term POLY6; grad-W curl; seed droplets; aux (-1,-1, rho, omega); rest-density slider; workgroup 64×1×1
MECHANISM INTERROGATION:
  tactic 2: overlapping neighbors are where the render's compression shimmer should come from.
  tactic 3: omega is one sum. Spin on a free surface is the part the iridescent stamp should keep.
ADD:
  1. collision-core density — a narrow kernel added on top of poly6 when neighbors are inside 0.35h
  2. surface vorticity — omega is attenuated in the over-dense core and kept on the free surface
FORBID: new aux channels; moving hashed positions; changing the named constants
A PACKING: aux record unchanged. No display write.
```

### sph-fluid-force

```
SHADER: sph-fluid-force
IDENTITY: Tait pressure, viscosity, cohesion, vorticity confinement, XSPH, walls, pointer and obstacle drive, then a stamp for the render.
KEEP VERBATIM: the named force constants; pressure / viscosity / cohesion / confinement / XSPH formulas; tide, kick, pointer, ripples, obstacle; stamp channels (.r speed, .g vorticity, .b rho/rho0, .a coverage); integrator and VMAX
MECHANISM INTERROGATION:
  tactic 2: WCSPH clumps when kernels overlap. Monaghan's short-range repulsion is the usual fix and is not in the sum.
  tactic 3: the stamp's speed channel is what the render whitens into foam. Under-dense fast particles are the spray, and the stamp does not know that yet.
ADD:
  1. tensile correction — a short-range repulsion along r-hat when r < 0.5, added beside the pressure term
  2. Weber spray — the stamp's speed channel rises when the particle is fast and under-dense. Velocity is unchanged
FORBID: new bindings; rewriting Tait; extraBuffer
A PACKING: stamp unchanged in meaning. No display write.
```

### gen-luminescent-chrono-fluid-astrolabe

```
SHADER: gen-luminescent-chrono-fluid-astrolabe
IDENTITY: a raymarched astrolabe — limb, rete, ecliptic, alidade — in liquid-gold rings.
KEEP VERBATIM: map / march / graduations / rete / ecliptic / alidade / unequal hours / alidade shadow; Intensity / Speed / Scale / Mouse Influence as 0–1 mixes; spring in extraBuffer[133..138] only; exact C history mix
MECHANISM INTERROGATION:
  tactic 5: a real limb has a 1° vernier beside the 10° and 30° marks. A rete star has a magnitude, not one brightness.
  tactic 3: hash2(cell) is already the star gate and is thrown away as a brightness.
ADD:
  1. vernier ticks — 1° marks, shorter than the 10° marks, on the existing limb face mask
  2. magnitude classes — the same star hash scales brightness from faint to first magnitude
FORBID: new FFT-bin reads; extraBuffer outside 133–138; a different instrument
A PACKING: ACES display RGBA. Unchanged.
```

### gen-sonoluminescent-chrono-geode-matrix

```
SHADER: gen-sonoluminescent-chrono-geode-matrix
IDENTITY: a shattering geode whose core is a collapsing sonoluminescent bubble.
KEEP VERBATIM: shell SDF; shock ignition; agate strata; flash translucency; pearl chains; twinning glints; Rayleigh–Plesset afterbounce; ember blackbody; swirl-advected C trail; Intensity / Speed / Scale / Mouse Influence
MECHANISM INTERROGATION:
  tactic 2: a driven bubble cavity has standing-wave nodes, dark rings, not only a flash.
  tactic 6: the trail in C is the previous flash. Recombination light is warmer than the flash that made it.
ADD:
  1. acoustic nodes — dark rings on the background radius, the cavity mode cancelling
  2. recombination tail — previous-frame luma in C adds a red tail once the flash has passed
FORBID: extraBuffer FFT bins; replacing the bubble cycle
A PACKING: HDR history RGB + alpha in A (ACES on writeTexture only). Unchanged.
```

### gen-lichtenberg-storm

```
SHADER: gen-lichtenberg-storm
IDENTITY: dielectric-breakdown trees with a racing return stroke, etched charge, and a violet corona.
KEEP VERBATIM: licht(); stepped leader, gaps, corona taps, beads; charge in C.g; spring in extraBuffer[133..138]; Branch Jitter / Glow / Storm Frequency / Afterglow; blackbody layers
MECHANISM INTERROGATION:
  tactic 5: a real figure carbonizes the dielectric under the channel. The corona grows streamer hairs, not only a smooth sheath.
  tactic 3: prevCharge and corona are already computed.
ADD:
  1. carbonized track — etched charge darkens the color under a channel the live stroke has left
  2. streamer hairs — sparse high-power specks on the corona, treble-gated
FORBID: extraBuffer outside 133–138; a second lightning system
A PACKING: raw state (energy, etched charge, shock ring, 1) in A. ACES on writeTexture only. Unchanged.
```

### gen-prismatic-void-weaver-ouroboros

```
SHADER: gen-prismatic-void-weaver-ouroboros
IDENTITY: one prismatic serpent biting its own tail, raymarched, with a jaw seam and a keel grating.
KEEP VERBATIM: twist / plasma glow / void gravity / audio reactivity roles; tether; jaw glow; keel grating; C history mix; raw pointer (no spring)
MECHANISM INTERROGATION:
  tactic 2: a mouth that swallows the tail occludes it. The seam currently only adds light.
  tactic 7: qP.y is already the keel side. The trailing side of a scale is darker.
ADD:
  1. swallowed-tail occlusion — color darkens in the jaw gap, beside the existing gold seam
  2. scale trailing shade — the keel's trailing side (negative qP.y) dims
FORBID: extraBuffer; a second creature
A PACKING: ACES display RGBA. Unchanged.
```

### gen-sentient-cyber-chrono-void-serpent

```
SHADER: gen-sentient-cyber-chrono-void-serpent
IDENTITY: a chrono-glass serpent, hex scales, torus rings, Julia rift. Echoes, glints, isochrones, swallowed shard, ecdysis stay.
KEEP VERBATIM: SDF march; echo field; scale glint; rift isochrones; bulge; ecdysis; Time Scale / Plasma Intensity / Void Density / Fracture Depth roles
MECHANISM INTERROGATION:
  tactic 6: A is display color and nothing reads it back. A chrono body should leave last frame's light.
  tactic 2: the ring's spectral band is only a crest. An interference band has a dark node.
ADD:
  1. chrono phosphor — exact load of last frame's display, mixed after tone-map so the body smears in time
  2. spectral node — the chrono-ring band has a dark interference minimum at mid-band
FORBID: a new creature; springs; tone-mapping the stored field twice (mix is after aces)
A PACKING: ACES display RGBA. C is that display, read back.
```

### matrix_digital_rain

```
SHADER: matrix_digital_rain
IDENTITY: layered digital rain. Glyph columns gate each zoom layer; the head shows the photo; trails are green phosphor.
KEEP VERBATIM: five zoom layers; layer speed low/high; edge glow; fog density; rain_cell; chroma split from bass; vortex from the held pointer and the newest ripple; ACES on display
MECHANISM INTERROGATION:
  tactic 6: A is written and never read. Phosphor trails and a decode head both persist for a frame on a real display.
  tactic 3: alpha already tracks glyph brightness, so last frame's alpha is a head latch.
ADD:
  1. phosphor afterimage — last frame's display, exact load, tints the new columns green
  2. decode latch — where last frame's alpha was a head, this frame holds more of that revealed color
FORBID: extraBuffer[0]; a second rain system
A PACKING: ACES display RGBA. C is that display, read back.
```
