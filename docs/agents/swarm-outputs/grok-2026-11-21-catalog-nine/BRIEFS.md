# Idea Cards — Grok (catalog nine, 2026-11-21)

Written before the WGSL edits. Nine shaders the user listed by size. Each card adds two ideas in the existing main path. Saved `params` stay byte-exact. No shared spring, shockwave, or palette is added. Springs, click paths, and earlier ideas that are already in a file stay as they are.

Three files still paste the binding header (`chroma-lens`, `steamy-glass`, `voronoi`). Migrating them to `#include "_prelude.wgsl"` is infrastructure and is not an idea.

Formula rule: a §12.2 row is newly applied on at most one file here.

- Schmitt-trigger lock (§12.2B) and field interlace (§12.2B) are `vhs-tracking` only.
- Cauchy dispersion (§12.2F) is `chroma-lens` only.
- Block DCT quantization (§12.2B) is `datamosh-brush` only.
- Dropout bursts (§12.2B) are `digital-decay` only.
- No other §12.2 row is newly applied.

```
SHADER: tensor-flow-sculpt
IDENTITY (one sentence): the photo pushed like clay along the depth map's structure-tensor directions, low frequencies warped and fine detail left in place.
KEEP VERBATIM: Sculpt Depth / Freq Separation / Curvature Scale / Anim Speed; the strided structure tensor and eigenpair; Hessian mean and Gaussian curvature; geodesic displacement; ripple sculpt force; frequency-split warp; LIC along the contour tangent; principal-axis chroma; ridge glow; dome/saddle sheen; clay creep through exact bilinear C; flowStr 0.3 and persistence 0.6.
MECHANISM INTERROGATION:
  tactic 2: clay yields along a coherent grain and barely moves where the tensor is isotropic. The geodesic step currently ignores anisotropy.
  tactic 5: a sculpting tool leaves rake grooves parallel to the stroke. The LIC combs color along the contour; it does not cut grooves along the tool direction.
  tactic 6: C stays display history. Creep already reads it. Do not pack curvature into A.
ADD:
  1. Anisotropic yield — the principal-axis term of the existing geodesic displacement scales with the coherence the tensor already computes. Isotropic clay barely slides. Sculpt Depth stays the amplitude.
  2. Rake striations — thin grooves parallel to the principal direction, gated by coherence and |mean curvature|, cut into the clay after the sheen. Distinct from the contour LIC.
FORBID: a spring, a new palette, replacing the tensor or the frequency split, shockwaves beyond the ripple sculpt force already here
A PACKING: ACES display RGBA (unchanged; C is that display history, mixed post-ACES)
```

```
SHADER: physarum
IDENTITY (one sentence): an Eulerian slime mold whose veins feed on the photo, with mass, heading, and a decayed trail.
KEEP VERBATIM: Agent Radius / Deposit Opacity / Sense Distance / Trail Decay; seed-on-zero; semi-Lagrangian scalar mass and winner-take-all heading; flow Jacobian pile-up; three-sensor steer; mouse arc pull; ripple twist; 3×3 trail blur; vein-above-ring display; Beer-style transmittance. The mass and heading update are not rewritten.
MECHANISM INTERROGATION:
  tactic 3: mass and heading are computed and then only deposited. The front of a vein is the trail difference along that heading, and it is thrown away.
  tactic 8: the red channel is the food. A dense vein should leave the food duller, or the agar never looks eaten.
  tactic 6: A stays raw (trail, mx, my). Display ideas must not be written into those fields.
ADD:
  1. Leading-edge glint — trail one step ahead minus trail one step behind, along the heading already stored, lights the front of a vein. Deposit and steering stay.
  2. Food bite — where vein density sits on bright food, the photo under it dulls and desaturates. Deposit Opacity still owns the vein coverage.
FORBID: a new solver, vorticity bolted on, a spring, an IQ palette, ACES stored into the sim fields
A PACKING: raw sim state (trail, mx, my, 0), unchanged. ACES on the display write only.
```

