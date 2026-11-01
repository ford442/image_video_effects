# Grok 4.7 — light / optical twelve

Written before WGSL edits. Second pass where a file already named ideas: the new pair is additive and uses nouns already in that file. No shared spring, ripple stamp, or IQ palette.

Formula cap for this batch: Beer–Lambert on volumetric-god-rays and velvet-scatter-bloom only. Cauchy on pp-bloom and volumetric-god-rays only. Energy-conserving bloom on pp-bloom only. Soft inverse-square and Airy on kimi-spotlight only. Fresnel–Schlick on spec-spherical-harmonics-light only. Rayleigh on alpha-aurora-bands only. Halation on light-leaks only.

```
SHADER: divine-light
IDENTITY: golden volumetric shafts marched from the photo toward a pointer light, with dust and a halo.
KEEP VERBATIM: ray intensity / decay / density / brightness filter; 16-step march; HG phase; depth occlusion; golden halo; dapple; exact C persistence
MECHANISM INTERROGATION:
  tactic 2: forward-scattered shaft light is redder than side scatter; airlight also veils the picture under the beam.
  tactic 3: hgPhase is computed per step and then thrown away as a scalar weight.
  tactic 8: the shaft adds light; the photo under it should wash out, not only get brighter.
ADD:
  1. phase-warmed scatter — the existing HG weight tints the shaft from pale gold toward amber when the step is forward
  2. aerial veiling — ray luma lifts and desaturates the source under the shaft
FORBID: a second phase function, Beer–Lambert (that is volumetric-god-rays), springs, new ripples
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: neon-light
IDENTITY: photo edges as hot neon tubes, blackbody by temperature, with phosphor that lingers.
KEEP VERBATIM: base temperature / edge heating / emission gain / thermal fog; blackbodyRGB; Schlick fresnel; Sobel tube tangent; phosphor = 0.78·C + emission
MECHANISM INTERROGATION:
  tactic 2: a real tube is brightest in the glass wall and dimmer in the gas bore; leftover phosphor cools through red as it fades.
  tactic 3: edgeStrength is a ridge magnitude with no shoulder.
  tactic 6: C is raw phosphor RGB. Recolor that leftover; do not change the packing.
ADD:
  1. bore and sheath — the hottest Sobel core dims and a shoulder band carries the wall
  2. cooling phosphor — leftover C energy is recolored toward 1200 K, fresh emission stays at the live temperature
FORBID: HSV neon (that is neon-pulse-edge), a new spring, IQ palette
A PACKING: raw phosphor RGB in A; ACES on writeTexture (unchanged)
```

```
SHADER: volumetric-god-rays
IDENTITY: a long radial march of the photo from the pointer, with dust, Mie phase, and a sun disk.
KEEP VERBATIM: density / decay / weight / exposure; 48-step march; luma occluder; Mie phase; sun-disk core; per-channel accum
MECHANISM INTERROGATION:
  tactic 1: decay is a constant per step; the dust factor already computed should thicken the optical depth.
  tactic 2: the existing R-up/B-down split is dispersion. Wavelengths should sample different points along the ray.
ADD:
  1. dust Beer–Lambert — each step is decay · exp(−σ·dust·density), decay slider still the base (§12.2F)
  2. Cauchy split along the march — R and B sample opposite offsets on the existing ray, scales from §12.2F Cauchy
FORBID: HG (divine-light already owns that phase), energy-conserving bloom, springs
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: light-leaks
IDENTITY: film light leaks — warm blobs screened over the photo, one under the pointer, two drifting.
KEEP VERBATIM: intensity / warmth / leak size / drift speed in that order; mouse blob; two autonomous blobs; white-hot core; screen blend
NOTE: the on-disk WGSL is a halftone (dot size, posterize, ink) that does not implement those param names. This pass restores the leak blobs the JSON names, then adds the ideas. The halftone is not the catalog effect.
MECHANISM INTERROGATION:
  tactic 5: leaks enter from the rebate, the core is white, the shoulder is a dye fringe, and the leak fogs the emulsion red.
  tactic 2: halation around the leak, not a new motif.
ADD:
  1. rebate streak — a leak from the frame edge, width from leak size, drift from the speed param, same screen blend
  2. dye-layer fringe — mid-strength leak shifts toward magenta; the white core stays
  3. halation — red-biased glow around the leak field, core slightly bleached (§12.2A)
FORBID: keeping the halftone, springs, IQ palette, Beer–Lambert
A PACKING: ACES display RGBA (C was not read)
```

```
SHADER: kimi-spotlight
IDENTITY: a sprung spotlight that reveals saturated color inside the beam and leaves the outside dim and grey.
KEEP VERBATIM: size / softness / edge darkness / color boost; desaturate-outside mix; spring in extraBuffer[133..138]; click rings; beam rim; hotspot; treble-bin flicker
MECHANISM INTERROGATION:
  tactic 2: a real beam is brighter at the axis than at the gate, and the focus throws diffraction rings.
  tactic 3: dist and the hotspot are already computed.
ADD:
  1. soft inverse-square inside the existing smoothstep gate (§12.2F) — the edge radius stays the size param
  2. Airy rings on the existing hotspot (§12.2F)
FORBID: a new spring, a second reveal mask, Cauchy
A PACKING: ACES display RGBA (was untonemapped display; C is not read as a field)
```

