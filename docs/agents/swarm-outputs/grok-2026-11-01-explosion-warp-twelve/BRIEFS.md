# Grok 4.7 — explosion / warp twelve

Written before WGSL edits. Second pass where a file already named ideas: the new pair is additive and uses nouns already in that file. No new spring. No shared IQ palette, ripple stamp, or Cauchy on more than one file.

Formula cap for this batch: Cauchy (§12.2F) on hyper-space-jump-blackbody only. Schmitt lock (§12.2B) on circuit-breaker-explosion only. N-wave on chromatic-shockwave only. Core-spend (desaturate under light the effect adds) on elastic-chromatic-explosion and cursor-aura-explosion only.

```
SHADER: cmyk-halftone-explosion
IDENTITY: CMYK halftone of the photo, screens thrown apart by a prism at the pointer and by click shocks.
KEEP VERBATIM: Dot Density / Angle Offset / Channel Spread / Prism Strength; angles 15/75/0/45 plus those offsets; sqrt(ink) dot radius; subtractive composite; per-channel prismDisplace; per-channel shock phase
MECHANISM INTERROGATION:
  tactic 2: a blown screen throws the colour plates; the black plate stays nearer registration.
  tactic 7: the shock already has a direction. Round dots should stretch along it.
  tactic 3: cOffset..kOffset are summed and then only added to the sample UV.
ADD:
  1. black plate holds registration — K prism and K shock are a fraction of the CMY throw; CMY offsets stay
  2. shock-stretched dots — the cell distance is an ellipse along the summed shock, circle when no shock
FORBID: midtone dot gain and ink trap (those are cmyk-halftone-interactive), a new spring, IQ palette
A PACKING: ACES display RGBA (C was not read)
```

```
SHADER: elastic-chromatic-explosion
IDENTITY: red and blue lag behind green through an EMA, with a sprung prism and click shocks.
KEEP VERBATIM: kernel roles of zoom_params — x red lag, y blue lag, z prism, w saturation (JSON labels say Explosion Force / Chromatic Spread / Elastic Snap / Trail Decay; do not rewire); spring in extraBuffer[133..138]; exact C EMA; caustic from |R−G| and |B−G|; bounded shocks
MECHANISM INTERROGATION:
  tactic 2: an elastic prism overshoots, so the lag should smear along the spring velocity already stored.
  tactic 8: the caustic adds light the lagged pixel never lost.
ADD:
  1. velocity smear — red samples shift along spring_vel, blue against it; the EMA lags stay
  2. fringe spends the core — where the existing caustic is high, the lagged colour desaturates before the highlight is added
FORBID: retargeting the four sliders to the JSON labels, a second spring, Cauchy (blackbody owns it)
A PACKING: ACES display RGBA (unchanged; C is last frame's display)
```

```
SHADER: interactive-rgb-split-explosion
IDENTITY: a falloff-gated RGB split around the pointer, plus tangential prism displacement and click shocks.
KEEP VERBATIM: Prism Strength / Falloff / Ripple Strength / Saturation Boost; falloff 0 leaves the split ungated; tangential prismDisplace; per-channel shock phase; mids corona ring
MECHANISM INTERROGATION:
  tactic 3: the header's radial split is not in the kernel — only the tangential prism is. The vector to the pointer is already computed.
  tactic 4: Falloff is one smoothstep. The lip of that window is where a prism fringe belongs.
ADD:
  1. radial split along the existing pointer vector, same `amount` as the tangential prism, still gated by Falloff
  2. falloff lip — a ring at the existing smoothstep edge multiplies `amount`; Falloff 0 still skips the gate
FORBID: core-spend (elastic and cursor-aura), a new spring, per-channel history
A PACKING: ACES display RGBA (C was not read)
```