```
SHADER: vhs-tracking
IDENTITY (one sentence): a VHS deck with capstan wander, azimuth loss, head-switch flagging, dropout concealment, and line-alternate chroma.
KEEP VERBATIM: Tracking Error / Noise Level / Color Drift / Scanlines and their current roles (walk sigma, azimuth, dropout rate, chroma phase magnitude); the sprung tracking cursor; capstan; head-switch skew; azimuth luma/chroma blur; line-alternate hue flip; head band; dropout mask; DOC line repeat; chroma smear; the row walk in C. A.g is written today and never read.
MECHANISM INTERROGATION:
  tactic 2: a tracking servo that loses lock stays lost until the error falls. The walk integrates fresh noise every frame, so it never latches.
  tactic 5: a mis-tracked VHS also shows the two fields a line apart. Luma and chroma already take different horizontal taps; they still share one vertical line. The line-alternate phase flip is hue, not a field offset.
  tactic 6: the row state at column 0 is the walk. The unread second channel can hold the lock bit.
ADD:
  1. Schmitt-trigger tracking lock (§12.2B) — once |walk| crosses a high threshold it holds and creeps back without new noise, and it releases only below a lower threshold. The bit is stored in the row state's second channel, which nothing read. Tracking Error still sets the walk sigma and both thresholds.
  2. Field interlace (§12.2B) — luma is sampled a fraction of a line off the chroma line, alternating by row and frame, scaled by Tracking Error. The chroma phase flip stays.
FORBID: a second spring, a DCT quantizer, a dropout-burst formula (the DOC already conceals dropouts), an IQ palette
A PACKING: raw row state (walk, tracking lock, chroma phase, head band). Dropout mask stays a same-frame display term; it is no longer what A.g means.
```

```
SHADER: plasma
IDENTITY (one sentence): a cluster of plasma orbs orbiting the pointer, with trails, shadows on the photo, arc filaments, and a luma corona.
KEEP VERBATIM: Orb Radius / Orbit Speed / Plasma Intensity / Shadow Depth; eight orbiting metaballs; wisp noise; velocity trail; photo shadow; arc filaments between consecutive orbs; luma corona. No spring is added.
MECHANISM INTERROGATION:
  tactic 2: a real discharge bows between the electrodes; it does not stay a straight segment. The filament loop already has the segment and the noise function.
  tactic 6: C is not read. The field is thrown away after the composite, so a moved orb cannot leave an afterglow unless the field is kept in a channel the next frame can read.
  tactic 3: plasmaField is the quantity to keep. Display RGB cannot be the memory, because it is also the photo.
ADD:
  1. Bowed filaments — the existing segment is offset along its normal by fbm, pinched to zero at both orbs so the arc stays attached. Plasma Intensity stays the brightness.
  2. Field afterglow — A.a stores a decaying envelope of the field (writeTexture keeps coverage alpha). Where that envelope remains and the previous pixel was brighter than the photo, the previous display color lingers. A.rgb stays the ACES display.
FORBID: a spring, a new orb count, an IQ palette, click shockwaves, replacing the metaball field
A PACKING: ACES display RGB, decaying plasma-field envelope in A.a. writeTexture alpha stays coverage. C.a is that envelope; C.rgb is the afterglow color only where the envelope remains and the pixel was brighter than the photo.
```

```
SHADER: chroma-lens
IDENTITY (one sentence): a pointer magnifier with seven-wavelength rainbow fringes, astigmatic edge blur, a glass rim, and click fronts.
KEEP VERBATIM: Magnification / Aberration / Lens Radius / Edge Blur; the barrel curve that is 1 at the rim; seven spectral taps and wavelengthToRGB; tangential plus sagittal edge blur; rim runners; click fronts; held radius growth. The seam at the rim stays 1.
MECHANISM INTERROGATION:
  tactic 1: the seven taps are spaced linearly in wavelength. Glass dispersion is Cauchy, 1/λ², so blue pulls away from green faster than red does.
  tactic 2: a simple magnifier does not hold one magnification at every radius. The zone between center and rim focuses differently, and that error has to be zero at the rim or the plate no longer joins.
  tactic 6: C is not read. A stays the pre-tone-map lens color. Do not pack a new field into it.
ADD:
  1. Cauchy spacing (§12.2F) — the existing ±abbStrength offset uses n(λ)=1+B/λ² relative to red and violet, instead of a linear mix. The seven taps and the red-spreads / violet-pulls sign stay.
  2. Zonal spherical aberration — an r²(1−r²) dip in the existing lens curve, scaled by Magnification, zero at the center and at the rim.
FORBID: a spring, cos⁴ as a flat vignette, a new spectral model that drops the seven taps, shockwaves beyond the click fronts already here
A PACKING: pre-tone-map lens colour RGBA (unchanged; C is not read). writeTexture stays ACES.
```

