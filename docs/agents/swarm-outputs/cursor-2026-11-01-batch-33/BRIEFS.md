# Idea Cards — cursor/batch-33 holographic projection and interference (2026-11-01)

Written before the WGSL edits. Twelve holographic projection and interference shaders. Several already carry a named idea set; those cards add two more inside the existing path. Saved `params` stay byte-exact. No new spring. No shared overlay.

The host re-uploads `extraBuffer` every frame and only index 0 of `plasmaBuffer` is bass/mids/treble, so a spring stored at `[133..]` never survives and `plasmaBuffer[1..]` is empty. Where a file was reading the pointer or the audio from those dead slots, the picture uses the live mouse and `plasmaBuffer[0].xyz`. That is a floor correction, not an idea. Silence and a released pointer still match the old picture.

Formula rule: Cauchy (§12.2F) is only on `holographic-prism`. Field interlace and dropout (§12.2B) are only on `holographic-projection-failure`. No other §12.2 row is used.

## holographic-contour

```
SHADER: holographic-contour
IDENTITY: a twisted holographic lattice marched over the photo, clicked rings, a luma gate that is supposed to be the contour.
KEEP VERBATIM: 60-step march, twist, grid-intersect-sphere, dotSize / edgeThresh / levels / inkDensity scalar roles, 0.3 mix with C, ripple ring shape.
MECHANISM INTERROGATION:
  tactic 1: the "contour" is a luma smoothstep. The next approximation of a contour is a Sobel ridge on that same photo.
  tactic 2: a hologram of a contour is a fringe record, not a flat cosine paint. The march distance is the object beam.
  tactic 3: levels is already a spatial frequency and is only added into one phase.
  tactic 6: C is display colour mixed at 0.3. Keep that mix; store it pre-ACES so the next frame is the same space.
ADD:
  1. Sobel contour ink — a bright ridge along the photo gradient, gated by the existing edgeThresh, drawn on top of the luma mix.
  2. Reference-beam fringes — object beam (march distance) beats a tilted reference; levels stays the frequency.
FORBID: deleting the march, a new spring, an IQ palette as the look.
A PACKING: pre-ACES linear display RGBA (C is that colour). ACES on writeTexture only. Depth is march distance.
```

## holographic-crystal

```
SHADER: holographic-crystal
IDENTITY: a square crystal of stepped diffraction orders, dark grooves on the integer facets, mouse tilt, click warp.
KEEP VERBATIM: facets / tilt / interference / dispersion, crystalShape cutoff at 0.7, groove on fract(crystalR), order = floor(crystalR), per-channel phase spread, spec, click front.
MECHANISM INTERROGATION:
  tactic 2: a cut facet has a bright lip on the lit side of the groove, not only a dark slot.
  tactic 3: crystal_p is the section coordinate and is thrown away after the radius.
  tactic 5: a square section focuses light on its diagonals.
ADD:
  1. Lit bevel — a thin bright lip on the lit side of each integer groove. The groove stays dark.
  2. Diagonal caustic — a streak where |x| equals |y| inside the gem, scaled by Interference.
FORBID: a different crystal solid, thin-film soap colour, a new spring.
A PACKING: ACES display RGBA (unchanged; C is the previous display frame).
```

## holographic-failure-iridescence

```
SHADER: holographic-failure-iridescence
IDENTITY: the photo under a failing hologram — thin-film colour, glitch rows, tears, laser flicker.
KEEP VERBATIM: thinFilmColor wavelength loop, Film IOR, turbulence thickness, glitch rows, tear mask, chroma split, Failure / Holographic / Turbulence roles.
MECHANISM INTERROGATION:
  tactic 2: a soap film that is failing dewets. The glitch row already jumps the thickness; the hole is the rupture.
  tactic 5: a broken hologram replays the object from the wrong angle. The carrier wave vector (28, 14) is already the fringe direction.
  tactic 6: C is mixed at 0.1 before ACES. Store pre-ACES so that mix stays linear.
ADD:
  1. Dewetted holes — glitch rows open a thin island back to the photo, with a bright rim. Failure Amount opens them.
  2. False reconstruction — a second photo sample stepped along the carrier direction, mixed by Failure.
FORBID: a new film model, replacing the wavelength loop, a spring as the idea.
A PACKING: pre-ACES linear display RGBA. ACES on writeTexture only.
```

## holographic-flicker

