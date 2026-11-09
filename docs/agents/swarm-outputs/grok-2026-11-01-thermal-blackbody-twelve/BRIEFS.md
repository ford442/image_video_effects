# Grok 4.7 — thermal / blackbody twelve

Written before WGSL edits. Second pass where a file already named ideas: the new pair is additive and uses nouns already in that file. No new spring. No shared IQ palette, ripple stamp, narcissus, isotherm, or well-bloom copied across the batch.

Formula cap: local-contrast / FLIR detail (§12.2A) on thermal-vision only. Energy-conserving bloom (§12.2F) on spec-blackbody-thermal only. Beer–Lambert veil (§12.2F) on heat-haze-gpt52 only. Binomial heat kernel (§12.2D family, heat stencil) on sim-heat-haze-blackbody only. No Cauchy. No Schmitt. No thin-film. No new extraBuffer spring.

```
SHADER: thermal-vision
IDENTITY: a false-color thermal camera — luma through black → blue → magenta → red → yellow → white, blackbody only on the hot end, with sensor noise and a blur.
KEEP VERBATIM: Heat Sensitivity / Color Range / Sensor Noise / Thermal Blur; thermal_gradient stops; blackbody mix only above the hot shoulder; split-tone; vignette; ACES then hue-preserve; IGN dither. The pointer is not part of this camera (JSON "mouse-driven" is a false tag).
MECHANISM INTERROGATION:
  tactic 2: a FLIR draws isotherms on the heat it already measured, and a "detail" mode is an unsharp of that same heat.
  tactic 3: the 5-tap luma average is computed and then only blended by Thermal Blur. The high-pass is thrown away.
  tactic 6: C is not read. A stays display RGBA.
ADD:
  1. isotherms — thin white contours where the existing heat scalar crosses steps; Color Range still sets how many steps
  2. detail unsharp — the 5-tap high-pass adds back into heat; Thermal Blur still only controls the blur mix (§12.2A local contrast, thermal-camera AGC form)
FORBID: NUC bars (thermal-vision-blackbody), a pointer heat source, a spring, IQ palette
A PACKING: ACES display RGBA (C is not read)
```

```
SHADER: thermal-vision-blackbody
IDENTITY: Planck thermal vision — luma to Kelvin, blackbody color, mouse heat while held, a glow of neighbor temperatures.
KEEP VERBATIM: Temperature Low / High / Sensor Contrast / Color Shift; blackbodyColor; NUC row noise and calibration bars; hot-object lag from C.a; 12-tap glow; mouse heat only while held; raw thermal RGB + T/15000 in A
MECHANISM INTERROGATION:
  tactic 5: an uncooled thermal lens shows narcissus, the cold detector reflected at the center of the field.
  tactic 8: the glow is mixed at a flat 30%. A saturated well should spill; a mid tone should not.
ADD:
  3. narcissus — a soft cold hole at the field center, stronger when Sensor Contrast is high; applied to the displayed Kelvin after the lag, not written into A.a
  4. well overflow — the existing glow mix rises only as normalized T approaches the top of the range
FORBID: false-color isotherms (thermal-vision), dwell under the pointer (thermal-touch), a spring
A PACKING: raw thermal RGB + normalized T (unchanged)
```

```
SHADER: thermal-touch-blackbody
IDENTITY: a pointer iron on the photo — blackbody heat, a conduction halo, buoyant streaks, click heat rings, Original Blend back to the picture.
KEEP VERBATIM: Heat Intensity / Heat Radius / Ambient Temperature / Original Blend; halo; click fronts; buoyant history sample; cooling-ember tint; ACES display RGB with temp/15000 in alpha
MECHANISM INTERROGATION:
  tactic 6: C.a is already temperature. The streak reads a pixel above; the pixel under the iron forgets as soon as the pointer moves.
  tactic 8: the iron adds blackbody on top of a photo that never chars.
ADD:
  3. dwell — under the existing mouse heat, temperature keeps last frame's C.a so a held contact climbs and a lifted one cools in place
  4. scorch — under that same heat the display drops toward a dark oxide before Original Blend restores the photo
FORBID: narcissus, NUC bars, a new spring, retargeting Original Blend
A PACKING: ACES display RGBA + tempNorm alpha (unchanged)
```

```
SHADER: spec-blackbody-thermal
IDENTITY: luma-to-Kelvin blackbody with a depth-gated pointer, isotherms, ember filaments, click rings, and an ember that persists in C.
KEEP VERBATIM: Low / High Temperature, Thermal Intensity, Ember Glow; depth conduction; isothermRing and emberFilament; Wien fringe; chroma mix by tempNorm; persistent ember from C; glow loop gated by Ember Glow; raw HDR in A
MECHANISM INTERROGATION:
  tactic 2: a thin edge of an ember sheds heat faster than the core. tempGrad is already computed for the Wien fringe.
  tactic 8: Ember Glow adds a neighborhood of blackbody and never takes it from the pixel that glowed.
ADD:
  3. edge cooling — emberDecay, still set by Ember Glow, drops where tempGrad is high
  4. energy-conserving glow (§12.2F) — after the existing glow mix, the core is pulled toward a dimmer luma by that mix
FORBID: narcissus, dwell scorch, a spring, changing the isotherm exponents
A PACKING: raw thermal HDR rgb + tempNorm alpha (unchanged)
```