```
SHADER: datamosh-brush
IDENTITY (one sentence): a held brush that corrupts macroblocks, flattens them toward a DC sample, and leaves a mosquito ring and a ghost trail.
KEEP VERBATIM: Brush Size / Block Crush / Decay Rate / Effect Threshold (threshold still drives ghost alpha); the spring and its smear; click corruption; DC hold; mosquito ring; macroblock edge tint; C as display color.
MECHANISM INTERROGATION:
  tactic 5: MPEG damage is a quantized block, not only a shifted one. Block Crush already chooses the block grid and is the quantizer step.
  tactic 6: the per-frame block hash jumps every sample. A P-frame holds one motion vector for a run of frames. Decay Rate is how fast the corruption gives up; it can also be how soon the vector is allowed to change. C stays display color — the held vector is a coarser time key, not a new buffer.
ADD:
  1. Block DCT quantization (§12.2B) — inside the corrupting brush, the color is rounded to a step taken from Block Crush, after the DC hold.
  2. Held motion vector — a second sample uses the block hash at floor(time × Decay Rate), mixed into the per-frame glitch, so the vector sticks and then pops. Decay Rate still mixes the ghost.
FORBID: a Schmitt lock (that is the VHS servo), a dropout streak, a second spring, replacing the DC hold or the mosquito ring
A PACKING: ACES display RGBA (unchanged; C is that display color)
```

```
SHADER: steamy-glass
IDENTITY (one sentence): a fogged pane with condensate, droplets, downward runoff, and a wipe that beads at its edge.
KEEP VERBATIM: Fog Density / Fade Speed / Wipe Radius / Blur Amount; steam relaxation; droplet growth; nucleation runoff; beaded wipe rim; click clear; refraction from the droplet gradient; Beer transmittance; A/C = steam, droplets, runoff, wipe memory. No spring.
MECHANISM INTERROGATION:
  tactic 4: Fade Speed returns the pane uniformly. On a real window the lower glass stays wet after the top has cleared.
  tactic 3: the droplet gradient is computed for refraction and then only shifts UV. The contact line of a drop is exactly where that gradient is steep.
  tactic 6: do not add a channel. The four fields stay the four fields.
ADD:
  1. Low-pane linger — the existing return toward Fog Density is weaker at the top of the glass and stronger toward the bottom. Fade Speed stays the rate.
  2. Contact line — where the droplet gradient is steep and the drop is not a solid bead, the glass darkens. Refraction still uses that same gradient.
FORBID: a new fluid solver, a spring, thin-film iridescence, ripples beyond the click clear already here
A PACKING: raw sim (steam, droplets, runoff, wipe memory), unchanged. ACES on writeTexture only.
```

```
SHADER: voronoi
IDENTITY (one sentence): a Voronoi tessellation of the photo, ridges on F2−F1, cells drifted and pulled by the pointer and by clicks.
KEEP VERBATIM: Cell Density / Jitter / Ridge Strength / Palette Shift; the 3×3 Worley; tectonic drift; pointer pull; six-ripple swirl; cell-center photo sample; palette mix; ridge ink; treble sparkle on the ridge.
MECHANISM INTERROGATION:
  tactic 3: F1 is only a mask. The seed of a cell is the point where F1 is zero, and nothing marks it.
  tactic 2: the description is a reconstruction. A reconstruction pulls boundaries onto image edges. The image gradient is not in the lattice.
  tactic 6: C is not read. Do not store cells in A. The palette indexed from plasmaBuffer stays; it is the Palette Shift param, not a new costume.
ADD:
  1. Feature gather — the lattice point is shifted by the photo's luma gradient, scaled by Ridge Strength, before Worley. Flat photos barely move.
  2. Seed pits — a small darkening at F1 ≈ 0, scaled by Ridge Strength, so each cell shows its site.
FORBID: a spring, a second distance field, replacing the palette, click shockwaves beyond the six ripples already here
A PACKING: ACES display RGBA (unchanged; C is not read)
```

```
SHADER: digital-decay
IDENTITY (one sentence): block corruption of the photo, with bit flips, a ghost frame, a torn block, and rows that stick.
KEEP VERBATIM: Corruption Rate / Block Size / Ghost Decay / Depth Influence; the spring hotspot; click burst; block displacement; bit flips; block tear; stuck row; C as the ghost color. Ghost Decay still owns the stuck row.
MECHANISM INTERROGATION:
  tactic 5: a serial bitstream fails in bursts: the error starts on a row and dies exponentially along the scan. The block tear is a spatial slide, not that tail.
  tactic 3: the spring velocity is integrated and only the position is used. A fast drag should shear the rows under the hotspot.
  tactic 6: C stays the ghost color. The burst is display-only.
ADD:
  1. Dropout bursts (§12.2B) — a sparse row, keyed like the stuck row, paints an exponential tail along x. Corruption Rate sets how often and how long the tail is. Zero corruption still forces the clean source.
  2. Pointer shear — rows inside the held hotspot shift by the spring's x velocity, which the integrator already writes. No new spring.
FORBID: a DCT quantizer (that is the datamosh brush), a Schmitt servo, a second spring, an IQ palette
A PACKING: ACES display RGBA (unchanged; C is the ghost color)
```
