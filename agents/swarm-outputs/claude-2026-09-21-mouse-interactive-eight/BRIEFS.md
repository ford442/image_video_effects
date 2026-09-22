# Batch: interactive-mouse eight (2026-09-21)

Theme: `interactive-mouse` family, all missing the plumbing floor (no `dataTextureA`,
no/partial audio, no `upgraded-rgba` tag). Selected via the §5.1 discovery script in
`agents/CLOUD_UPGRADE.md`, filtered to shaders that already carry a
`shader_definitions/interactive-mouse/*.json` entry.

IDs: `mouse-magnetic-pixel-sand`, `magnetic-rgb`, `mouse-julia-morph`, `cross-stitch`,
`foil-impression`, `interactive-voronoi-web`, `mouse-polarized-light-field`, `poly-art`.

---

```
SHADER: mouse-magnetic-pixel-sand
IDENTITY: pixels behave as iron filings pulled/pushed along a mouse-centered magnetic field
KEEP VERBATIM: magnetStrength/magneticRange/polarity/grainSize param roles, ripple
  secondary-magnet loop, mouse-driven displaced-sample "moved filing" look, sheen/align boost
ADD:
  1. Field-line chaining — sample forward/back along fieldDir and blend, so filings visibly
     link into short chains instead of independent jittered grains
  2. Bass-driven field pulse — plasmaBuffer bass modulates magnetStrength/falloff so the
     filing pattern visibly surges on the beat
  3. Settling residue (C feedback) — a slowly-decaying "settled sand" field stored in
     dataTextureC/A so filings leave faint residue after the mouse moves on
FORBID: springs (ripples already native here), IQ palettes, replacing the sim with a solver
A PACKING: raw sim state — dataTextureC.a = settled residue (decays each frame),
  dataTextureC.rgb = last filing color for continuity. First reader/writer of C in this file.
```

```
SHADER: magnetic-rgb
IDENTITY: mouse-centered magnet splits R (attract) / G (swirl) / B (repel) channel UVs,
  with iron-filing field-line filaments already drawn along the combined field
KEEP VERBATIM: per-channel offsetR/offsetG/offsetB physics, strength/radius/swirl/chaos
  param roles, existing field-line filing overlay
ADD:
  1. (name the existing idea) iron-filing field-line filaments — already implemented,
     now documented in the header
  2. Bass-driven field surge — bass pulses `displace` so channel separation and filings
     pump with the beat
  3. Semantic alpha from channel divergence — alpha now encodes how far the R/G/B sample
     UVs have separated (the magnet's actual local strength), replacing hardcoded 1.0
FORBID: new solver, holographic overlays, replacing the dipole-field idea
A PACKING: display RGBA passthrough into dataTextureA (no C history read — none existed)
```

```
SHADER: mouse-julia-morph
IDENTITY: mouse position sets the Julia constant c; input image is the palette; click
  ripples pin extra Julia configs that blend in
KEEP VERBATIM: currentC/autoC blend, ripple-pinned Julia blending, palette-from-image
  sampling, alpha = normalized escape iteration
ADD:
  1. Orbit-trap filament glow — track the minimum |z| during the existing iteration loop
     and use it to add fine boundary filaments, deepening the fractal's own structure
  2. Bass-driven zoom breathing — bass subtly modulates `zoom` so the fractal pulses with
     the music without touching the param's role
FORBID: reimagining as a different fractal, IQ palettes replacing the image-palette sampling
A PACKING: display RGBA passthrough into dataTextureA (no history)
```