```
SHADER: sim-heat-haze-blackbody
IDENTITY: a temperature field with ground heat, counted sources, mouse heat, image displacement along ∇T, and blackbody where the field is hot.
KEEP VERBATIM: Temperature Intensity / Convection Speed / Distortion Strength / Heat Source Count; ground at uv.y near 0; source loop; cooling 0.98; Schlieren signed brightness; plume shear on displacement.x; raw T in A.r
MECHANISM INTERROGATION:
  tactic 1: the 3×3 is a box. Heat conducts more across edges than across corners.
  tactic 2: Convection Speed moves the photo, not the temperature. The plume should carry T off the ground.
ADD:
  3. binomial heat kernel — same 3×3 loads, weights 4/2/1, still cooled by 0.98
  4. rising temperature — a pixel takes heat from toward the ground (smaller y), mixed by Convection Speed and how hot that sample is
FORBID: the inferior-mirage reflection (heat-haze-gpt52), a spring, storing display color in A
A PACKING: raw temperature in A.r (unchanged)
```

```
SHADER: heat-haze-gpt52
IDENTITY: fbm heat haze with chromatic split, an inferior mirage under a ground line, a boundary layer, and a held pointer pool.
KEEP VERBATIM: Haze Intensity / Rise Speed / Turbulence / Chromatic Split; groundY 0.78; mirageSample flip; boundary boost; hot patch; filaments, packets, click rings; 22% C blend; display RGBA
MECHANISM INTERROGATION:
  tactic 5: a road mirage throws a bright glitter right on the ground line, broken into the pools the shader already has.
  tactic 2: the boundary layer is thicker at the ground. Looking through it veils the picture (Beer–Lambert), it does not only warp it.
ADD:
  4. ground-line glitter — a thin highlight on groundY, masked by the existing pools
  5. boundary veil (§12.2F Beer–Lambert) — optical depth from the existing boundary excess, warm gray, stronger with Haze Intensity
FORBID: a temperature-field solver, narcissus, a new spring, another inferior-mirage copy
A PACKING: display RGBA, C blended at 22% (unchanged)
```

```
SHADER: honey-melt-blackbody
IDENTITY: hex cells of honey — velocity, thickness, temperature — amber Beer color, blackbody when hot, a pointer that pulls and swirls.
KEEP VERBATIM: Grid Size / Melt Radius / Distort Strength / Softness and their mappings (cell scale, melt radius, pull, softness); hex metric; gravity; mouse pull and swirl; click rings; packing velocity.xy, thickness, temperature; Beer amber
MECHANISM INTERROGATION:
  tactic 2: honey on a drip thins where it is moving fast and holds its body where it is slow.
  tactic 2 again: cool, thick honey skins over and hides the glow.
ADD:
  1. drip neck — thickness scales down with the speed already in velocity; a still cell keeps the thickness the solver wrote
  2. wax crust — low temperature and high thickness cloud the blackbody toward a pale amber skin
FORBID: Marangoni (melting-oil), a hex energy shield, a spring, changing the packing
A PACKING: raw velocity.xy, thickness, normalized temperature (unchanged). ACES on writeTexture only.
```

```
SHADER: melting-oil-blackbody
IDENTITY: oil that runs downhill, swirls, and melts — velocity, temperature, molten coverage — blackbody plus an ember bloom.
KEEP VERBATIM: Viscosity / Temperature Range / Thermal Intensity / Glow Amount (ember bloom); downhill and tangent flow; mouse swirl; click fronts; packing velocity.xy, temperature, molten; blackbody on the molten mix
MECHANISM INTERROGATION:
  tactic 2: oil crawls from hot toward cold along the temperature field it already stores (Marangoni).
  tactic 3: molten coverage is a mask. Its edge, where neighbors are still solid, is a meniscus the shader never draws.
ADD:
  1. Marangoni — after viscosity damps velocity, a step toward the cooler neighbor from the stored temperature
  2. contact meniscus — molten pixels whose neighbors are less molten gain a thin bright lip and a little coverage
FORBID: honey crust, hex grid, thin-film as the whole look, a spring
A PACKING: raw velocity.xy, normalized temperature, molten coverage (unchanged). ACES on writeTexture only.
```