```
SHADER: cursor-aura-explosion
IDENTITY: a round cursor aura that splits RGB inside the disc and draws a spectral ring on the rim.
KEEP VERBATIM: Radius / Intensity / Prism Strength / Dispersion; disc mask; 4-tap edge colour inside the disc; existing cosine ring; click shocks; tangential prism
MECHANISM INTERROGATION:
  tactic 2: a prism throws colour at the limb, not uniformly through the disc.
  tactic 8: the core glow adds violet on top of a photo that never darkened.
ADD:
  1. limb dispersion — prism strength peaks on the existing rim and stays weaker in the core
  2. core spends the photo — under the existing pointer glow the photo drops toward a darker luma before the glow is added
FORBID: a new spring, a second ring palette, Cauchy
A PACKING: ACES display RGBA (C was not read)
```

```
SHADER: chronos-brush-explosion
IDENTITY: a held brush freezes the photo into C, and the frozen paint splits into a prism.
KEEP VERBATIM: Brush Size / Decay / Prism Strength / Dispersion; deposit only while held and inside the brush; alpha *= mix(0.9, 1.0, Decay); mix live toward frozen by alpha; click shocks scaled by freeze
MECHANISM INTERROGATION:
  tactic 3: edgeMask already peaks at alpha 0.5 and is only used to saturate.
  tactic 2: a thawing freeze lets go at the rim first. The comment claims edge dispersion; the kernel scales the prism by the whole freeze.
  tactic 6: C is the frozen photo. Read it with textureLoad, not a filtering sampler.
ADD:
  1. rim prism — dispersion follows edgeMask; the frozen interior keeps a smaller share of Prism Strength
  2. rim thaw — after the existing Decay multiply, alpha drops faster where edgeMask is high
FORBID: a spring, ACES on the stored freeze, wet-edge darkening from the paint batch
A PACKING: raw freeze RGBA in A (rgb frozen photo, a coverage). ACES on writeTexture only.
```

```
SHADER: circuit-breaker-explosion
IDENTITY: a circuit grid and photo edges that overload near the pointer, with prism-split samples and node flashes.
KEEP VERBATIM: Grid Scale / Overload / Jitter / Prism Strength; grid lines and hash nodes; Sobel edge; spectral recolour of traces; scanline; click shocks; jitter inside the influence radius
MECHANISM INTERROGATION:
  tactic 2: a trace drops voltage with distance from the fault. A contact chatters and then holds, instead of flickering for the whole influence disk.
  tactic 6: C is unread. A.a can hold the contact without changing the grid.
ADD:
  1. voltage drop — existing trace glow fades with pointer distance; Overload shallows that falloff
  2. contact latch (§12.2B) — node flash holds from C.a between a high and a low influence, and releases outside it
FORBID: a new spring, replacing the grid, Cauchy
A PACKING: A.rgb ACES display; A.a contact latch (only C.a is read back)
```

```
SHADER: mouse-chromatic-explosion
IDENTITY: one displaced sample of the photo, tinted by wavelengthToRGB, not three channel UVs.
KEEP VERBATIM: Prism Strength / Dispersion / Ripple Chromatics / Saturation Boost; single UV; tangential prism; one ripple offset; wavelengthToRGB mix; bass pulse; treble wobble; depth blend
MECHANISM INTERROGATION:
  tactic 2: the field is pure shear. An explosion also pushes along the radius already used for the angle.
  tactic 3: prismAngle is computed and then thrown away; the wavelength is a single global mix.
ADD:
  1. radial push added to the existing tangential deflection, same prismStrength
  2. spectrum wheel — wavelengthToRGB follows prismAngle around the pointer; Dispersion still scales the range
FORBID: per-channel UV samples, a spring, Cauchy
A PACKING: ACES display RGBA (C was not read)
```

```
SHADER: chromatic-shockwave
IDENTITY: continuous rings of displacement from a sprung pointer, with click shells and Beer–Lambert channel alpha.
KEEP VERBATIM: Wave Speed / Frequency / Aberration / Ring Count; 8-layer harmonic stack; spring in extraBuffer[133..138]; click shells; Beer–Lambert alphas; sector plasmaBuffer voice
MECHANISM INTERROGATION:
  tactic 2: a shock is an N-wave, not a symmetric sine. Aberration in glass peaks where the front is steepest.
  tactic 3: `wave` is one scalar for the whole displacement.
ADD:
  1. N-wave — the summed ring is sharpened on the positive crest and left alone on the rarefaction
  2. crest-gated aberration — Aberration stays the scale, but the continuous wave's channel offset peaks where |N-wave| is high; click shells keep their own offset
FORBID: a second Beer–Lambert, Cauchy, a new spring
A PACKING: ACES display RGBA (C was not read as a field)
```

