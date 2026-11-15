# Idea Cards — Grok (spectral-field ten, 2026-11-15)

Written before the WGSL edits. Ten shaders the user listed by size. Each card adds **two to four** ideas in the existing main path. Saved `params` stay byte-exact. No shared spring, ripple stamp, or new IQ palette.

Formula rule: a §12.2 row is newly applied on at most two files here.

- Cauchy (§12.2F) is new on `cross-spec-alpha-spectral-bloom` and `hyb-spectral-fbm-displace` only.
- Energy-conserving bloom (§12.2F) is the bloom only.
- Beer–Lambert absorption and Fresnel–Schlick (§12.2F) are the photon march only. The fog already had Beer; this pass does not re-apply it.
- Anti-halo envelope (§12.2A) is the guided filter only.
- Block DCT quantization and macroblock motion carry (§12.2B) are `datamosh` only.
- Three-tap step-count AO (§12.2E) is the mycelium only.

`rainbow-vector-field` still pastes the binding header. Migrating it to `#include "_prelude.wgsl"` is infrastructure. It is not an idea and does not by itself bump `Upgraded:`. The pointer fix (mouse uv is `zoom_config.yz`, mouse-down is `zoom_config.w`) is the same kind of floor repair: the old code divided the uv by resolution and used `zoom_config.x`, which is time.

```
SHADER: photon-bins
IDENTITY (one sentence): wavelength-binned photons bend and bounce on the image as a height field, splat into a spectral caustic, and present over a night-dimmed photo.
KEEP VERBATIM: simState packing (xy px, z heading, w bin+energy); graded-index bend; wall reflect; 65k agents; spatial-hash gather of 2×2 cells; persistence in A (rgb energy, a count); spectrum(); night-dimmed composite; params Index Contrast / Dispersion / Light Size / Persistence. Present must not write dataA.
MECHANISM INTERROGATION:
  tactic 2: a graded medium absorbs in the dark, and a wall reflects more at a grazing hit
  tactic 3: the splat loads q.z (heading) and never uses it; the caustic is added as pure light, not light on the photo
  tactic 6: A/C is the spectral accumulator. Present reads C after the A→C barrier. Do not store display in A.
ADD:
  1. Beer absorption — dark ground eats energy each substep (§12.2F). Clear ground keeps the existing 0.9925 decay
  2. Grazing Schlick wall — the existing reflect keeps more energy when the ray is glancing (§12.2F)
  3. Travel-axis splat — the kernel stretches along the heading the gather already loaded
  4. Surface-tinted caustic — the present multiplies the caustic by the source albedo so the light sits on the photo
FORBID on this file: a new solver, writing dataA from present, an oil-slick, a spring
A PACKING: A/C spectral energy rgb + photon count in a (unchanged). Present is ACES display and does not write A
```

```
SHADER: conv-guided-filter-depth
IDENTITY (one sentence): a guided filter whose guide is the depth buffer, with a mouse focus aperture and ripple dents in that guide.
KEEP VERBATIM: radius / epsilon / depth influence / mouse focus; the linear model a*guide+b; luma range weight; photo-edge hold; mouse aperture; ripple depth dents; params Filter Radius / Edge Sensitivity / Depth Influence / Mouse Focus
MECHANISM INTERROGATION:
  tactic 1: the window is a box, and epsilon is one scalar for flat depth and noisy depth
  tactic 2: the guided result can ring outside the samples it just averaged
  tactic 3: varGuide is computed and only used in the denominator
ADD:
  1. Spatial Gaussian — taps already in the window fall off from the centre. Radius still sets the window
  2. Variance-scaled epsilon — noisy depth (high varGuide) regularizes more; the epsilon slider still scales it
  3. Anti-halo clamp — the guided colour stays inside the window's min/max (§12.2A)
FORBID on this file: a new spring, a palette, replacing the guided model
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: datamosh
IDENTITY (one sentence): 8×8 macroblock P-frame smear with I-frame resets, a chroma ghost, and pointer scrub.
KEEP VERBATIM: A = (motion, age, strength); I-frame reset from the block gradient; chroma ghost from per-pixel C; phase-edge block snap; spring scrub and click fronts already in the file; params Motion Strength / I-Frame Interval / Smear Blend / Trail Decay
MECHANISM INTERROGATION:
  tactic 1: the vector is computed per block and then stored per pixel, so the block falls apart
  tactic 2: a P-frame is quantized; the existing "quantization" only snaps the block centre at the I-frame boundary
  tactic 6: C already stores the motion. The block centre is the vector a real macroblock would carry
ADD:
  1. Block-carried P-frame motion — the update reads C at the block centre (§12.2B). The chroma ghost still uses the per-pixel vector
  2. DCT step — the predicted colour is round-to-step on P-frames, step size from Motion Strength (§12.2B). I-frames stay clean
FORBID on this file: a second spring, VHS dropouts, thin-film
A PACKING: motion state in A (unchanged). Display is ACES on writeTexture only
```