```
SHADER: cross-stitch
IDENTITY: cross-stitch embroidery simulation — thread coverage over Aida cloth, X pattern,
  alpha encodes thread density/coverage
KEEP VERBATIM: baseScale/thickness/mouseRadius/threadDensity param roles, X-pattern distance
  math, thread_alpha derivation chain, depth = mask*threadDensity
ADD:
  1. Half-stitch / full-stitch shading — dark local luma renders a single diagonal
     (half-stitch), bright/mid luma completes the X (full-stitch): the real shading
     technique embroiderers use
  2. Satin thread sheen — a highlight running along the thread's own diagonal direction,
     giving floss its glossy look
  3. Bass-driven weave tension pulse — subtle bass modulation of thread_alpha so the cloth
     breathes gently with the beat
FORBID: replacing the grid/X mechanism, unrelated liquid or generative motifs
A PACKING: display RGBA passthrough into dataTextureA (no history)
```

```
SHADER: foil-impression
IDENTITY: metallic foil sheet with fine bump noise; mouse press reveals the image's own
  relief-embossed normal; brushed-metal spectral shimmer
KEEP VERBATIM: press_factor blend of foil/image normals, spec/brushed/spectral terms,
  radius/roughness/relief/color_mix_amt param roles, existing audio use (audio.x/y/z)
ADD:
  1. Anisotropic brushed-metal streaks — streak direction now follows the local image-relief
     gradient instead of a fixed diagonal, so brushing bends around embossed features
  2. Crinkle micro-fold shimmer at the press boundary — an extra high-frequency fbm octave
     gated at the press edge, where foil catches light at the fold transition
FORBID: replacing the foil/relief normal blend, adding an unrelated solver
A PACKING: display RGBA passthrough into dataTextureA (no history)
```

```
SHADER: interactive-voronoi-web
IDENTITY: Voronoi cell edges rendered as a glowing neural web; charge pulses race each
  strand from its owning cell; animated cell points act as firing synapse nodes
KEEP VERBATIM: web/edgeVal geometry, thickness/scale/glow/pulseSpeed param roles, existing
  per-cell pulse-racing + synapse node mechanism
ADD:
  1. (name the existing idea) living neural web — pulses racing strands, firing synapse nodes
  2. Bass-synchronized firing bursts — a global bass hit triggers a synchronized flash across
     active synapse nodes, layered on top of the independent per-cell firing
FORBID: replacing the Voronoi web with a different generative motif
A PACKING: display RGBA passthrough into dataTextureA (no history)
```

```
SHADER: mouse-polarized-light-field
IDENTITY: mouse sets polarization angle; birefringence produces interference fringes and
  moiré; ripples spawn transient polarization vortices; alpha stores phase
KEEP VERBATIM: Malus's-law filtering, birefringence/fringeDensity/colorMode param roles,
  ripple vortices, mouseDown analyzer flash, alpha = phase
ADD:
  1. Chromatic fringe dispersion — per-channel retardation now also shifts fringe *density*
     (not just hue angle), producing true rainbow-edged interference fringes like real
     birefringent film
  2. Treble-driven fringe shimmer — treble adds high-frequency jitter to fringeDensity so
     fringes visibly sparkle on cymbals/hats (file had zero plasmaBuffer use before)
FORBID: replacing the optics model, IQ palettes
A PACKING: display RGBA passthrough into dataTextureA (no history)
```

```
SHADER: poly-art
IDENTITY: low-poly Voronoi facet abstraction of the source image; cells densify (fisheye)
  toward the mouse
KEEP VERBATIM: cellSize/edgeWidth/randomness/influence param roles, fisheye distortion,
  per-cell flat texture sampling
ADD:
  1. Finish the facet edges — the file already attempted a 2nd-closest-point border search
     that was abandoned as dead code; implement the perpendicular-bisector distance so
     edgeWidth actually draws crisp polygon borders
  2. Per-facet flat-shading — a hashed pseudo-normal per cell lit from a fixed direction,
     giving the genuine low-poly faceted-lighting look instead of flat texture color
  3. (bug fix, not a creative idea) add the missing bounds guard — the file had none
FORBID: replacing Voronoi facets with a different tessellation motif
A PACKING: display RGBA passthrough into dataTextureA (no history)
```
