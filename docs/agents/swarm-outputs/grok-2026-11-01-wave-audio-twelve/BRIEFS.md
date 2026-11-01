# Grok 4.7 — wave / audio twelve

Written before WGSL edits. Second pass where a file already named ideas: the new pair is additive and uses nouns already in that file. No shared spring, ripple stamp, or IQ palette. Cauchy on audio-reactive-rgb-dispersion only. Deep-water dispersion on sine-wave only. Chroma delay on waveform-glitch only. Anti-halo on audio-reactive-pyramid only. Beat envelope on moire-interference only.

```
SHADER: sine-wave
IDENTITY: multi-frequency sine interference that displaces the photo, with traveling packets, click fronts, crest chroma, and caustic tint.
KEEP VERBATIM: wave amplitude / speed / scale / chroma detail; phase + phase2 carriers; packet envelopes; standing-wave nodes; Stokes drift; click fronts; telemetry A (offset.xy, crest, alpha)
MECHANISM INTERROGATION:
  tactic 2: two wavenumbers already run at nearly the same phase speed; deep water lets the longer one outrun the shorter.
  tactic 3: packetX and packetY already exist and only scale amplitude — the group trough is thrown away.
  tactic 6: C stays the offset/crest history already read back.
ADD:
  1. deep-water dispersion — the longer cross-wave (0.7× k) gets phase speed ∝ 1/sqrt(k); the speed slider still sets the primary (§12.2D)
  2. group shade — between the existing packets the photo sits in the group trough
FORBID: a new spring, a new palette, replacing Stokes or the nodes
A PACKING: telemetry (offset.xy, crest, alpha) unchanged; ACES on writeTexture only
```

```
SHADER: spectral-waves
IDENTITY: luminance-weighted radial ripples from a sprung pointer, with a slower echo, click trains, chromatic split, and caustic persistence.
KEEP VERBATIM: frequency / speed / amplitude / chromatic split; spring [133..138]; wave+echo; click trains; radial safeDir displacement; existing caustic palette; C display-history mix
MECHANISM INTERROGATION:
  tactic 3: cos(phase) is the slope of the ripple and is discarded; aberration is a flat scalar.
  tactic 4: amplitude already scales with luma, but a flat sky and an edge get the same spatial gain.
  tactic 6: C stays premultiplied display history.
ADD:
  1. slope-weighted split — chromatic fringes follow |cos(phase)|, aberration stays the amount
  2. contrast-weighted amplitude — a horizontal luma difference boosts the existing displacement on edges
FORBID: a second spring, a new palette, deep-water dispersion (that is sine-wave)
A PACKING: premultiplied ACES display RGBA (unchanged; C is that history)
```

```
SHADER: digital-waves
IDENTITY: cyber sine interference that displaces, pixelates, posterizes, and scanlines the photo, dark at the standing nodes.
KEEP VERBATIM: intensity / speed / scale / detail roles as the shader maps them; three-sine pattern; standing nodes; crest scanlines; glitch blocks; spring; diagnostic A (wave, depth, ripple, alpha)
MECHANISM INTERROGATION:
  tactic 4: detail sets one posterize step count for the whole frame; the wave it names is already per pixel.
  tactic 7: the pixel lattice is axis-aligned while wavePattern is the shear the effect already computed.
ADD:
  1. crest-following posterize — step count drops toward the standing nodes and holds the detail slider on the crests
  2. wave-sheared pixel grid — the existing pixel snap slides by wavePattern × pixel size
FORBID: chroma-delay line (that is waveform-glitch), a new palette, replacing the nodes or scanlines
A PACKING: raw diagnostic (wave, depth, ripple, alpha) unchanged; ACES on writeTexture only
```