```
SHADER: spectral-mesh
IDENTITY (one sentence): an image-adaptive wire mesh, spectral along the wires, pulled toward the pointer.
KEEP VERBATIM: density from Grid Density and the image gradient; displacement wobble; mouse pull; spectralWavelength; diagonals and triangle wires; junction beads; grating fringe; A = (line, triLine, pull, alpha). Params Grid Density / Displacement Strength / Mouse Radius / Color Shift
MECHANISM INTERROGATION:
  tactic 2: a mesh drawn on a photo is heavier on edges and the cell face sits below the wire
  tactic 3: gradMag only scales density; lineWidth ignores it. grid is the cell interior and is only used for the wire test
ADD:
  1. Edge-weighted wire gauge — lineWidth grows with the gradMag the density already uses
  2. Recessed cell faces — the interior of grid darkens, the wires stay
FORBID on this file: replacing the grid with Voronoi, a new palette, a spring
A PACKING: A stores (line, triLine, pull, alpha). Display is ACES. C is not read
```

```
SHADER: gen-fractal-lightning-canvas
IDENTITY (one sentence): Lichtenberg bolts on a dark field, with bass-seeded strikes, a pointer bolt, and afterglow in C.r.
KEEP VERBATIM: branchBolt dendrite, seed loop, pointer bolt, strike flash, afterglow from C.r scaled by Afterglow, cool/hot/core colour, params Branch Density / Glow Intensity / Strike Rate / Afterglow
MECHANISM INTERROGATION:
  tactic 2: a discharge has a hot channel inside a dimmer sheath, and the branch dies at the tip
  tactic 6: C.r is one pixel of last frame's energy. The neighbours are the scorch the channel leaves
ADD:
  1. Return-stroke core — a tighter band of the same dendrite, so the existing hot colour lights the channel
  2. Tip taper — the sheath dims as r grows. The seed core stays
  3. Scorch corona — four exact-C neighbours, scaled by the same Afterglow mix
FORBID on this file: a new creature, an IQ palette, a spring. A.r stays raw energy
A PACKING: A.r raw energy (unchanged). Display is ACES. C.r is that energy, read with textureLoad
```

```
SHADER: gen-bioluminescent-mycelial-nexus
IDENTITY (one sentence): a raymarched lattice of three glowing tubes per cell, warped by fbm, thickened by bass.
KEEP VERBATIM: three axis tubes, smin, the fbm warp, mouse pull while held, bass thickness, treble on the emit, SSS from the slider, 80-step march. Params Branching Density / Glow Intensity / Network Mutation Speed / Subsurface Scattering
MECHANISM INTERROGATION:
  tactic 1: noise3D already builds hermite weights and then ignores them, so the warp is a block
  tactic 2: hyphae swell where they cross, and the flash travels along the tube you are on
  tactic 3: the normal says which tube was hit; the emit only uses p.z
ADD:
  1. Hermite noise — the weights already computed, so the same lattice mutates continuously
  2. Junction bulbs — a sphere at the cell centre, smin'd with the three tubes
  3. Hypha-axis pulse — the emit travels along the tube axis the normal already implies
  4. Three-tap crevice AO on the lit body (§12.2E). The emit stays bright
FORBID on this file: a different creature, an IQ palette, a liquid solver
A PACKING: ACES display RGBA. C is not read
```

