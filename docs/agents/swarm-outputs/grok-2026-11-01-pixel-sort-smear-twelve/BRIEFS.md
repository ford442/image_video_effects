# Grok 4.7 — pixel-sort / smear twelve

Written before WGSL edits. Second pass where a file already named ideas: the new pair is additive and uses nouns already in that file. No new spring. No shared IQ palette, ripple stamp, or Asendorf walk copied onto a file that does not already sort that way.

Formula cap for this batch: chroma delay (§12.2B) and dropout tail (§12.2B) on glitch-pixel-sort only. Macroblock step (§12.2B) on spectral-glitch-sort only. Drying (§12.2C) on pixel-drag-smear only. Speed-thinning (§12.2C) on spectral-smear only. Cauchy (§12.2F) on pixel-stretch-interactive only. Wet-edge is not added (luma-smear already has the ridge).

```
SHADER: glitch-pixel-sort
IDENTITY: a luma-threshold sort that shoves pixels along H, V, or a noisy diagonal, then melts bright runs through last frame and races a bright packet down the axis.
KEEP VERBATIM: Threshold / Sort Mode / Glitch Amount; mode 0 horizontal, 1 vertical, else noisy angle; fp128 displacement; hash jump; C melt when previous luma wins; streak_packet; glitch RGB split above 0.3; held deepens glitch and melt; click rings
MECHANISM INTERROGATION:
  tactic 2: a tape tear keeps luma and lets chroma lag, and a dropout burst has a tail behind the head.
  tactic 3: streak_packet is a symmetric spike. The head position is computed and thrown away.
  tactic 6: C is last frame's display RGB for the melt. Alpha is unread, so the delay does not need new state.
ADD:
  1. chroma delay line (§12.2B) — luma stays on the sorted sample; chroma comes from one step back along sortDir, mixed by Glitch Amount
  2. dropout tail (§12.2B) — behind the existing packet head, an exponential one-sided tail lifts toward white, scaled by Glitch Amount and the threshold mask
FORBID: an Asendorf walk (pixel-sorter and pixel-sort-radial already own that), a new spring, Schmitt latch packed into A.a (melt stores display RGBA)
A PACKING: ACES display RGBA (C is read as last frame's colour for the melt)
```

```
SHADER: pixel-sorter
IDENTITY: an interval pixel sort inside a cursor gate: walk the axis until luma falls under the threshold, keep the brightest, tint by how far the run went.
KEEP VERBATIM: Sort Direction / Reverse Sort / Intensity Scale / Sort Threshold Luma; vertical / horizontal / velocity axis; Asendorf close; span seam; exact C blend; wavelength tint; prev-mouse in extraBuffer[133..134] and [138] (not a spring)
MECHANISM INTERROGATION:
  tactic 3: steps is the run length and is only used as a sample offset. The seam is a bright accent with no column structure.
  tactic 4: Intensity Scale sets stride. The spatial version of "a sort" is a comb across that axis.
ADD:
  1. head-to-tail ramp — steps already counted: the head keeps the brightest sample, the tail darkens
  2. sort-axis comb — a hairline every eighth pixel across the axis, only inside the run, so streaks read as columns or rows
FORBID: a new spring, another wavelength function, spoke gutters (those belong on the radial sort)
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: pixel-sort-radial
IDENTITY: a radial stretch around the pointer that walks out along the radius, closes when luma drops, and marks that close with a ring.
KEEP VERBATIM: Stretch Amt / Luma Thresh / Radius / Direction; inward versus outward dir; 10-step Asendorf; ring seam; chromatic sample; twist and radial runner; click fronts
MECHANISM INTERROGATION:
  tactic 7: the radius already has an angle. A radial sort is a fan of spokes, and that angle is only used as a direction vector.
  tactic 2: pulling inward stacks pigment on the cursor; pushing outward should spend saturation rather than add it.
ADD:
  1. spoke gutter — dark rays at the boundaries of angular bins around the pointer, gated by the existing influence and the luma run
  2. inward stack — Direction below 0.5 piles the existing brightest sample toward the pointer; outward runs desaturate with Stretch Amt
FORBID: an axis comb (pixel-sorter), a new spring, a second spectral palette
A PACKING: ACES display RGBA (C was not read)
```

