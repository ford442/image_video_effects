# Idea Cards — Grok (kaleido-chroma ten, 2026-11-15)

Written before the WGSL edits. Ten shaders. Each card adds **two or three** ideas in the existing main path. Saved `params` stay byte-exact. No shared spring, ripple stamp, or new IQ palette.

Formula rule: a §12.2 row is newly applied on at most two files here.

- Thin-film (§12.2F) and energy-conserving glow (§12.2F) are `hyb-iridescent-fbm-glow` only.
- Cauchy (§12.2F) is `chromatic-focus-interactive` and `interactive-fresnel` only. Both already split RGB along an optical axis; the second idea on each file is different (iris blades vs groove draft).
- No Fresnel–Schlick, no cos⁴, no fold-count, no golden-angle, no new spring.

Prelude migration on `chroma-threads-gabor` and `chromatographic-separation` is infrastructure (`migrate_to_prelude.py`). It is not an idea and does not by itself bump `Upgraded:`.

```
SHADER: hybrid-noise-kaleidoscope
IDENTITY (one sentence): domain-warped FBM pushed through a kaleidoscope, then hue-cycled, with an RGB split.
KEEP VERBATIM: fbm2 / value noise, kaleidoscope fold, hueShift, noise-scale / segments / chromatic / hue-speed roles, bass on scale, mids on segments, treble on the split
MECHANISM INTERROGATION:
  tactic 2: a domain warp is noise of noise, and a real mirror joint is a dark hairline
  tactic 3: rUV/gUV/bUV are computed and never sampled; the split is only a sine tint. finalUV is the same dead path
  tactic 6: C is not read. A becomes ACES display RGBA (it stored the pre-tone colour)
ADD:
  1. Second domain warp — one more fbm displacement on the already-warped coordinate, which is the warp the header names
  2. Chromatic domain split — the dead RGB offsets move the fbm domain, so Chromatic Aberration splits the pattern
  3. Mirror joint — the fold's distance to the segment boundary darkens a hairline
FORBID on this file: sampling the photo as the picture, a bore falloff, a breath cycle, a new spring
A PACKING: ACES display RGBA. C is not read
```

```
SHADER: chroma-threads-gabor
IDENTITY (one sentence): horizontal threads that vibrate under the pointer, coloured by three Gabor orientations of the photo.
KEEP VERBATIM: thread rows from density, mouse vibration and held gain, per-channel X offsets, the three Gabor angles, the existing IQ mix of those responses, params Thread Density / Amplitude / Channel Split / Gabor Response. Amplitude still also sets Gabor frequency; Channel Split still also sets sigma
MECHANISM INTERROGATION:
  tactic 2: a thread has a bright filament core, and it should lie along the grain the Gabor already measured
  tactic 3: r0/r45/r90 become a colour and the orientation is thrown away
  tactic 6: C is not read. A becomes ACES display RGBA (this file wrote no A)
ADD:
  1. Grain-following nudge — the dominant Gabor angle shifts the sample along the photo's grain and phases the existing vibration
  2. Filament core — the existing thread mask is brighter on its centerline
FORBID on this file: a new palette, a spring, audio (the definition does not claim it), more Gabor orientations
A PACKING: ACES display RGBA. C is not read
```

```
SHADER: chromatographic-separation
IDENTITY (one sentence): the photo's RGB channels separate along a spun axis, developing upward past a solvent front, with a capillary tail.
KEEP VERBATIM: per-channel depth offsets, spin from the second slider, prism focus around the pointer, solvent-front Rf, capillary tail samples, the four param roles as the shader already maps them (separation, rotation, depth weight, separation mode). Do not rename the JSON viscosity labels
MECHANISM INTERROGATION:
  tactic 2: a band spreads as it travels, and the solvent front is a wet line, not only a gate
  tactic 3: uv.y is only the front test; the tail mix is a constant 0.35
  tactic 6: C is not read. A stays ACES display RGBA
ADD:
  1. Longitudinal diffusion — the existing tail mix widens with distance traveled, and only above the front
  2. Solvent meniscus — a thin wet line on the traveling front, darker and cooler
FORBID on this file: a fluid solver, rewiring the sliders to the JSON viscosity names, a new spring
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: gen-symbiotic-neuro-lattice
IDENTITY (one sentence): a raymarched lattice of pulsing nodes with a gravity well while the pointer is held.
KEEP VERBATIM: grid hash nodes, smin, held gravity, bass on the node radius, camera speed from Speed, Pulse Frequency, metallic diffuse, params Thickness / Gravity Strength / Speed / Pulse Frequency
MECHANISM INTERROGATION:
  tactic 2: a lattice is the links, and a synapse fires as a wave, not all at once
  tactic 3: sdCapsule is defined and never called; pulse is computed and never used
  tactic 6: C is not read. A was zeros; it becomes ACES display RGBA
ADD:
  1. Axons — capsules from each node to its six neighbours, using the unused sdCapsule
  2. Firing wave — Pulse Frequency travels across cell ids and swells the node that is firing
FORBID on this file: a new creature, an IQ palette, a Gray-Scott, a spring, step-count AO (too many extra marches on this 100-step map)
A PACKING: ACES display RGBA. C is not read
```