```
SHADER: sonic-distortion
IDENTITY: a superellipse around the pointer filled with radial harmonic waves, four Lissajous sources, a rose amplitude, and an echo trail.
KEEP VERBATIM: frequency / speed / amplitude / radius; superellipse mask; four Lissajous sources; 3-harmonic chaosWave; rose; FBM domain warp; echo mix from C
MECHANISM INTERROGATION:
  tactic 3: chaosWave sums three partials and throws away the beat between the first two.
  tactic 5: a rose curve's gaps are as much the picture as the petals; roseAmp currently only scales the offset.
  tactic 6: C is display colour for the echo — exact load, and ACES must not be stored into it.
ADD:
  1. harmonic beat — |first × second| partials brighten inside the mask the solver already draws
  2. rose-petal nulls — the angular gaps of the existing rose darken the photo
FORBID: a new spring, Voronoi, a moiré beat (that is moire-interference)
A PACKING: pre-ACES linear display RGBA (C is the echo colour); ACES on writeTexture only
```

```
SHADER: audio-reactive-rgb-dispersion
IDENTITY: FFT-centroid RGB dispersion — 5 wavelength taps, spread-widened smear, bass radial vs treble sideways.
KEEP VERBATIM: scale / angle / falloff / original blend; centroid, energy, spread, balance; 5-tap smear; lateral/transverse mix; no ACES (passthrough grade)
MECHANISM INTERROGATION:
  tactic 1: the 5 taps are evenly spaced in wavelength; glass dispersion is Cauchy, n = A + B/λ².
  tactic 4: falloff is a pure radius; a prism splits where the picture actually has an edge.
ADD:
  1. Cauchy tap spacing — endpoints stay on the existing red/blue offsets; interior taps follow n(λ) (§12.2F)
  2. edge-weighted falloff — local contrast along the dispersion axis joins the existing radial falloff
FORBID: ACES (would regrade the photo), a spring, deep-water dispersion
A PACKING: display RGBA passthrough (unchanged, no ACES)
```

```
SHADER: audio-reactive-pyramid
IDENTITY: a three-level DoG sharpen whose coarse/mid/fine gains follow bass/mid/treble, with a silence floor, depth routing, and warm/cool added detail.
KEEP VERBATIM: bass/mid/treble gain and blend; bin ranges; DoG levels; silence floor; depth routing; per-band chroma split; no ACES
MECHANISM INTERROGATION:
  tactic 1: the 5-tap blur already computes a horizontal and a vertical response and then averages them.
  tactic 8: the reconstruction can ring outside the range of the taps it already fetched.
ADD:
  1. anisotropic fine gate — |horizontal − vertical| luma from the existing blur pair quiets isotropic noise
  2. anti-halo envelope — reconstructed RGB stays inside min/max of original and the coarse blur, plus a small blend radius (§12.2A)
FORBID: ACES, Cauchy, a spring, replacing the pyramid
A PACKING: display RGBA (enhanced photo, source alpha); C is not read
```

```
SHADER: audio-voronoi-displacement
IDENTITY: Voronoi cells that slide and glow with audio and shove the photo, with a pointer gravity.
KEEP VERBATIM: cell count / audio reactivity / displacement / color intensity; 3×3 nearest and second site; hash cell shift; mouse gravity and click pulse
MECHANISM INTERROGATION:
  tactic 2: the second site is already computed; the ridge between sites is the cell wall, and it currently appears only when mids are loud.
  tactic 3: the vector from the pixel to the nearest site is computed inside the loop and discarded; displacement uses a random direction instead.
  tactic 6: C is not read. A was not written.
ADD:
  1. site bulge — add a displacement toward the nearest site, scaled by the displacement slider, with bass on top of a silence floor
  2. visible ridge — the existing (dist2 − dist1) edge is a dark wall even in silence; mids still brighten it
FORBID: a spring, stained-glass lead from another batch, fake sin() audio
A PACKING: ACES display RGBA (C is not read; A was missing)
```

```
SHADER: moire-interference
IDENTITY: two radial sines (frame centre and a sprung pointer) whose sum displaces the photo, plus a complexity midpoint wave and click emitters.
KEEP VERBATIM: frequency / distortion / aberration / complexity; spring [133..137]; w1+w2+w3; per-emitter FFT gains; click emitters; cos/sin displacement
MECHANISM INTERROGATION:
  tactic 2: a moiré is the beat between two carriers; the shader adds the carriers and throws the slow envelope away.
  tactic 3: |d1 − d2| is already implied by the two distances.
ADD:
  1. beat-gated displacement — |cos(½(d1−d2)·freq)| scales the existing warp so the moiré bands move the photo (§12.2 family: interference beat, not a copied row)
  2. beat contrast — the same envelope darkens the nulls so the fringes read when distortion is small
FORBID: deep-water dispersion, Cauchy, a second spring, harmonic-beat glow (that is sonic-distortion)
A PACKING: ACES display RGBA (C is not read)
```