```
SHADER: rainbow-vector-field
IDENTITY (one sentence): a polar rainbow wheel with outward spectral rings and a displacement strength in depth for a follow-up pass.
KEEP VERBATIM: hue from angle + distance * Frequency; saturation and brightness sliders; ring phase; depth = brightness * Displacement Scale + the mouse wave. Params Frequency / Saturation / Brightness / Displacement Scale
MECHANISM INTERROGATION:
  tactic 2: a traveling ring has a bright front, and a polar field has spokes
  tactic 3: angle is computed and only added into the hue
  tactic 7: the field has a direction. Held, that direction should bend at the pointer
ADD:
  1. Ring leading crest — a sharp cos crest on the same ringPhase, on the side the ring travels toward
  2. Angular spokes — cos(angle * n) with n from Frequency, so the wheel reads as a direction field
  3. Held swirl — the angle bends inside the pointer disk while the mouse is down
FORBID on this file: a spring, an IQ palette, changing depth into something other than a displacement strength
A PACKING: ACES display RGBA. C is not read. Depth stays a displacement strength
```

```
SHADER: alpha-depth-fog-volumetric
IDENTITY (one sentence): seven-layer Beer fog over the photo, warm-to-cool by the temperature slider, with a held clear and click swirls.
KEEP VERBATIM: 7-layer optical depth, height falloff, turbulence fbm, temperature ramp, pointer clear, click shells, silver lining, the small C smear, A = ACES rgb + transmittance. Params Fog Density / Fog Height / Turbulence / Color Temperature
MECHANISM INTERROGATION:
  tactic 2: fog in front of a bright pixel takes that colour, and distant fog goes cool
  tactic 3: transmittance is a single veil. Scatter in a real slab peaks in the middle of the optical depth
  tactic 6: C stays the display smear it already is
ADD:
  1. Source-tinted in-scatter — bright source pixels pull the existing fog colour
  2. Mid-slab lobe — silver lining peaks at transmittance 0.5 (4T(1-T)), with a floor so the lining does not vanish
  3. Aerial cooling — far depth shifts toward the cool stop, and a warm Color Temperature weakens that shift
FORBID on this file: a new spring, a second fog model, replacing Beer
A PACKING: ACES display RGB + transmittance in A.a (unchanged)
```

```
SHADER: cross-spec-alpha-spectral-bloom
IDENTITY (one sentence): per-channel bloom plus a Cauchy split of the sharp plate, exposure and a pointer lamp.
KEEP VERBATIM: bloom radius loop, Cauchy on the sharp R/B sample, exposure, chromatic shift, mouse lamp, bass halo. Params Bloom Radius / Dispersion / Exposure / Chromatic Shift
MECHANISM INTERROGATION:
  tactic 1: the bloom is a blur of the whole image. A bloom extracts highlights, and blue should spread wider than red
  tactic 8: the glow is added on top of the plate, so the highlight is counted twice
ADD:
  1. Soft-knee extract — the loop blooms max(sample - knee, 0). Knee drops as Exposure rises
  2. Cauchy-weighted PSF — red tighter, blue wider, from the n(λ) the file already computes (§12.2F)
  3. Energy-conserving core — the sharp plate gives up light where the extract is strong (§12.2F)
FORBID on this file: a spring, an anamorphic streak, a second palette
A PACKING: ACES display RGBA. C is not read. The old comment that A stores four bloom bands was not what the shader wrote
```

```
SHADER: hyb-spectral-fbm-displace
IDENTITY (one sentence): nested fbm domain-warp of the photo, with a spectral split along the warp, conveyor bands, and click rings.
KEEP VERBATIM: domainWarp, ±split scaled by Spectral Spread, conveyors, oil-slick, wavelength tint, held pull, click rings, Effect Mix. Params FBM Scale / Warp Amount / Spectral Spread / Effect Mix
MECHANISM INTERROGATION:
  tactic 2: blue should leave the warp farther than red. The split is symmetric
  tactic 3: dispVec is the warp. The history mix samples C at the same pixel, so the trail does not follow the flow
  tactic 7: the warp has a direction. A filament across that direction belongs to this field
ADD:
  1. Cauchy scale on the existing ±spread (§12.2F). Spectral Spread still sets the magnitude
  2. Upwind C trail — the 0.08 history mix samples C upstream of dispVec
  3. Flow-aligned filament — a band across the warp direction, gated by how far the pixel moved
FORBID on this file: a new spring, a second oil-slick, replacing domainWarp
A PACKING: ACES display RGBA. C is read as colour
```