```
SHADER: holographic-flicker
IDENTITY: an unstable laser hologram — mode-hopping lines, per-channel phosphor trails, vertical-hold slips, a hex emblem.
KEEP VERBATIM: three laser lines and spacing, phosphor decay (0.9, 0.8, 0.62), slip band and tear line, hex loop, chroma split, blackout, the four sliders.
MECHANISM INTERROGATION:
  tactic 2: the mode-hop already picks a wavelength. Coherent light at that wavelength speckles, and the grain is coarser when the line is longer.
  tactic 6: C is the ACES frame the phosphor already reads. Red is the slow channel; it should smear along the scan, not only sit one shift away.
ADD:
  1. Wavelength speckle — grain cell size follows laserLambda. Treble boils it by crossfading two seeds.
  2. Red phosphor smear — the red channel of C, a few pixels to the left, joins the existing red ghost. Ghost Amount scales it.
FORBID: a second slip system, a new laser line, a spring.
A PACKING: ACES display RGBA (unchanged; phosphor compares C in display space).
```

## holographic-glitch

```
SHADER: holographic-glitch
IDENTITY: a peeled, sheared hologram — row phase, grating-order ghosts, peel shadow, emitter blackouts.
KEEP VERBATIM: peel fold, continuous shear, ±1 grating orders, peel shadow, emitter blackout and sag, three history taps, Glitch / Holographic / RGB Shift / Flicker.
MECHANISM INTERROGATION:
  tactic 2: a scanned carrier has nulls. The scan sine is already there and only used as a brightness comb.
  tactic 3: interferencePhase and the scan frequency are both computed and never beat against each other.
ADD:
  1. Carrier nulls — a thin dark line where the scan sine crosses zero. Flicker widens it.
  2. Scan/grating moiré — the beat of interferencePhase against the scan comb, scaled by Holographic Intensity.
FORBID: a new tear axis, thin-film as the look, a spring.
A PACKING: pre-ACES linear display RGB + transmission alpha (unchanged).
```

## holographic-interferometry

```
SHADER: holographic-interferometry
IDENTITY: object and reference beams interfere across depth and luma; speckle, parallax reconstruction, spectral fringes.
KEEP VERBATIM: interferencePattern cosine, spectralReconstruct, 4-tap speckle, parallax sample, Fringe Density / Coherence / Reconstruction Angle / Saturation.
MECHANISM INTERROGATION:
  tactic 1: the cosine is the interferogram. An interferometer also draws the equal-phase contour, the dark line at the half-fringe.
  tactic 2: coherence length is a visibility envelope versus path difference. The slider currently only scales speckle size. The path difference is computed inside interferencePattern and discarded.
  tactic 4: Coherence Length, spatially — visibility falls as the path grows, same slider.
ADD:
  1. Equal-phase contours — dark ink where the cosine crosses 0.5. Density stays Fringe Density.
  2. Coherence envelope — fringe contrast falls with path difference. Width is Coherence Length. Speckle scale stays.
FORBID: replacing the two-beam sum, a soap-film palette, a spring as the idea.
A PACKING: pre-ACES linear display RGBA. ACES on writeTexture only.
```

## holographic-prism

```
SHADER: holographic-prism
IDENTITY: a prism the pointer moves, Snell refraction, facet count, wavelength caustics, a hex that opens while held.
KEEP VERBATIM: snellRefract, facet count, hex/circle morph, wavelengthToRGB, caustic, click rings, Facet Count / Dispersion / Rotation / Holo Glitch.
MECHANISM INTERROGATION:
  tactic 1: the R/B split is a fixed 0.8/1.2. A prism's split is Cauchy, n = A + B/λ², and Dispersion is B.
  tactic 2: Snell already computes sin²θt and clamps it. Past 1 the ray reflects. That flash is missing.
ADD:
  1. Cauchy split — §12.2F. Red and blue offsets follow n(λ) relative to green. Dispersion stays the amount.
  2. TIR flash — where sin²θt exceeds 1, the facet edge lights in the wavelength colour instead of a fake refraction.
FORBID: a second prism solid, a grating copied from shatter, a spring as the idea.
A PACKING: ACES display RGBA (unchanged; C.r is a small caustic boost in that space).
```

## holographic-projection

```
SHADER: holographic-projection
IDENTITY: a plate projector — object-locked speckle, Bragg colour versus viewing angle, a rolling refresh band, focus under the cursor.
KEEP VERBATIM: speckle boil, Bragg wavelengthRGB, refresh band and persistFactor, scan line, glitch blocks, Scan Speed / Glitch / Holo Tint / Focus.
MECHANISM INTERROGATION:
  tactic 8: diffraction is not 100%. The undiffracted photo leaks through the dark fringes. Glitch is lost diffraction efficiency.
  tactic 5: a hologram replays only near the reference angle. viewVec is already the angle off the cursor.
ADD:
  1. Zero-order leak — the unshifted photo shows in the dark cosine fringes. Glitch Amount raises the leak.
  2. Replay window — off the cursor's vertical angle the reconstruction gives way to that photo. Focus Strength narrows the window.
FORBID: a new speckle field, a Bragg sinc copied from gpt52, a spring.
A PACKING: ACES display RGBA (unchanged; the refresh blend is in display space).
```