```
SHADER: pixel-sort-explorer
IDENTITY: interval-segmented luma streaks inside a spotlight, with line wobble, a scan read-out, and a lens rim.
KEEP VERBATIM: Sort Threshold / Spot Radius / Direction (V/H) / Smoothness; bidirectional 12-step walk; luma-hold from C.a; streak persist from C.rgb; head-bright ramp; scan band; surround dim
MECHANISM INTERROGATION:
  tactic 3: streakT is 0 at the head and 1 at the tail, and it only scales a ramp and a glow.
  tactic 4: Smoothness sets stride. The tail of a long run is where a sort sheds pixels.
ADD:
  1. interval ticks — dark stations along streakT so the segment length is visible inside the spotlight
  2. tail dust — a stable spatial breakup only where streakT is high. Smoothness still owns the stride
FORBID: a new spring, frame-hash dust, a second hysteresis term
A PACKING: ACES display RGBA (unchanged; C.a is the hold, C.rgb is the persist)
```

```
SHADER: spectral-glitch-sort
IDENTITY: a brightness-gated sort along a sprung angle, with block noise, a short brighter-sample walk, and red/blue extra steps.
KEEP VERBATIM: Sort Length / Luma Threshold / Direction / Digital Noise; spring in extraBuffer[133..138]; click tears; four-step walk; chroma sort; exact-C trail; read-only FFT block voice
MECHANISM INTERROGATION:
  tactic 2: a digital tear is a rectangle, and a click tear has a head on one side of the axis.
  tactic 3: noise is already one value per block, then only scales a per-pixel offset.
ADD:
  1. block-shared step (§12.2B macroblock) — Digital Noise mixes the per-pixel walk toward one step count shared by the block
  2. directional tear — click energy throws harder down the sort axis than against it, so the ring boost is a head and a tail
FORBID: a second chroma split, a new spring, dropout tails (glitch-pixel-sort owns those)
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: spectral-flow-sorting
IDENTITY: pixels sort along an optical-flow vector, with a cursor flow added and a frequency false-colour.
KEEP VERBATIM: Flow Sensitivity / Sort Threshold / Frequency Influence / Temporal Smoothing; exact-C Lucas-Kanade; Asendorf walk along the flow; cursor flow and click pulse; raw previous RGB in A
MECHANISM INTERROGATION:
  tactic 1: a one-tap LK step is unreliable where the spatial gradient is ~0 (the aperture problem). The gradient is computed and discarded after the product.
  tactic 7: flowDir is a direction. A flow picture shows that direction, not only a shifted colour.
ADD:
  1. aperture gate — the optical-flow term is scaled by gradient confidence. Cursor flow and the click pulse stay
  2. flow barb — a short tick across flowDir where the vector is strong and the pixel is inside the sort threshold
FORBID: ACES on the stored previous RGB, a spring, another cosine palette
A PACKING: raw previous RGB in A for the next LK step. ACES on writeTexture only.
```

```
SHADER: hybrid-spectral-sorting
IDENTITY: horizontal spectral bands that walk down the strip while luma stays similar, then displace and hue-shift by band energy.
KEEP VERBATIM: Sort Sensitivity / Spectral Bands / Spectral Displacement / Hue Shift; Y walk that breaks on a small luma delta; band sine displacement; palette and hueShift; bass step glitch; three-band audio
MECHANISM INTERROGATION:
  tactic 3: band and bandTop are computed to clip the walk, then the strip edge is invisible.
  tactic 4: the brightest sample is one colour for the whole strip. The leading edge of a band is where that sample belongs.
ADD:
  1. band gutter — a dark hairline on the boundary the walk already refuses to cross
  2. band head — the top of the strip keeps more of the brightest sample; the bottom stays on the displaced photo
FORBID: a new sort axis, a second palette, a spring
A PACKING: ACES display RGBA (C was not read)
```

```
SHADER: pixel-drag-smear
IDENTITY: a brush that drags last frame's paint along the pointer, with curl, a comb, and three history taps.
KEEP VERBATIM: Brush Radius / Drag Strength / Decay Rate / Mode; three exact-C taps; treble R/B bleed; lumaMix; warm/cool tint; click fronts; comb from Mode
MECHANISM INTERROGATION:
  tactic 2: bristles splay across the drag, and paint outside the brush dries back toward the photo.
  tactic 3: the three taps are collinear with the offset. The perpendicular of that offset is unused.
ADD:
  1. bristle splay — the side taps move off the drag line by a fraction of Brush Radius
  2. drying (§12.2C) — outside the brush, history falls back toward the live photo. Decay Rate still holds the stroke
FORBID: a new spring, speed-thinning (spectral-smear owns that), a second wet-edge (luma-smear already has the ridge)
A PACKING: ACES display RGBA (unchanged; C is last frame's display)
```