```
SHADER: warp-drive-blackbody
IDENTITY: radial blur into the pointer, blackbody along the streak, an Alcubierre wall, bow-blue / wake-red on the aberration axis.
KEEP VERBATIM: Intensity / Aberration / Brightness / Samples; the sample loop and weight; bow/mid/wake UVs; center glow; wall annulus; held mouse hotspot; raw HDR + avgTemp/15000 in A. Brightness and Samples stay dual-used as the temperature range (do not rewire).
MECHANISM INTERROGATION:
  tactic 2: inside an Alcubierre bubble the ship is at rest, so the streak should ease off inside the wall that already exists.
  tactic 6: A.a is avgTemp and C is not read. The wake can remember that temperature for one frame.
ADD:
  3. quiescent pocket — inside the existing bubble radius the mix from photo to thermal streak drops; the wall stays
  4. wake afterglow — outside the wall, mix toward last frame's Kelvin from C.a; first frame (C.a ≈ 0) skips it
FORBID: a second bubble, Cauchy (bow/wake split already is the chromatic), the non-blackbody warp's sign-change wall, a spring
A PACKING: raw HDR RGB + normalized avgTemp (unchanged). C.a read as previous avgTemp.
```

```
SHADER: energy-shield-blackbody
IDENTITY: a hex shield that strikes in whole cells, runs hotter on the edges, and leaves a decaying trail.
KEEP VERBATIM: Hex Scale / Ripple Speed / Impact Strength / Decay; cell hash radius; Faraday edge vs fill temperatures; click heat on the edge; trail = max(prev * Decay, activation); cyan on a fresh strike; raw trail in A.r
MECHANISM INTERROGATION:
  tactic 2: a struck cell should warm the next cell, using the trail scalar already stored.
  tactic 2 again: a decaying trail should cool through the blackbody ramp instead of staying cyan for its whole life. A fresh strike stays cyan.
ADD:
  3. neighbor conduction — newTrail also takes a fraction of the trail one hex step away; Decay still multiplies this pixel's own previous trail
  4. cooling tail — fresh cellHit keeps the cyan add; the decayed trail adds blackbody at a Kelvin set by newTrail
FORBID: facet shade and photo desaturate (those are energy-shield, not this file), a spring, changing the hex SDF
A PACKING: raw trail scalar in A.r (unchanged)
```

```
SHADER: gamma-ray-burst
IDENTITY: a relativistic jet at the pointer — Doppler beaming, a magnetic spiral, synchrotron color, click shells, chromatic aberration. A spring already follows the pointer.
KEEP VERBATIM: Intensity / Decay / Jet Spread / Exposure; Lorentz beaming; jetCore; magneticSpiral; click burst; synchrotron_spectrum shape; spring in extraBuffer[133..138]; A stores (burst, doppler, spiral, alpha)
MECHANISM INTERROGATION:
  tactic 2: the prompt is hard and the tail cools — blue dies as the existing burst cycle ages. The cycle phase is already computed and only gates burstTrigger.
  tactic 4: Jet Spread winds the spiral. A real jet also breaks, steepening past a radius that shrinks as the jet is tighter.
  The file also has a second click loop and an IQ clock-ring that redeclares aspect and rippleCount, so it does not compile. That stamp is not the effect. Remove it; keep the first click burst.
ADD:
  1. synchrotron cooling — as fract(time * 1.5) advances, the existing spectrum loses blue then green; the prompt stays
  2. jet break — past 6/jetSpread the wings fade; the core falloff stays
FORBID: bipolar lobes and C afterglow (gamma-ray-burst-blackbody), a blast-wave shell, a new spring, putting the IQ ring back
A PACKING: diagnostic fields (burst, dopplerBeaming, magneticSpiral, alpha). ACES on writeTexture only. C is not read.
```

```
SHADER: gamma-ray-burst-blackbody
IDENTITY: a radial-blur burst at the pointer, blackbody on the samples, two opposite jet lobes, an afterglow stored in C.
KEEP VERBATIM: Intensity / Decay / Ray Density / Exposure; 20-tap blur; bipolar lobe and rayInJet; core glare; afterglow add from C; raw RGB + energy in A. Temperature range stays tied to Intensity and Decay (do not rewire).
MECHANISM INTERROGATION:
  tactic 2: the fireball drives a blast wave, a thin shell that expands and cools. This file has no click ripples; the shell is the burst's own.
  tactic 6: the afterglow is last frame's RGB added back. A cooling fireball is redder than the prompt.
ADD:
  3. blast-wave shell — a thin ring at fract(time) * radius, blackbody of the high range, fading as the shell grows; Decay still weights the blur
  4. red afterglow — the existing cooled RGB is multiplied by a warm tint before it is added; the prompt mix stays
FORBID: synchrotron cooling and the jet-break radius (gamma-ray-burst), IQ clock rings, a spring, reading C as display color
A PACKING: raw burst RGB + energy (unchanged)
```