```
SHADER: breathing-kaleidoscope
IDENTITY (one sentence): a photo kaleidoscope whose petals swell and shrink on a breath, and freeze while the pointer is held.
KEEP VERBATIM: inhale vs exhale petal scale, held-breath freeze (no extraBuffer), FBM warp of the segment count, jewel / axis glow / treble sparkle, film grain, the four param roles (cycle, segments, rotation, max rotation)
MECHANISM INTERROGATION:
  tactic 2: a real breath exhales longer than it inhales, and a petal has a midrib
  tactic 3: sector is 0 on the wedge centerline and is only used for the fold and the sparkle
  tactic 6: C is not read. A stays ACES display RGBA
ADD:
  1. Slow exhale — the existing sine is time-warped so the rising half is ~35% of the cycle
  2. Petal midrib — a vein on the wedge centerline that brightens with the inhale
FORBID on this file: a mirror hairline (that is hybrid-noise-kaleidoscope), a bore falloff, a new spring
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: hyb-iridescent-fbm-glow
IDENTITY (one sentence): domain-warped FBM drives an iridescent glow over the photo, with a viewport rim, a small chromatic split, and OkLab mixing.
KEEP VERBATIM: fbm warp, octave and scale params, Color Shift Speed, Glow Mix, chromaticAberration, fresnelRim, oklabMix, ACES, IGN dither, bass on the warp and the glow
MECHANISM INTERROGATION:
  tactic 2: the description calls this a thin film, but the colour is a cosine; a glow that adds light should take it from the photo
  tactic 3: noise is only a palette index and a brightness
  tactic 6: C is not read. A stays ACES display RGBA
ADD:
  1. Thin-film — noise is thickness and Color Shift Speed drifts it (§12.2F)
  2. Energy-conserving glow — the film darkens the photo it lights (§12.2F)
FORBID on this file: a second palette, a spring, replacing the FBM, a Fresnel–Schlick on top of the existing rim
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: chromatic-focus-interactive
IDENTITY (one sentence): chromatic defocus around the pointer, with a six-blade iris, tangent blur, zone-plate caustics, and the existing oil-slick runners.
KEEP VERBATIM: strength / blur / focus radius / falloff, held squeeze, click iris shells, six-blade highlight, runners, packets, oil-slick, zone-plate caustic, wavelength absorption into alpha, display history mix
MECHANISM INTERROGATION:
  tactic 2: a real iris clips the blur, and the wavelengths already in the file should weight the split
  tactic 3: WAVELENGTH_RED/GREEN/BLUE feed absorption only; blades feed a highlight only
  tactic 6: C stays display colour. The history mix stays
ADD:
  1. Cauchy-weighted offsets — blue's lateral split is larger than red's, from the wavelengths already declared (§12.2F)
  2. Blade-gated circle of confusion — the existing blade signal shortens the blur under the metal
FORBID on this file: another oil-slick, another runner, a new spring, replacing the six-blade term
A PACKING: ACES display RGBA. C is the previous display. ACES was missing despite the upgraded-rgba tag; applied as floor, not as an idea
```

```
SHADER: gen-kaleidoscopic-synapse-bloom
IDENTITY (one sentence): a folded neural mandala — axon runners, a counter-rotating dendrite web, myelin, glia, and vesicle sparks.
KEEP VERBATIM: sector fold, axon and branch, runner fronts, refractory wake, myelin phase, counter-rotating dendrites, synapse bridges, vesicle lattice, astrocyte web, click rings, exact-C smear, the four param roles
MECHANISM INTERROGATION:
  tactic 2: the sheath insulates and the gap fires, and a propagating spike stays narrow
  tactic 3: myelinPhase is only a bead; the runner width is a constant
  tactic 6: the existing history smear stays. Do not store a new field in A
ADD:
  1. Nodes of Ranvier — the gap in the existing myelin phase flares, the bead stays the sheath
  2. Tightening front — the runner's gaussian narrows with radius so the spike stays sharp as it runs
FORBID on this file: a mirror hairline, a new creature, a new palette, a spring
A PACKING: ACES display RGBA (unchanged). C is colour history
```

```
SHADER: hyb-hex-voronoi-distort
IDENTITY (one sentence): the photo is pulled toward hex centres inside the cell, with a Voronoi crack on the F2−F1 ridge.
KEEP VERBATIM: nearest hex, hex mortar gating the pull, animated Voronoi, F2−F1 crack glow, bass/mids/treble roles, pointer falloff, the four param roles
MECHANISM INTERROGATION:
  tactic 2: the Voronoi site is a second centre the cell should pull toward, and a crack should shift the photo, not only glow
  tactic 3: voro.cell and voro.point are stored and used for phase and the crack width only
  tactic 6: C is not read. A stays ACES display RGBA
ADD:
  1. Site pull — the sample target mixes the hex centre with the Voronoi site
  2. Crack kick — the existing F2−F1 ridge offsets the sample along the site direction
FORBID on this file: a glass Fresnel, a caustic ridge, a new spring, a new palette
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: interactive-fresnel
IDENTITY (one sentence): a pointer-centred Fresnel lens — annular grooves, a height-field normal, chromatic dispersion, held squeeze, click shells.
KEEP VERBATIM: annular bump, five-tap normal, held ring spacing, Cauchy-ready dispersion slider, grout, packets, click displacement, specular, the existing view-angle fresnel mix, exact-C history, the four param roles
MECHANISM INTERROGATION:
  tactic 2: a cut Fresnel groove is steeper on the inner face, and dispersion follows 1/λ²
  tactic 3: the bump is symmetric; the RGB scales are a linear ± of the same displacement
  tactic 6: C stays display colour. The history mix stays
ADD:
  1. Cauchy scales — Dispersion is B in n=1+B/λ². Same-direction split stays; blue compresses more than red stretches (§12.2F)
  2. Draft face — the inner half of each existing groove is the steep riser
FORBID on this file: flipping blue to the opposite direction, a new oil-slick, a Schlick layer, a spring
A PACKING: ACES display RGBA (unchanged). C is the previous display
```
