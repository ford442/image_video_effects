# Idea Cards — Grok (glass-flora ten, 2026-11-15)

Written before the WGSL edits. Ten shaders around 137–142 lines. Each card adds **two or three** ideas in the existing main path. Saved `params` stay byte-exact. No shared spring, ripple stamp, or new IQ palette.

Formula rule: a §12.2 row is newly applied on at most two files here.

- Fresnel–Schlick (§12.2F) is new on `gen-liquid-metal-chrono-flora` and `quantum-prism` only. `hybrid-voronoi-glass` already had Schlick; it is not re-applied.
- Cauchy (§12.2F) is new on `quantum-prism` only. The Voronoi glass already had Cauchy.
- Thin-film (§12.2F) is new on `gen-aetherial-chromatic-tesseract` only (the file already called its cosine "thin-film").
- Fold-count material and box-edge wear (§12.2E) are the tesseract only.
- Step-count AO (§12.2E, three taps) is the ferrofluid only.
- Golden-angle layout (§12.2E) is the pollen only.
- cos⁴ bore falloff (§12.2A, used as the tunnel's off-axis shade) is the kaleidoscope tunnel only.

Prelude migration on `bio-touch`, `mouse-kaleidoscope-tunnel`, `quantum-prism`, `gen-psychedelic-time-warp-kaleidoscope`, and `rain-lens-wipe` is infrastructure (`migrate_to_prelude.py`). It is not an idea and does not by itself bump `Upgraded:`.

```
SHADER: hybrid-voronoi-glass
IDENTITY (one sentence): stable Voronoi cells as thick glass — Cauchy split, Fresnel, TIR, absorption, cursor pressure, click fracture.
KEEP VERBATIM: F1/F2 cell loop, hash22 sites, Cauchy IOR at 0.700/0.546/0.436 µm, Snell offset, Schlick, TIR step, Beer absorption, pointer lens pressure, ripple fracture on the normal, exact-C smear, params Cell Density / Refraction Index / Chromatic Dispersion / Glass Thickness
MECHANISM INTERROGATION:
  tactic 2: cut glass is flat in the facet and only turns at the bevel; the wall focuses a caustic
  tactic 3: stableBoundaryDistance is already computed and only used as a soft edge mask
  tactic 6: C is display colour; the existing smear stays. A stays ACES display RGBA
ADD:
  1. Interior-flat bevel — the existing facet tilt is full at the wall and quiet in the cell, so the pane is flat and the bevel carries the bend
  2. Wall caustic — the F2−F1 ridge concentrates transmitted light and the facet body gives a little up
FORBID on this file: a new spring, an oil-slick, a second palette, replacing Snell
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: gen-harmonic-ferrofluid-kinetics
IDENTITY (one sentence): a raymarched sheet of inverted-Voronoi ferrofluid spikes, with a magnetic mound under a held pointer.
KEEP VERBATIM: domain warp, 3D Voronoi spikes, inverse smoothstep height, mouse mound only while held, Blinn spec from Glossiness, view-cosine iridescence, subsurface from Subsurface Intensity, distance fog, params Spike Density / Flow Speed / Glossiness / Subsurface Intensity
MECHANISM INTERROGATION:
  tactic 2: a Rosensweig spike is pinched at the crest, and the tip throws a hard glint
  tactic 3: the normal's vertical component is computed for lighting and then thrown away; the one-tap AO is not a crevice term
  tactic 6: C is not read. A becomes ACES display RGBA (this file wrote no A)
ADD:
  1. Rosensweig tip pinch — the existing spike field is raised to a power so shoulders fall and crests stay
  2. Crest glint — high crests (p.y) whose normal still points up; Glossiness throws a tight white tip. An upward normal alone would also light the flat sheet.
  3. Three-tap crevice AO — replaces the single map() sample (§12.2E step-count AO, three taps)
FORBID on this file: Gray-Scott, a new palette, audio (the definition does not claim it), a spring
A PACKING: ACES display RGBA. C is not read
```

```
SHADER: bio-touch
IDENTITY (one sentence): bioluminescent Voronoi cells that light only around the pointer, with a pulse, a held curl, and click fronts.
KEEP VERBATIM: glow radius as the influence disk, cell-density Voronoi, color-shift tints, pulse on distance, held curl, click fronts, three-band audio, the existing spectral mix, params Glow Radius / Cell Density / Color Shift / Pulse Speed
MECHANISM INTERROGATION:
  tactic 2: a cell has a nucleus and a wall, and the flash keeps glowing after the stimulus moves on
  tactic 3: Voronoi distance v is collapsed into one soft blob
  tactic 6: C was written and never read. A.a becomes the glow field; A.rgb stays display. Do not ACES A.a
ADD:
  1. Nucleus and cell wall — the same Voronoi distance draws a core and a ring on top of the existing body
  2. Afterglow — C.a holds the previous glow and decays with Pulse Speed, so the flash stays where the pointer was
FORBID on this file: a new spring, a second IQ palette, a fluid solver
A PACKING: display RGB (ACES) with raw glow in A.a. C.a is that glow. writeTexture alpha is coverage, not the field
```

```
SHADER: gen-liquid-metal-chrono-flora
IDENTITY (one sentence): a raymarched six-petal metal flower, chrome lit, with chrono colour in the crevices and a pointer gravity well.
KEEP VERBATIM: smin of the folded torus and the core sphere, six petals, time-wave on effectiveTime, bass/mid on radius and tube, mouse pull, crevice energy from the one-tap AO, spec, params Metallic Shine / Bloom Speed / Temporal Distortion / Chrono Color Intensity
MECHANISM INTERROGATION:
  tactic 2: liquid metal is dark face-on and mirror at the rim; a petal carries veins along its folds
  tactic 3: petal angle and radius are computed inside map and discarded; ndotv is not a Fresnel
  tactic 6: C is not read. A was stored as zeros; it becomes ACES display RGBA
ADD:
  1. Fresnel–Schlick chrome — facing metal darkens, the grazing rim reflects (§12.2F)
  2. Petal veins — a ridge along the existing six-fold angle, lit by that Fresnel
FORBID on this file: a new creature, an IQ palette, a Gray-Scott, reading C as a new sim
A PACKING: ACES display RGBA. C is not read (the old zero store was unused)
```

```
SHADER: mouse-kaleidoscope-tunnel
IDENTITY (one sentence): a kaleidoscope tunnel aimed at the pointer, receding in log-z, with a per-channel spiral split.
KEEP VERBATIM: log-z depthLayer, segment kaleidoscope, spiral on depthLayer, wavelength split of polar.y, three-layer sample, ring glow, click ripple UV kicks, params Tunnel Speed / Mirror Count / Spiral Twist / Tunnel Depth
MECHANISM INTERROGATION:
  tactic 2: a tube is darker off-axis, and forward flight leaves a short streak toward the bore
  tactic 3: polar.x is only a radius for the log; the view never shades the bore
  tactic 6: C is display colour. One step toward the pointer is the flight direction this tunnel already has
ADD:
  1. Bore falloff — cos⁴ of the angle off the tunnel axis, using Tunnel Depth as the bore (§12.2A cos⁴)
  2. Inward flight streak — exact C, a few pixels toward the pointer, amount from Tunnel Speed
FORBID on this file: a mirror-seam hairline (that is the other kaleidoscope), a new spring, an IQ palette
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: gen-aetherial-chromatic-tesseract
IDENTITY (one sentence): a four-fold KIFS box, raymarched, with audio scale, a glow from the march, and a gravity well while the pointer is held.
KEEP VERBATIM: four abs-and-rotate folds, box SDF, bass scale, march glow from Glow Intensity, iridescence amount from Iridescence Shift, gravity from Gravity Strength, diffuse and spec, params Fold Complexity / Iridescence Shift / Gravity Strength / Glow Intensity
MECHANISM INTERROGATION:
  tactic 2: the comment already calls the colour thin-film, but the term is a cosine; a box shows its edges
  tactic 3: each fold's sign is thrown away; the box q is thrown away after the distance
  tactic 5: the gravity well divides the pointer by the resolution, so the warp is numerically dead — restore the same warp in the ray's uv
  tactic 6: C is not read. A becomes ACES display RGBA (this file wrote no A)
ADD:
  1. Fold-count material — reflections already taken tint and roughen the facet (§12.2E)
  2. Thin-film — the existing iridescence becomes a thickness phase, and Iridescence Shift stays the thickness (§12.2F)
  3. Box-edge wear — two q axes near zero catch a metal edge (§12.2E curvature's box form)
FORBID on this file: a new primitive, a liquid solver, a spring, an oil-slick overlay
A PACKING: ACES display RGBA. C is not read
```

```
SHADER: quantum-prism
IDENTITY (one sentence): a honeycomb of prisms over the photo — bevel, grout, spectral bands, oil-slick runners, held twist, click fronts.
KEEP VERBATIM: hex cell pick, facet rotation, zoom, grout and bevel, spectral bands, oil-slick runners and packets, click fronts, history mix, params Intensity / Speed / Scale / Detail
MECHANISM INTERROGATION:
  tactic 2: a prism's split follows wavelength, and the facet rim reflects
  tactic 3: hexDistance is a bevel scalar and never a Fresnel; the RGB offsets are an equal wheel
  tactic 6: C stays display colour; the existing mix stays
ADD:
  1. Cauchy-weighted offsets — the existing RGB wheel is scaled by n(λ)/n(green) (§12.2F Cauchy)
  2. Facet Fresnel rim — grazing hex edges reflect a cool rim and give up a little transmission (§12.2F Fresnel)
FORBID on this file: another oil-slick, another runner system, a new spring, replacing the hex grid
A PACKING: display RGBA in A, matching the existing C read. ACES was missing despite the upgraded-rgba tag; applied as floor, not as an idea.
```

```
SHADER: gen-psychedelic-time-warp-kaleidoscope
IDENTITY (one sentence): a pointer-centred kaleidoscope whose fold is warped by curl noise and by a traveling angle wobble.
KEEP VERBATIM: mirror fold, curl-noise sample offset, bass mirror count, exact-C smear along the fold, three-band glow, applyGenerativePrimaryControls roles (x intensity, y speed, z detail, w mouse), params as that function already maps them
MECHANISM INTERROGATION:
  tactic 2: a time warp has a wave coming back, and a real mirror joint is a dark hairline
  tactic 3: the folded angle's distance to the mirror is overwritten when the UV is rebuilt
  tactic 6: the existing fold smear stays. Do not store a new field in A
ADD:
  1. Counter-rotating warp — a second sine on the same wobble amplitude, opposite direction
  2. Mirror-joint hairline — the unused distance to the mirror plane darkens a thin joint
FORBID on this file: a tunnel bore falloff, a wavelength split (that is the tunnel), a new spring, a new palette
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: rain-lens-wipe
IDENTITY (one sentence): falling lens-drops and streak packets distort the photo, while a pointer wipe clears an advected mask.
KEEP VERBATIM: stable drop cells, advected clean-state in A.r, decay, mouse wipe, click rings, meniscus, beads, streak motion, params Rain Strength / Re-fog Speed / Wipe Radius / Rain Density
MECHANISM INTERROGATION:
  tactic 2: a drop is a thicker lens in the middle, and a rain streak has a head and a tail
  tactic 3: the drop weight is a linear pull; the streak packet is a symmetric gaussian (and pow() of a signed value)
  tactic 6: C.r stays the wipe mask. Do not write colour into A.r
ADD:
  1. Drop-core lens — the existing pull is stronger where the drop mask is thick
  2. Asymmetric streak tail — a sharp head and a long tail replace the symmetric packet
FORBID on this file: a new spring, an oil-slick, changing A.r away from the wipe mask
A PACKING: wipe mask in A.r (raw). Meniscus and bead stay in A.g / A.b. ACES on the display write only
```

```
SHADER: gen-audio-reactive-quantum-pollen
IDENTITY (one sentence): a field of pollen grains, bass pulling them onto a log-spiral, mids orbiting, treble scattering, hold-to-attract.
KEEP VERBATIM: per-cell gather, bass/treble envelopes in A.rg, log-spiral arm, harmonic orbit, treble burst, mouse attract, fbm haze, ACES and dither on the display, params Grain Density / Glow Size / Orbit Speed / Hue Base
MECHANISM INTERROGATION:
  tactic 2: pollen is not a square jitter of soft dots; grains sit on a golden angle and the exine is lobed
  tactic 3: the rest position is a square hash inside the cell; the radius is a smooth gaussian
  tactic 6: C.r and C.g stay the envelopes. Do not write display colour into A
ADD:
  1. Golden-angle rest — each cell's grain sits on a golden angle instead of a square jitter (§12.2E)
  2. Exine lobes — the existing radius is modulated around the grain so the silhouette is spiked
FORBID on this file: a new galaxy, an IQ palette, a spring, tone-mapping the stored envelopes
A PACKING: raw (bassEnv, trebEnv, density, alpha). ACES and premultiply on writeTexture only
```
