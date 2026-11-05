# Idea Cards — cursor/batch-34 slit-scan and time-delay (2026-11-01)

Written before the WGSL edits. Twelve slit-scan and time-delay shaders. Where a file already names ideas, these cards add two more inside that path. Saved params stay byte-exact. No shared spring, no shared ripple stamp, no shared palette.

Formula rule: Cauchy dispersion (§12.2F) is only on `spectral-slit-scan` and `hyper-chromatic-delay`. Beer–Lambert (§12.2F) is only on `temporal-distortion-field`. Chroma delay (§12.2B) is only on `hyper-chromatic-delay`. Field interlace (§12.2B) is only on `cyber-slit-scan`. Semi-Lagrangian and wet-edge (§12.2C) are only on `rgb-delay-brush`. No other §12.2 row is shared.

## chrono-slit-scan

```
SHADER: chrono-slit-scan
IDENTITY: two or three vertical slits sweep the frame, exposing the live picture inside the slit and letting history decay outside it.
KEEP VERBATIM: slitPosition golden-ratio phases; smin of the three distances; slitCount 2–3; width / speed / feather roles; LOD fbm warp on the nearest slit; held drag of that slit; slit heads, cross-runners, click fronts; early-exit when the mask is empty; history decay outside the slit.
MECHANISM INTERROGATION:
  tactic 2: a metal slit has jaws. Light catches the edge as a bright lip the smoothstep mask throws away.
  tactic 5: the film gate weaves a few pixels vertically while the slit is open. The live sample is currently the pixel under the slit, with no transport.
  tactic 3: dist and slitW are already computed and only feed the mask.
ADD:
  1. Jaw lip — a thin exposure line where dist meets slitW, folded into the existing mask so the jaws catch light.
  2. Transport weave — inside that mask the live sample shifts a few pixels in Y with slit speed, the film creeping while the slit is open.
FORBID: another cosine palette, a new slit count, springs, replacing the sweep with a scanline glitch.
A PACKING: linear history RGBA in A (C is that history). ACES on writeTexture only, so the decay does not compound.
```

## cyber-slit-scan

```
SHADER: cyber-slit-scan
IDENTITY: a vertical slit writes a bit-crushed, hue-shifted column at the right edge and the rest of the frame scrolls out of history.
KEEP VERBATIM: right-edge injection from the mouse slit; bit crush; hue shift; scan speed; diagonal tear, held bend, click kick; conveyor; second lagged head; treble crush bursts; artifact amount on the tears.
MECHANISM INTERROGATION:
  tactic 3: the crush residual (pre-crush minus crushed) is computed and discarded. Those are the posterization edges.
  tactic 5: a digital slit scanner reads odd and even rows from adjacent columns. The write head currently samples one column for every row.
  tactic 1: the fresh column is one texture sample. The next-better read of the same slit is a field pair.
ADD:
  1. Crush contour — the quantization residual lights the bin edges on the fresh column. Bit Crush still sets the bit depth.
  2. Field interlace (§12.2B) — odd rows of the write head sample one column further, widened by Artifact Amount.
FORBID: a third scan head, oil-slick as a new layer, springs, storing a latch in A (A is the scrolled picture).
A PACKING: linear display RGBA in A (the scroll reads C as color). ACES on writeTexture only.
```

## spectral-slit-scan

```
SHADER: spectral-slit-scan
IDENTITY: several curved slits (sine, orbit, radial) replay history with a chromatic offset and a per-slit trail decay.
KEEP VERBATIM: slit density → count; trail decay power; chroma shift; curve amplitude; the three curve shapes; mouse parallax and curl; wavelength-staggered R/G/B taps; luma-hold; ACES display feedback.
MECHANISM INTERROGATION:
  tactic 2: a grating does not bend every wavelength by the same fraction of the curve. Dispersion goes as 1/λ².
  tactic 5: the second diffraction order sits further out and fainter. The shader has one chromatic tap per slit.
  tactic 4: Chromatic Shift is a constant UV nudge. The spatial version of that nudge is the curve itself, scaled per channel.
ADD:
  1. Cauchy bend (§12.2F) — curveOff is scaled per channel by n(λ)/n(green). The existing linear R/G/B stagger stays.
  2. Second diffraction order — one fainter history tap at 2× the chromatic offset, weight following Chromatic Shift.
FORBID: thin-film, a new curve family, springs, dropping luma-hold.
A PACKING: ACES display RGBA (unchanged; C is read as that color).
```

## temporal-slit-paint