```
SHADER: pixel-stretch-interactive
IDENTITY: an edge-directed stretch from the structure tensor, with chromatic taps along that axis and bloom on the highlights.
KEEP VERBATIM: Stretch Amount / Bloom Strength / Grain Strength / Chromatic Scale; integrated tensor; coherence tear length; luma-sorted 8-tap streak; parallax; grain
MECHANISM INTERROGATION:
  tactic 2: dispersion through a stretch is nonlinear in wavelength. A coherent tear also has a lip beside the axis.
  tactic 3: coherence gates length and is then discarded. Chromatic Scale is a linear ±.
ADD:
  1. Cauchy channel scale (§12.2F) — Chromatic Scale is the dispersion coefficient; red, green, and blue offsets follow n(λ) relative to green
  2. coherence gutter — where the centre luma differs from one texel off the stretch axis, a coherent tear darkens
FORBID: a spring, reading C, replacing the tensor
A PACKING: ACES display RGBA (C was not read)
```

```
SHADER: luma-smear-interactive
IDENTITY: bright pixels smear along the pointer and downhill on the luma slope, with chromatic trail taps and a wet-edge ridge.
KEEP VERBATIM: Trail Decay / Luma Threshold / Color Shift / Eraser Size; (0,0) state texel; pre-ACES trail RGB and energy in A; downhill luma term; R-lag / B-lead; ridge from C.a; eraser zeros velocity
MECHANISM INTERROGATION:
  tactic 2: pigment sticks when the drag points up the slope, and a split of red and blue spends saturation.
  tactic 3: lumaGrad is subtracted as a force. The uphill component of velocity is not removed. rTrail and bTrail are only packed into the colour.
ADD:
  1. uphill stick — the part of velocity aimed up the existing luma gradient is removed. Downhill slide stays
  2. fringe spends the trail — where the red and blue taps diverge, the trail desaturates before the ridge. Color Shift still sets the tap spacing
FORBID: a new spring, ACES on the stored trail, a second ridge
A PACKING: unchanged. Linear pre-ACES trail RGB and A.a = trail energy. (0,0) stays the pointer state texel. ACES on writeTexture only.
```

```
SHADER: spectral-smear
IDENTITY: a sprung brush paints a spectral trail that advects through noise and last frame, with click blooms.
KEEP VERBATIM: Trail Decay / Brush Radius / Color Speed / Intensity; spring in extraBuffer[133..138]; flow advection; exact C; spectral palette; held gate; click bloom
MECHANISM INTERROGATION:
  tactic 2: a fast stroke is thinner, and hue should run along the stroke the spring already has.
  tactic 3: springVel only shifts the history UV. Color Speed only spins hue in time.
ADD:
  1. speed-thinned brush (§12.2C) — Brush Radius is divided by spring speed. The base radius stays the slider
  2. stroke-sheared hue — hue also advances along springVel. Color Speed still scales both the time spin and the shear
FORBID: a second spring, drying (pixel-drag owns that), replacing the palette
A PACKING: ACES display RGBA (unchanged; C is last frame's display)
```

```
SHADER: quantum-smear
IDENTITY: the photo scatters into a noisy smear where motion, depth, and entropy are high, with foam, voids, and a coherence mix back to the picture.
KEEP VERBATIM: Intensity / Speed / Scale / Detail as scatter radius, entropy scale, coherence, and density (do not rewire to the JSON words); stochasticAdvect; foam; void subtract; click mix back to the photo; motion from C versus the current photo
MECHANISM INTERROGATION:
  tactic 2: still pixels should stop boiling, and a void that removes particles leaves a lip of them around the hole.
  tactic 6: C is previous smear colour used only as a motion magnitude. Display can be tone-mapped without storing the tone-map in A.
  tactic 8: the void only subtracts.
ADD:
  1. still-lock — the advected UV collapses back to the pixel where motion is ~0. Intensity still sets the radius
  2. void rim — a thin add of the photo where void potential is weak but nonzero, around the existing subtract
FORBID: a spring, packing the latch into A, tone-mapping the stored smear (next frame's motion would compare unlike quantities)
A PACKING: clamped pre-ACES smear RGB in A so motion stays a colour difference. ACES on writeTexture only.
```