## holographic-projection-failure

```
SHADER: holographic-projection-failure
IDENTITY: a failing emitter — cone from the bottom, stale-frame tear bands, a re-sync line inside the repair circle, bit crush, V-hold.
KEEP VERBATIM: emitter cone and cyan cast, stale C tears, lock-line sweep, bitTruncate, block faults, Instability / RGB Split / V-Hold / Static.
MECHANISM INTERROGATION:
  tactic 5: a rolled V-hold splits the two fields. Even and odd lines in a tear band should not share the same horizontal offset.
  tactic 5 (second artifact): static on a failing projector arrives as a dropout, a white streak with a tail along the line, not only grain.
ADD:
  1. Field interlace — §12.2B. Inside a tear band, one field shifts an extra fraction of V-Hold.
  2. Dropout burst — §12.2B. A scanline flashes and decays along +x. Static sets how often.
FORBID: a new emitter position, the peel from holographic-glitch, a spring.
A PACKING: pre-ACES linear display RGB + carrier alpha (unchanged).
```

## holographic-projection-gpt52

```
SHADER: holographic-projection-gpt52
IDENTITY: a volume hologram — Bragg sinc per wavelength, thin-film order, scan jitter, a Pepper's ghost sample.
KEEP VERBATIM: braggDiffraction, thinFilmInterference, scan and slowScan, ghost sample, Scan Speed raw 0..5, Glitch / Holo Tint / Focus.
MECHANISM INTERROGATION:
  tactic 2: a thick grating shows pendellösung, brightness oscillating through the depth. Depth is read and used only in alpha.
  tactic 3: the sinc² efficiency is computed per channel and then only added as colour. Low efficiency should walk the reconstruction along the diffracted ray.
ADD:
  1. Pendellösung — the Bragg colour bands with scene depth.
  2. Diffracted walk — the sample offset gains a step along the Bragg angle, scaled by the existing efficiency.
FORBID: the projection shader's cosine leak, a new volume integral, a spring as the idea.
A PACKING: pre-ACES linear display RGBA. ACES on writeTexture only. C is mixed before the tone map.
```

## holographic-shatter

```
SHADER: holographic-shatter
IDENTITY: the photo cracked into flying shards with foil, a per-shard grating, a two-beam ghost, and a scan sweep.
KEEP VERBATIM: shard grid, flight from the pointer and from clicks, grating rainbow, two-beam ghost, scan sweep, Depth Weight alpha, Shatter / Hologram / Shard Count.
MECHANISM INTERROGATION:
  tactic 2: a glass edge has a lit bevel on the side facing the flight and a dark lip on the back. edgeGlow is a uniform rim.
  tactic 8: when the shard leaves, a crack opens and the ghost (the image still at the old place) is what shows in the gap.
ADD:
  1. Lit bevel — the rim toward flightDir brightens, the trailing rim darkens.
  2. Open crack — the narrow edge of a flying shard reveals the existing ghost and goes dark.
FORBID: a new fracture pattern, a different ghost, a spring.
A PACKING: pre-ACES display RGBA (unchanged).
```

## holographic_interference

```
SHADER: holographic_interference
IDENTITY: three coherent sources, an object beam from the pointer and a planar reference, speckle, a thin-film tint, chromatic fringe spacing. The id and the file use an underscore.
KEEP VERBATIM: the three-source loop, object path through filmThickness, reference angle and mouse tilt, IQ tint at 0.3, carrier comb, Film Thickness / Wave Scale / Depth Weight / Chromatic Aberration. Source count stays 3 (it was 3 plus a read of empty plasmaBuffer slots).
MECHANISM INTERROGATION:
  tactic 2: fringe visibility falls as the object path and the reference path diverge. That difference is computed per source and thrown away.
  tactic 4: Wave Scale is the wavenumber. Speckle size should move with it; the hash scales are fixed.
ADD:
  1. Visibility envelope — contrast falls with the mean |object path − reference path|. Film Thickness sets the coherence length.
  2. Wavenumber speckle — speckle and boiling-grain scales follow Wave Scale, so the grain tracks the fringe pitch.
FORBID: a fourth source, replacing the IQ tint, a spring.
A PACKING: ACES display RGBA. C is not read.
```