```
SHADER: temporal-slit-paint
IDENTITY: a brush that stamps the live frame, stretched along the stroke, with a slit through the brush that smears a strip of video.
KEEP VERBATIM: four brush shapes; size / softness / diffusion; velocity stretch from the (0,0) state texel; slit stamp; exposure frame-lines; diffusion laplacian; state packing (prevMouse.xy, vel.xy) at (0,0).
MECHANISM INTERROGATION:
  tactic 2: an open slit exposes brightest on its centerline and falls off at the jaws. The stamp is flat across local.y.
  tactic 6: the stroke already has a velocity. A moving slit integrates the frames it just passed, not one instant.
  tactic 4: softness is a scalar on the brush SDF. Across the slit it is the exposure profile.
ADD:
  1. Gaussian slit exposure — the stamped strip falls off across the slit, wider when Brush Softness is higher.
  2. Stroke integration — the slit color is the average of the live frame at the brush and at one and two frames back along the velocity.
FORBID: a new spring, a new shape, replacing the state texel, drying the whole canvas into a different sim.
A PACKING: raw canvas RGBA; texel (0,0) remains cursor state. ACES on writeTexture only (unchanged).
```

## temporal-slit-scan

```
SHADER: temporal-slit-scan
IDENTITY: each column or row reads a different age in the history ring, so time runs across the picture.
KEEP VERBATIM: axis, temporal spread, reverse, original blend; mouse tent pivot; click tears; per-column spectral jitter; frameAt wrapping at textureNumLayers; sub-frame interpolation; 1-2-1 exposure box.
MECHANISM INTERROGATION:
  tactic 2: bright film reciprocates — a hot subject streaks longer through the same slit. Shutter width ignores luma.
  tactic 4: Temporal Spread is a time width. A physical slit also has a spatial width, so neighboring columns share a little of the same age.
  tactic 3: the center age sample's luma is about to be thrown into a box average.
ADD:
  1. Highlight reciprocity — the existing shutter widens where that center sample is bright, and stays shut at the live pivot.
  2. Spatial slit width — a small mix of the neighbor column at the same age, scaled by Temporal Spread.
FORBID: a second axis, interlace comb, springs, changing the ring wrap.
A PACKING: ACES display RGBA (unchanged). Binding 13 stays.
```

## time-slit-scan

```
SHADER: time-slit-scan
IDENTITY: one to three geometric slits (sine, radial, or spiral) drift through history and tint older light blue, newer light warm, over a dimmed live frame.
KEEP VERBATIM: slit count 1–3; shape mode 0/1/2; the three SDFs; per-shape drift UV; drift speed and slit width roles; index tint from blue to warm.
MECHANISM INTERROGATION:
  tactic 1: slitBlendFactor already takes a feather, and main passes a constant 0.02, so a hairline and a wide slit have the same jaw.
  tactic 2: an open slit integrates a short streak along its travel, not one history texel.
  tactic 5: age changes along a slit, not only from slit to slit. The tint is constant per index.
ADD:
  1. Width-scaled jaws — feather follows Slit Width so a thin slit stays a hairline and a wide slit has soft jaws.
  2. Exposure streak — a second history load a step back along the drift, averaged with the existing sample.
  3. Along-slit age — the existing blue-to-warm tint also runs along the slit (x for sine, angle for radial and spiral).
FORBID: a fourth shape, springs, an IQ palette, filtering the history texture.
A PACKING: linear slit RGBA in A (C is that color, exact load). ACES on writeTexture only.
```

## time-lag-map

```
SHADER: time-lag-map
IDENTITY: a spatial delay field (radial, horizontal, vertical, spiral, or noise) mixes the live frame toward stored history.
KEEP VERBATIM: the five mapping modes; Delay Length; Delay Pattern; Motion Sensitivity gate; luma-keyed delay; mouse and ripple lag bumps; chroma split of the delayed color; history write in A.
MECHANISM INTERROGATION:
  tactic 3: lagAmount is a field. Its level sets are the time zones, and they are never drawn.
  tactic 7: the smear direction is two magnitudes, so it always points down-right. The lag field has a real gradient.
  tactic 4: Feedback Mix is read and then ignored. High feedback should keep history; low feedback should track the live frame.
ADD:
  1. Lag iso-lines — faint contours where the delay field crosses its level sets, so the map is visible as a map.
  2. Lag-gradient flow — the motion-gated smear follows ∇lag. The motion gate stays.
FORBID: a sixth mapping mode, a spring, replacing luma-key or the five selectors.
A PACKING: history RGB in A (unchanged). ACES on writeTexture only.
```

## phantom-lag-history

```
SHADER: phantom-lag-history
IDENTITY: a lagged echo of the previous frame, hue-cycled, with bright echoes that hang and then cool.
KEEP VERBATIM: echo decay; lag offset X/Y; hue cycle; luma stored in A.a; luma-weighted persist; age-tint toward cool; glow when stored luma exceeds the live frame; mouse and ripple charge of that luma.
MECHANISM INTERROGATION:
  tactic 6: the four neighbor luma taps are already loaded for diffusion and then only averaged. A phantom blooms into those neighbors.
  tactic 2: new light should flash before it ages. The shader tints the afterimage and has no attack on a rising luma.
  tactic 7: the echo offset is a constant vector. The stored luma already says which side was brighter.
ADD:
  1. Neighbor glow — the existing four luma taps add a short halo where they outshine the live pixel.
  2. Attack flash — a white head where the live luma rises above the stored luma, before the cool age-tint.
FORBID: a second hue cycle, springs, rewriting A.a away from luminance history.
A PACKING: ACES display RGB + luminance history in A.a (unchanged).
```