```
SHADER: zoom-burst
IDENTITY: a radial zoom streak with rotational shear, highlight comets, and a ghost at the end of the travel.
KEEP VERBATIM: Burst Length / Sample Quality / Spin / Chroma; comet weights; end-of-streak ghost; spring; click packets; exact C mix; speed-line tint
MECHANISM INTERROGATION:
  tactic 2: a zoom shutter smears colour off the far taps and leaves dark gaps between the speed lines it already draws.
  tactic 3: `t` along the streak and the speed-line sine are computed and only brighten.
ADD:
  1. spoke gaps — the existing 8-blade speed-line phase darkens the burst between blades
  2. far-streak chroma loss — taps mix toward their luma as `t` increases; the head and the dwell ghost stay coloured; Chroma still boosts the composite
FORBID: a new spring, Cauchy, another comet weight
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: hyper-space-jump
IDENTITY: a radial streak tunnel toward the pointer, brightness-weighted, with a vignette.
KEEP VERBATIM: Jump Strength / Streak Decay / Chromatic Spread / Vignette Size roles (y, z, and w are currently multiplied by zero — wire them back into decay, the R/B offset, and the vignette); 30-tap radial loop; streak alpha; depth cleared to 0
MECHANISM INTERROGATION:
  tactic 2: the header already claims a blue shift at the rim. The kernel never tints.
  tactic 6: feedbackPacking says A/C is the trail. C is not read.
ADD:
  1. rim blue-shift — the finished streak tints toward blue where dist is large, scaled by Jump Strength
  2. tunnel afterimage — a small mix of exact C into the streak before ACES, and A stores that display
FORBID: blackbody temperature (that is hyper-space-jump-blackbody), Lorentz gamma, a spring, helical rewrite
A PACKING: ACES display RGBA. Depth store stays 0.
```

```
SHADER: hyper-space-jump-blackbody
IDENTITY: the same radial tunnel, with streak luma mapped through blackbody temperature.
KEEP VERBATIM: Jump Strength / Low Temperature / High Temperature / Chromatic Spread; 24-tap loop; Lorentz gammaStretch; inward beaming; blackbodyColor; pre-ACES store
MECHANISM INTERROGATION:
  tactic 2: the chromatic offset is symmetric. Glass dispersion is not: blue bends more than red.
  tactic 6: A is pre-ACES heat. Last frame's heat should cool toward red, not be discarded.
ADD:
  1. Cauchy split on the existing chrom offset (§12.2F) — Chromatic Spread still sets the magnitude; R and B scales follow 1/λ²
  2. cooling afterglow — exact C, still pre-ACES, mixed in cooler and redder before the vignette
FORBID: replacing blackbodyColor, a spring, N-wave, energy-spend desat
A PACKING: pre-ACES RGB + vignette alpha (unchanged). ACES on writeTexture only.
```

```
SHADER: warp-drive
IDENTITY: an Alcubierre streak of the photo, with Doppler tint, star seeds, a packet ring, and click fronts. File is warp_drive.wgsl.
KEEP VERBATIM: Warp Speed / Prism Split / Core Glow / Blur Quality; alcubierre sign change at t = 0.5; star hash; oil-slick packet; click fronts; diagnostic A (dist, warpFactor, dopplerMag, alpha)
MECHANISM INTERROGATION:
  tactic 3: the sign change at t = 0.5 is the bubble wall and is not drawn.
  tactic 2: Doppler is currently left-of-screen versus right. A warp's Doppler is bow versus wake along the streak.
ADD:
  1. bubble wall — a thin spike in the existing integral where t crosses 0.5, brightness from Core Glow
  2. bow-blue / wake-red — the existing doppler mix follows t instead of dirSafe.x
FORBID: writing display colour into A, a spring, a second oil-slick, blackbody
A PACKING: diagnostic vec4(dist, warpFactor * 0.1, dopplerMag, finalAlpha) (unchanged; C is not read)
```
