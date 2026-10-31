# Grok 4.7 — temporal echo twelve

Written before WGSL edits. Second pass on files that already named ideas: the new pair is additive and uses nouns already in that file. No shared spring, ripple stamp, or IQ palette.

```
SHADER: temporal-echo
IDENTITY: a brightness-biased feedback echo that accumulates alpha and pins a frame on bass transients and clicks
KEEP VERBATIM: accumulativeAlpha; depthLayeredAlpha; temporalOffset lag bias; bass-transient pin via extraBuffer[133]; ripple pin; params accumulation_rate / echo_decay / depth_weight / temporal_offset
MECHANISM INTERROGATION:
  tactic 1: the "history" is a vertical slice through C. The next-better read of that same axis is a short smear along it, not a new buffer.
  tactic 2: a real afterimage drops the shadows first.
  tactic 3: brightness is already computed and only scales the slice index.
  tactic 6: C is accumulated RGBA. One extra row along the existing slice is still that packing.
ADD:
  1. history-axis smear — mix the slice with the next row so the echo is a short streak on the axis this shader already uses
  2. shadow-first stick — echoDecay tightens a luma knee so dim pixels stop accumulating before bright ones
FORBID: orbital transport (that is temporal_echo), phosphor masks, IQ palette, a new spring
A PACKING: accumulated linear RGBA in A (C is that accumulation); ACES on writeTexture only
```

```
SHADER: temporal_echo
IDENTITY: depth-weighted orbital transport of an exact chromatic history around the pointer
KEEP VERBATIM: tangent orbit; chromatic R/G/B exact-C taps; HSV hue walk; ripple echo fronts; decay / hue speed / chroma spread / depth influence; raw HDR in A, ACES on writeTexture
MECHANISM INTERROGATION:
  tactic 1: the echo is one sample on the orbit. An arc of taps along the same tangent is the same transport, extended.
  tactic 2: a persisted afterimage desaturates as it fades.
  tactic 3: tangent and effectiveDecay are already computed.
  tactic 6: C is raw HDR color. Extra exact loads along the orbit stay in that packing.
ADD:
  1. orbital arc smear — two extra exact-C taps along the existing tangent, mixed into the center tap
  2. afterimage bleach — persisted saturation falls with effectiveDecay
FORBID: history-ring ages, phosphor slots, peg-bar shifts
A PACKING: raw HDR echo RGB + alpha (unchanged); ACES on writeTexture only
```

```
SHADER: phantom-lag
IDENTITY: a velocity-aimed stack of decaying echo taps with chromatic split and a hue cycle
KEEP VERBATIM: five-tap PHI spacing; Echo X = step length; Echo Y = tap count; decay; hue cycle; cursor stretch; chromatic sampleEcho; params zoomParam1..4
MECHANISM INTERROGATION:
  tactic 2: a lag ghost does not sit on one line; it fans off the velocity, and it collapses when the motion stops.
  tactic 6: C is display color. Taps must be exact loads. Persistent mouse/bass state moves to [133..137] (floor; [0..3] is engine-owned).
  tactic 7: echoDir already has a perpendicular.
ADD:
  1. lag fan — each tap steps off the velocity along the perpendicular, with a midpoint filament so the phantom is a streak
  2. catch-up collapse — when speed drops, older taps lose weight faster than the head
FORBID: a second spring, history ring, orbital hue
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: long-exposure
IDENTITY: a highlight plate that accumulates, decays, and can be erased under the pointer
KEEP VERBATIM: threshold gate; reciprocity-law fade; highlight-only plate mix; positional eraser; ripple flashes; 4-tap C glow; FFT band decay; params accumSpeed / decayRate / glowRadius / threshold
MECHANISM INTERROGATION:
  tactic 2: a light-painting stroke continues along its own tangent, and dim latent image shifts cool.
  tactic 3: prevLuma and the glow radius already exist.
  tactic 6: C is raw exposure RGB. One more exact load along the plate gradient stays that packing.
ADD:
  1. light-trail tangent — one exact C sample along the plate's luminance gradient
  2. reciprocity color — dim trails cool; the hot core keeps its color. Amount rides decayRate
FORBID: orbital smear, phosphor mask, onion-skin outlines
A PACKING: raw HDR exposure RGB (C is previous accumulation); A.a = exposure density; ACES on writeTexture only
```

```
SHADER: temporal-rgb-ghost
IDENTITY: R from the live frame, G from a delayed ring age, B from an older comet integrated across ages
KEEP VERBATIM: per-channel ages; fractional G crossfade; motion-gated FBM displace; blue comet integration; vignette; g_delay / b_delay / blend / displace; frameAt ring wrap
MECHANISM INTERROGATION:
  tactic 2: a prism ghost puts red ahead of the delayed green.
  tactic 3: dispG - uv and |G - B| are already in hand and thrown away.
  tactic 6: the ring is read as color. No new packing.
ADD:
  1. leading red — live R is sampled opposite the G displacement, and only where motion is already gated
  2. disagreement fringe — where delayed G and comet B differ, a neutral rim marks the ghost edge
FORBID: onion pegs, zoom bezels, phosphor slots
A PACKING: display RGBA (unchanged)
```

```
SHADER: temporal-layered-time-stamps
IDENTITY: several past ring frames, spiraled about the cursor and inked with per-age onion-skin outlines
KEEP VERBATIM: echo layer count; per-age spiral; hue tint; exponential weights; onion outlines; echo_layers / warp_strength / color_intensity / blend_mix; frameAt
MECHANISM INTERROGATION:
  tactic 5: onion sheets on a peg bar do not register; motion between stamps smears.
  tactic 6: each age is already a color sample. The next age is the same read.
ADD:
  1. peg-bar shift — older sheets step along X by warp strength
  2. inter-stamp smear — each sheet mixes with the next-older frame at the same peg
FORBID: RGB comet, zoom bezel, cascade leak
A PACKING: display RGBA (unchanged)
```