```
SHADER: alpha-aurora-bands
IDENTITY: stacked altitude curtains of oxygen green, oxygen red, and nitrogen blue over the photo.
KEEP VERBATIM: intensity / curtain frequency / turbulence / wind speed; 5-layer fbm curtains; auroraEmission lines; field-aligned folds; green-line treble shimmer
MECHANISM INTERROGATION:
  tactic 2: curtains are brightest along the lower border; the air under them scatters blue.
  tactic 3: altitude is computed per layer and then only used to pick the emission line.
ADD:
  1. lower-border brightening — emission lifts where altitude is already in the nitrogen foot
  2. Rayleigh limb — blue scatter under the curtain from the emission already summed (§12.2F)
FORBID: ribbons and reconnection sparks (those belong to aurora_borealis), HG phase
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: aurora_borealis
IDENTITY: a handful of flowing color ribbons, stars, a crest corona, and bass-triggered sparks.
KEEP VERBATIM: num ribbons / flow speed / ribbon width / glow; ribbon y-sum; curl; corona at the crest; reconnection from C.a bass envelope; mouse pull
MECHANISM INTERROGATION:
  tactic 2: a dim red proton arc sits equatorward of the main curtain; stars do not shine through the ribbon.
  tactic 3: ribbonPos.y and auroraCoverage are computed and not reused that way.
ADD:
  1. equatorward proton arc — a thin red line below the first ribbon, width from the ribbon-width param
  2. star occultation — the existing star field is multiplied by (1 − coverage)
FORBID: altitude emission lines (alpha-aurora-bands), Rayleigh, a new ribbon count param
A PACKING: ACES display RGB; A.a remains the smoothed bass envelope (unchanged)
```

```
SHADER: pp-bloom
IDENTITY: HDR threshold bloom on the photo, with an optional horizontal anamorphic streak.
KEEP VERBATIM: intensity / anamorphic / threshold / quality tap count; soft-knee hue-preserving extract; separable blur; horizontal streak
MECHANISM INTERROGATION:
  tactic 8: the blur adds light the source never lost.
  tactic 2: an anamorphic streak fringes red and blue along its length.
ADD:
  1. energy-conserving composite — a fraction of the spread is taken from the source (§12.2F)
  2. Cauchy fringe on the existing horizontal streak only (§12.2F)
FORBID: a radial god-ray march, springs, a second blur kernel
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: velvet-scatter-bloom
IDENTITY: dark regions of the photo scatter like velvet pile, with a nap sheen and a held-pointer crush.
KEEP VERBATIM: scatter / bloom / subsurface / light angle; velvetScatter taps; darkMask; nap direction from light angle; held crush; edge bloom
MECHANISM INTERROGATION:
  tactic 2: red light leaves the pile farther than blue; the sheen has a dark trough beside the peak.
  tactic 3: napDir and the per-tap radius are already computed.
ADD:
  1. spectral subsurface — far taps weight red, near taps weight blue, inside the existing scatter loop (§12.2F Beer–Lambert per channel)
  2. nap trough — a dark band beside the existing sheen peak, same napDir
FORBID: anamorphic bloom, inverse-square spotlight, a new scatter solver
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: neon-pulse-edge
IDENTITY: Sobel edges as a cycling neon line with a pulse and a wide halo.
KEEP VERBATIM: threshold / glow radius / pulse speed / cycle rate; HSV from edge angle; gradient-oriented rim; treble sub-harmonic; A.r = edge magnitude for the halo
MECHANISM INTERROGATION:
  tactic 6: A.r is stored so the halo can read last frame's edge. It does not linger on its own.
  tactic 7: the pulse is a global sine; the Sobel tangent is the direction a pulse would travel.
ADD:
  1. edge afterglow — store max(edge, 0.86·previous edge) so the halo trails the ridge
  2. traveling pulse — brightness runs along the Sobel tangent at the existing pulse speed
FORBID: blackbody tubes (neon-light), bore/sheath, springs
A PACKING: edge magnitude in A.r (now the trailed magnitude); ACES display on writeTexture
```

```
SHADER: interactive-film-burn
IDENTITY: a sprung hole burned through the photo, with a fire rim, click brands, and embers running the edge.
KEEP VERBATIM: burn radius / speed / grain / edge glow; spring extraBuffer[133..138]; click brands; ember conveyor and packets; oil-slick fire gradient; A = [hole, fire, smoke, alpha]
MECHANISM INTERROGATION:
  tactic 2: film blisters at the rim before it opens, and smoke leaves upward.
  tactic 6: C already stores hole and fire. The 0.12 mix reads those masks as color. Use them as scar and cooling ember instead.
ADD:
  1. emulsion blister — a radial UV warp in the existing glow-width ring, before the photo sample
  2. rising smoke — the smoke mask mixes a photo sample shifted upward
  3. scar and cooling ember — hole lingers from C.r, fire cools from C.g; stop mixing mask RGB as a photo
FORBID: halation (light-leaks), a new spring, changing the A packing
A PACKING: [hole, fire, smoke, alpha] diagnostic (unchanged). ACES on writeTexture only.
```

```
SHADER: spec-spherical-harmonics-light
IDENTITY: local SH coefficients from the photo, evaluated on a depth normal, plus a specular lobe.
KEEP VERBATIM: SH strength / normal scale / specular power / ambient; 9-coeff evaluateSH; depth Sobel normal; held-pointer normal nudge; L1 from the color gradient
MECHANISM INTERROGATION:
  tactic 1: the eval is radiance. Irradiance convolution damps L1 and L2 against L0.
  tactic 3: the L1 coefficients are the dominant light direction and are not used for the specular, which aims at a fixed vector.
  tactic 2: a dielectric surface gets Fresnel at grazing.
ADD:
  1. cosine-lobe irradiance — L1 scaled by 2/3 and L2 by 1/4 relative to L0, same coefficients
  2. specular from L1 — light direction is the luminance of coeffs 3, 1, 2
  3. Fresnel–Schlick on that specular (§12.2F)
FORBID: a new SH band, springs, god-ray march, IQ palette
A PACKING: ACES display RGBA. C is not read; the old A stored raw shLight and spec that this shader never loaded.
```