```
SHADER: waveform-glitch
IDENTITY: an aliased, VHS-split photo with a Lissajous scope, a cursor-row waveform monitor, and treble block tears.
KEEP VERBATIM: wave / VHS / block-glitch / shadow-mask; aliasing; Lissajous SDF; waveform trace; beam-dwell; block shift; phosphor trail from C; pre-ACES A
MECHANISM INTERROGATION:
  tactic 2: the VHS split is symmetric; tape chroma lags luma in one direction.
  tactic 6: persistence is one scalar; the beam the shader already draws should ghost longer than the field.
ADD:
  1. chroma delay line — R/B mix toward a sample further +x; amount is the VHS slider; the symmetric split stays (§12.2B)
  2. beam afterglow — the existing persistence rises where the Lissajous is bright
FORBID: a new scope motif, standing-wave nodes, Cauchy
A PACKING: pre-ACES linear display RGB + semantic alpha (unchanged)
```

```
SHADER: signal-modulation
IDENTITY: a bright carrier trace across the photo, displaced in Y, with eight spectral bands, chroma split, and click bursts from a sprung origin.
KEEP VERBATIM: base frequency / distortion / scroll speed / color split; carrier sin; band mask; click rings; spring [133..138]
MECHANISM INTERROGATION:
  tactic 2: the carrier is a fixed sine; AM puts the band energy into the excursion.
  tactic 3: cos(phase) is the slope at the zero crossing and is discarded.
  tactic 5: the band readout claimed plasmaBuffer[1..8]; engine FFT bins are extraBuffer[5..12].
ADD:
  1. AM excursion — the carrier amplitude swells with the FFT band under that row; the distortion slider stays the depth
  2. zero-crossing ticks — short vertical marks where the carrier crosses mid-line
FORBID: a Lissajous (that is waveform-glitch), a moiré beat, a new spring
A PACKING: ACES display RGBA (C is not read)
```

```
SHADER: vertical-slice-wave
IDENTITY: vertical strips of the photo shifted in Y by a layered sine, with RGB split, jitter, a seam runner, and click fronts.
KEEP VERBATIM: strip count / wave speed / RGB split / jitter; strip quantization; layered sines; seam runner; click fronts; A = (env, spring.xy, vel) raw
MECHANISM INTERROGATION:
  tactic 2: hard strip edges are the slice; the neighbour's phase is analytic and unused.
  tactic 3: vel_new is the spring speed stored in A.a and never reaches the offset.
ADD:
  1. inter-strip lag — the strip edge blends toward the next strip's layered wave
  2. velocity throw — stored spring speed adds a small extra Y offset
FORBID: ACES on the stored state, a new spring, deep-water dispersion
A PACKING: raw state (env, spring.xy, vel) unchanged; ACES on writeTexture only
```

```
SHADER: wave-halftone
IDENTITY: a hex halftone of the photo whose dots breathe with a multi-oscillator wave, stretched along the wave gradient, with a 15° rosette.
KEEP VERBATIM: dot size / grid density / wave amp / wave speed; hex cell; elliptical stretch; 15° rosette; crest chromatic; ACES display
MECHANISM INTERROGATION:
  tactic 2: real dots gain in the midtones; radius is linear in luma.
  tactic 4: density is one global scalar; the wave amplitude already varies across the frame.
  tactic 5: zoom_params.w is named Wave Speed and only set chromatic amount. Speed scale is normalized so the default 0.2 matches today's timing; chromatic amount stays on that slider.
ADD:
  1. midtone dot gain — radius grows with sqrt(L·(1−L)) on top of the existing luma radius
  2. wave-compressed screen — local density rises with |interference|; the density slider stays the base
FORBID: a new rosette angle, Cauchy, a spring
A PACKING: ACES display RGBA (unchanged)
```