```
SHADER: temporal-decay-multiresolution
IDENTITY: R/G/B are fast, medium, and slow history windows; A is ultra-slow luminance
KEEP VERBATIM: decay-shaped kernels; time-inversion inside click rings; mouse lens; fast/medium/slow decay and original blend; frameAt; A = ultra-slow luma
MECHANISM INTERROGATION:
  tactic 2: energy that leaves a fast window should show up in the next slower one.
  tactic 3: |fast - slow| is the motion the three kernels already imply.
  tactic 6: ring samples are color. Leak is a mix of kernels already formed.
ADD:
  1. cross-scale cascade — fast leaks into medium, medium into slow, in proportion to how fast that band forgets
  2. stationary mute — where fast and slow agree, the colored windows collapse toward ultra-slow luma
FORBID: peg bars, phosphor, orbital arc
A PACKING: display RGB, A = ultra-slow luminance (unchanged)
```

```
SHADER: temporal-feedback-zoom-tracer
IDENTITY: the newest history frame zoomed and rotated about the pointer, with nested bezels and a hue step per pass
KEEP VERBATIM: zoom / rotation / persistence / blend; FBM jitter; chromatic history; bezel tick; recursion hue drift; frameAt; in-frame surround
MECHANISM INTERROGATION:
  tactic 5: a camera filming a monitor shows interlace comb and its own corner falloff.
  tactic 6: age 2 is the same ring read as age 1. Falloff multiplies the warped history only.
ADD:
  1. field lag — even rows read one age older than odd rows
  2. feedback-camera falloff — cos^4 of distance from the zoom focus, on the warped history only
FORBID: onion outlines, phosphor slots, light-painting tangent
A PACKING: display RGBA (unchanged)
```

```
SHADER: infinite-video-feedback
IDENTITY: five recursive zoom-rotations of the previous frame about a sprung pointer, folded back into the picture
KEEP VERBATIM: 5-pass recursion; zoom scale; rotation; color shift; feedback decay; sprung center in extraBuffer[133..138]; click spin/zoom; sector FFT; accumulativeAlpha
MECHANISM INTERROGATION:
  tactic 2: each re-photograph loses detail, and the picture folds at the frame edge instead of vanishing.
  tactic 6: C is feedback color. Exact loads replace the filtering sample. Deeper passes widen one neighbor tap.
ADD:
  1. generation softness — pass i mixes in a neighbor exact-C tap so deeper copies go soft
  2. frame-edge fold — recursive UVs that leave the frame mirror back in
FORBID: history-ring ages, bezel ticks, phosphor mask
A PACKING: linear feedback RGBA in A; ACES on writeTexture only
```

```
SHADER: neon-echo
IDENTITY: a phosphor tube — per-channel exponential tails, a slow P7 yellow-green tail, cursor drift, and halation
KEEP VERBATIM: tauR/tauG/tauB; P7 tail; exact-C persistence; cursor drift; excitation threshold; halation taps; blackbody tint; persistence gain / cursor drift / threshold / halation; raw persistence in A
MECHANISM INTERROGATION:
  tactic 2: a CRT flashes when the beam crosses threshold, and the face is a vertical RGB slot mask.
  tactic 3: injectionStrength and halation are already computed. The flash and the mask are display-only so they do not bake into the tail.
ADD:
  1. ignition flash — a white display spike where excitation crosses the existing threshold
  2. phosphor slot mask — vertical RGB triads whose strength follows the halation slider
FORBID: zoom recursion, onion sheets, orbital arc
A PACKING: raw persistence RGB + alpha (ACES on writeTexture only, unchanged)
```

```
SHADER: luma-echo-warp
IDENTITY: luma-weighted warp of the live frame plus a chromatic echo, with terraced luma bands and contour ghosts
KEEP VERBATIM: radial+tangent warp; curl drift; 6-band terrace quantize; contour-slowed decay; strength / decay / radius / luma weight; feedback is pre-tint echo
MECHANISM INTERROGATION:
  tactic 2: bright parts of a luma warp should pull their echo farther than shadows, and a terrace has a shaded riser.
  tactic 3: warp, luma, and (weight - weightSmooth) already exist.
  tactic 6: C is the pre-tint echo. The lead is a different UV into that same load.
ADD:
  1. bright-lead trail — history UV shifts along the warp in proportion to luma
  2. terrace riser shade — display darkens where the quantized weight leaves the smooth weight (not written back into A)
FORBID: phosphor slots, peg bars, field lag
A PACKING: linear echo RGB (pre-tint/sparkle, clamped 0..1.2) + alpha (unchanged)
```

```
SHADER: temporal-rift
IDENTITY: a pointer-centred tear that paints the live frame into a decaying history, with arrival delay and velocity shear
KEEP VERBATIM: smear decay; rift width; chroma split; echo intensity; distance-arrival; C ghost shear; sprung pointer in extraBuffer[133..138]; click rift
MECHANISM INTERROGATION:
  tactic 2: a tear is loudest at its lip, and the two sides of a rift disagree in color more than the cloth around it.
  tactic 3: rift * (1 - rift) is the lip of the mask already computed. separation is a scalar that can widen inside the rift.
  tactic 6: C is previous hist RGBA. The lip is an extra offset on the shear load that already exists.
ADD:
  1. rift lip — shear peaks on the edge of the tear, tangential to the pointer
  2. rift-widened chroma — the existing channel split grows inside the rift
FORBID: zoom bezels, onion pegs, phosphor mask
A PACKING: nextHist RGBA (C is previous hist, unchanged); ACES on writeTexture
```