## temporal-distortion-field

```
SHADER: temporal-distortion-field
IDENTITY: a depth-scaled freeze bubble around the pointer, with a warped flow, ghost taps back along that flow, and past/present/future channels.
KEEP VERBATIM: Freeze Amount, Warp Strength, Ghost Count, Depth Weight; fbm warp cap; stasis bubble (held field outputs C); ghost taps 1..5; past/present/future channels; horizon lens from the smoothstep edge.
MECHANISM INTERROGATION:
  tactic 4: Depth Weight scales the bubble radius and nothing about how far the ghosts step.
  tactic 8: the frozen field is a thickness. Light through it should be absorbed, not only replaced.
  tactic 2: glass and stopped time both eat light toward the center of the disk.
ADD:
  1. Depth-scaled ghost step — the existing tap distance grows with depth × Depth Weight.
  2. Bubble absorption (§12.2F Beer–Lambert) — the field darkens toward its center, more while held.
FORBID: a new warp, Cauchy (used on the two spectral files), another ghost model, springs.
A PACKING: ACES display RGBA, history decoded with acesInverse (unchanged).
```

## temporal-phosphor-burn-motion-adaptive

```
SHADER: temporal-phosphor-burn-motion-adaptive
IDENTITY: motion-adaptive CRT phosphor. Fast regions keep long trails; still regions clear; the trail ages from white to amber.
KEEP VERBATIM: motion sensitivity, max decay, min decay, warm tint; history-ring ages; mouse lens charge; click stamps; band drift; trail hysteresis; persistence colour aging; ring wrap at textureNumLayers.
MECHANISM INTERROGATION:
  tactic 5: P31 phosphor grain shows in the decay, not in the fresh scan. The trail is smooth.
  tactic 8: the burn is a point sample. Real phosphor spreads into the neighboring cells of last frame's burn.
  tactic 3: lastBurn − current is already the trail mask (wasTrail) and is not used to place grain or bleed.
ADD:
  1. Phosphor grain — stable spatial grain on the excess of the burn over the live frame, scaled by Warm Tint.
  2. Neighbor bleed — a 4-tap of last frame's burn, added only where this pixel was already a trail.
FORBID: frame-hash strobe, a second tint palette, springs, ACES inside A (C is the burn the hysteresis reads).
A PACKING: display RGBA burn in A, read back as last frame's burn. ACES on writeTexture only.
```

## hyper-chromatic-delay

```
SHADER: hyper-chromatic-delay
IDENTITY: a spectral delay line — wavelength-tinted taps along a rotating direction, per-channel lens distortion, and a trail mixed from last frame.
KEEP VERBATIM: RGB Split, Trail Decay, Shift Speed, Mouse Influence; 7-tap spectral sum; Brown–Conrady lens per channel; echo taps; trail mix with C; the existing mouse-down spring.
MECHANISM INTERROGATION:
  tactic 2: glass separates wavelengths as 1/λ². The taps shift linearly in (λ − 550).
  tactic 5: a chroma delay holds red and blue for different times. The trail mix delays all three channels by the same amount.
  tactic 1: the spectral loop already has λ. The next-better shift of that loop is Cauchy.
ADD:
  1. Cauchy tap spacing (§12.2F) — the existing dispersion slider scales n(λ)/n(green) instead of (λ − 550).
  2. Chroma delay line (§12.2B) — Trail Decay holds red longer than green and blue shorter, against the same C frame.
FORBID: a new spring, thin-film, a second direction field, replacing the lens.
A PACKING: ACES display RGBA (unchanged; C is that color).
```

## rgb-delay-brush

```
SHADER: rgb-delay-brush
IDENTITY: under the brush, red catches the live frame first, then green, then blue, and the thick trail absorbs light by wavelength.
KEEP VERBATIM: Trail Persistence, Time Split, Brush Size, Alpha Absorption Scale; per-channel catch-up speeds; wavelength absorption; bristle offset; wet mix from C; click stamps; the existing spring.
MECHANISM INTERROGATION:
  tactic 6: the spring velocity is the stroke. Blue should be read from behind the brush, not only mixed more slowly at this pixel.
  tactic 2: absorption is flat across the dab. Water and dye go dark at the rim, where the mask falls off.
  tactic 3: mask × (1 − mask) is the rim, and it is thrown away.
ADD:
  1. Semi-Lagrangian channel lag (§12.2C) — green and blue sample C behind the stroke, blue further, and only while the brush is moving.
  2. Wet-edge absorption (§12.2C) — the existing thickness rises on the rim of the mask, so the edge goes darker.
FORBID: a second spring, a new brush shape, speed-thinning (kept off this batch so the two brushes do not share a formula), replacing the wavelength absorption.
A PACKING: delayed RGB in A (C is the previous delayed color). ACES on writeTexture only (unchanged).
```
