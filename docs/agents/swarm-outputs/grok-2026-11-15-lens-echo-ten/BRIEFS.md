# Idea Cards — grok/lens-echo-ten (2026-11-15)

Written before the WGSL edits. Ten smallest remaining shaders (108–121 lines). Mixed lens, temporal-echo, and grade files. Each card adds 2 native ideas inside the existing main path. Saved params stay byte-exact. No new spring. No shared ripple stamp. No shared palette.

Formula rule: Airy (§12.2F) is only on `tilt-shift`. Cauchy and energy-conserving bloom (§12.2F) are only on `alpha-hdr-bloom-chain`. Halation red-fringe and core bleach (§12.2A) are only on `temporal-halation-freeze`. The H&D toe (§12.2A) is only on `pp-tone-map`. No §12.2 row is shared across files.

Two files still paste the binding header (`temporal-halation-freeze`, `pp-tone-map`). Those get `migrate_to_prelude.py` first. That swap is not an idea and is not why `Upgraded:` moves.

## tilt-shift

```
SHADER: tilt-shift
IDENTITY: a Scheimpflug miniature — a tilted sharp band, hexagonal CoC blur off that band, toy saturation.
KEEP VERBATIM: Blur Amount, Focus Width, Saturation, Tilt Angle; mouse Y as the focal plane; bass tilt oscillation; depth-scaled CoC; 16-tap golden-angle gather; hex aperture weight; specular add only where coc is large; OOF chromatic split; HSV saturation; blur vignette.
MECHANISM INTERROGATION:
  tactic 1: the gather is a hex-weighted disc. A real iris is also clipped by the barrel once the view is off axis.
  tactic 2: a point highlight in that disc is an Airy pattern, not a flat hex stamp. The specular add is a scalar on the center sample.
  tactic 3: each tap already has a radius `r` and a direction `dir`. Both are thrown away after the hex test.
  tactic 6: C is display color and is not part of the gather. Leave the packing alone.
ADD:
  1. Cat's-eye optical vignetting — off-axis, out-of-focus taps on the outward side of the hex lose weight. The sharp band (small coc) stays round.
  2. Airy ring on defocus specular taps (§12.2F) — bright taps inside the same gather are weighted by a sinc disc with one lifted ring. Diffuse taps keep the hex weight. The existing center specular add stays.
FORBID: a spring, a click shockwave, an IQ palette, a new param, replacing the hex gather.
A PACKING: ACES display RGBA (unchanged).
```

## hyb-temporal-fbm-ghost

```
SHADER: hyb-temporal-fbm-ghost
IDENTITY: the photo split into three rotating channel offsets, shoved by an FBM domain warp, with a ghost halo tied to the source luma.
KEEP VERBATIM: Temporal Shift, FBM Scale, Warp Amount, Effect Mix; domainWarp(); per-channel dirs; exact-C per-channel lag (R holds longer than B); source-tied halo; effectMix over the source; ACES on the composite.
MECHANISM INTERROGATION:
  tactic 3: `disp = warped - uv` is the flow and is only used to place the three taps.
  tactic 6: C is the previous display plate, read at this pixel only. The warp says where that plate came from.
  tactic 2: a ghost riding a warp should brighten on the steep crest of that warp, where the smear is longest.
ADD:
  1. Flow-advected ghost — one exact C load upstream along `disp`, mixed into the lagged RGB by the temporal-shift slider. The per-channel same-pixel lag stays.
  2. Warp-crest glow — the existing source-tied halo brightens where `|disp|` is large relative to the warp amount. Flat warps stay as they were.
FORBID: a new palette, a spring, a second noise, reading C as anything but display color.
A PACKING: ACES display RGBA (unchanged). C is that display.
```

## chroma-threads

```
SHADER: chroma-threads
IDENTITY: horizontal silk threads across the photo, plucked toward the pointer, with anisotropic weave, a sheen BRDF, and an RGB split along the thread.
KEEP VERBATIM: Thread Density, Vibration Amp, RGB Split, Decay; threadID from uv.y; mouse influence and pluck; anisotropic noise; sheen_brdf; SSS; edge chromatic tint; mask from the thread profile.
MECHANISM INTERROGATION:
  tactic 5: a weave has a weft. These threads are only a warp — nothing crosses them.
  tactic 6: A.r already stores this frame's offset and C is never read. Decay is named as a trail and currently only shortens the spatial pluck.
  tactic 2: a plucked thread rings. The sine is single-frame.
ADD:
  1. Weft crossing — a perpendicular thread ducks the warp on alternate crossings (mask and live offset drop there). Density still sets both pitches.
  2. Pluck ring-down — C.r (previous offset) is damped by the decay slider and added to this frame's vibration. Higher decay still means a shorter trail. A stays telemetry, not color.
FORBID: a spring, a new solver, ACES on the stored offset, turning A into display color (C.r is the offset).
A PACKING: A = (offset, influence, sheen, alpha) telemetry. Display RGBA is writeTexture only, ACES there. C.r is the previous offset.
```

## concentric-spin

```
SHADER: concentric-spin
IDENTITY: concentric rings spinning in alternating directions around a lagged pointer, rose and epitrochoid shapes as mids rise, gaps between rings.
KEEP VERBATIM: Density, Speed, Smooth W, Gap Fade; exact-C center lag; rose/epi mix from mids; alternating dir; per-channel rotation offsets; gap tangent conveyor; iridescent gap bloom; click pulse; sheen; A = lag.xy plus alpha.
MECHANISM INTERROGATION:
  tactic 4: Smooth W is one gap width for every ring. A groove pitch opens toward the rim.
  tactic 3: `edge` is the distance to the ring boundary and is only a mask. The shoulder of that boundary is a place light catches.
  tactic 7: the ring already has a tangent. The shoulder should face the spin, not be a flat add.
ADD:
  1. Groove pitch — Smooth W is multiplied by a radius term so outer rings open a wider groove. Slider at 0 still closes every gap.
  2. Groove-shoulder glint — a thin band of `edge` just inside the groove lights on the side facing the spin. Gap Fade still owns the dark seam.
FORBID: a new curve family, a spring (the lag is already the pointer), an IQ palette, packing spin into A (A.xy stays the center lag).
A PACKING: lag.xy telemetry plus alpha (unchanged). ACES on writeTexture only.
```

## temporal-halation-freeze

```
SHADER: temporal-halation-freeze
IDENTITY: a long exposure of hex-bokeh halation that accumulates in C, red-lagged, and freeze-holds while the pointer is down.
KEEP VERBATIM: Exposure Length, Decay Rate, Bloom Color Temp, Ghost Echo; 7-tap hex bloom; bass envelope in A.a; dye-layer lag (R holds); held-pointer freeze toward prev.rgb; warm/cool tint; ghost from C; dark-pixel bypass; A = accumulated halo RGB + envelope.
MECHANISM INTERROGATION:
  tactic 2: light that bounces off the film base re-exposes the red layer, and it is redder the further it has scattered. The hex taps are the same color.
  tactic 8: the halo is added on top of the core. The core should give that light up — desaturate, not just dim by the existing 0.15 brightMask.
  tactic 3: each hex tap already knows whether it is the center.
ADD:
  1. Red fringe on the outer taps (§12.2A halation) — the center tap stays the source color; the six surround taps mix toward a red times their luma. Color Temp still tints the accumulated plate.
  2. Core bleach (§12.2A) — where the new halo is strong, the source is pulled toward its luma before the bloom is added. The dye lag and the freeze hold stay.
FORBID: a spring, a new bloom kernel, ACES on the stored halo, an IQ palette.
A PACKING: accumulated halo RGB + envelope in A (unchanged, raw). ACES on writeTexture only.
```

## alpha-luminance-history

```
SHADER: alpha-luminance-history
IDENTITY: a light trail. RGB is this frame's color; alpha is a rolling luminance that glows warm where the scene used to be brighter, advected toward the pointer and diffused.
KEEP VERBATIM: Memory Decay, Glow Intensity, History Tint, Trail Diffusion; advected historyAt(); 4-neighbour diffusion; mouse paint into the average; ripple flash into the average; history tint multiply; A.rgb = current color, A.a = diffused average.
MECHANISM INTERROGATION:
  tactic 2: phosphor and light-painting rise fast and release slowly. The mix uses one decay both ways.
  tactic 3: C.rgb is the color that was stored with that luminance and is never read. The glow is a fixed warm vector.
  tactic 6: reading C.rgb as the remembered hue does not change the packing.
ADD:
  1. Phosphor attack / release — rising luma uses a faster mix, falling luma uses a slower mix. The decay slider still sets both time constants.
  2. Remembered-color afterglow — the glow tint mixes the fixed warm lamp with C.rgb, weighted by the previous average. History Tint still multiplies the result.
FORBID: a spring, storing the display color in A (A.rgb must stay the source color the next glow reads), a new diffusion solver.
A PACKING: raw state. A.rgb = current source color, A.a = rolling luminance. ACES on writeTexture only. Do not tone-map A.
```

## chrono-luma-slit-scan

```
SHADER: chrono-luma-slit-scan
IDENTITY: a luma-keyed slit scan across the history ring, with sweeping scan runners that open onto the oldest frame and thin isochrones on integer ages.
KEEP VERBATIM: Temporal Spread, Warp Strength, Luma Gamma, Original Blend; frameAt() ring clamp; luma→age; runner window onto reach; isochrone on ageFrac; ripple warp; held shrink of spread; binding 13.
MECHANISM INTERROGATION:
  tactic 2: a slit integrates while the subject travels through it. The shader picks one UV and crossfades two ages.
  tactic 4: the age crossfade is linear. A slit shutter's exposure across the two frames is a raised cosine.
  tactic 3: slitBandH / slitBandV already say which way the slit is traveling.
ADD:
  1. Slit-travel smear — two extra frameAt taps one step along the dominant scan axis, averaged in only where the runners are actually bright. Spread still scales the step.
  2. Raised-cosine shutter — the mix of frameA and frameB uses a raised cosine of ageFrac. Isochrones still key off the raw ageFrac, so the contour stays on the integer.
FORBID: a new history binding, a spring, painting the isochrone in a new palette, ignoring histDepth.
A PACKING: display RGBA (unchanged). The ring is binding 13, not C.
```

## video-echo-chamber

```
SHADER: video-echo-chamber
IDENTITY: orbiting, chromatic video feedback around the pointer. Moving subjects leave an echo; still background stays clean; near depth holds the echo longer.
KEEP VERBATIM: Global Decay, Mouse Radius, Echo Strength, Color Shift; aspect-correct orbit; horizontal runner streak; click rings; motion key from |current − prev| with C.a memory; depth-weighted decay; static floor under the pointer; A = pre-ACES blend + motionMemory; ACES on writeTexture only.
MECHANISM INTERROGATION:
  tactic 2: a feedback loop bleaches chroma as the echo gets older. motionMemory is that age and only gates the weight.
  tactic 3: the luma difference is a blob. The contour of the moving subject is a spatial edge of the source, gated by that same difference.
  tactic 6: C.rgb is the echo color. Desaturating it is still color history.
ADD:
  1. Chroma collapse of the persisted echo — echoColor is pulled toward its luma by motionMemory. A still frame (memory near 0) stays chromatic. The color-shift streak stays.
  2. Motion contour rim — a 4-neighbour luma edge of the source, gated by motionNow, added on the display only so it cannot feed back into A.
FORBID: a third conveyor, a spring, storing the rim in A, an IQ palette, changing the motion-key floor.
A PACKING: pre-ACES echo RGB + motion memory in A (unchanged). ACES on writeTexture only.
```

## alpha-hdr-bloom-chain

```
SHADER: alpha-hdr-bloom-chain
IDENTITY: a spectral HDR bloom gathered on 16 rings, added to an exposed source, with a short exact-C feedback, a held-pointer halo, and click fronts.
KEEP VERBATIM: Bloom Radius, Bloom Intensity, Exposure, Saturation; 16-ring gather; bright threshold; hover halo and held gain; click fronts; history mix cap 0.14; saturation toward luma; A = raw HDR rgb + overexposure; ACES on writeTexture only.
MECHANISM INTERROGATION:
  tactic 1: the R/B tap offsets are fixed magic scales. Dispersion in glass is Cauchy, blue wider than red.
  tactic 8: the bloom is pure add, so highlights double. The spread light should come out of the source.
  tactic 3: bloom and sourceHdr are both in hand before the add.
ADD:
  1. Cauchy ratio on the existing spectral taps (§12.2F) — green keeps its 0.19 offset. Red and blue keep opposite directions; their magnitudes follow n(λ) so blue outruns red. Radius still sets the overall shift.
  2. Energy-conserving bloom (§12.2F) — a fraction of the spread is subtracted from the exposed source, clamped so the source cannot go negative, then the spread is added back.
FORBID: a new gather count, a spring, ACES on the stored HDR, an extra palette on the bloom itself (the hover tint stays).
A PACKING: raw HDR RGB + overexposure in A (unchanged). ACES on writeTexture only.
```

## pp-tone-map

```
SHADER: pp-tone-map
IDENTITY: one global grade. The algorithm slider crossfades ACES, Uncharted 2, Reinhard, and AgX, then contrast and saturation.
KEEP VERBATIM: Algorithm, Exposure, Contrast, Saturation; the four curve functions; continuous mix across algorithm * 3; hue-preserving contrast (scale around luma); saturation mix toward luma; bass on exposure; no second ACES wrap; source is readTexture, never C.
MECHANISM INTERROGATION:
  tactic 2: exposure below the middle of the slider is a linear scale into black. A film curve has a toe there.
  tactic 8: clamp(ldr, 0, 1) clips the hottest channel first and shifts hue. The contrast function preserves hue around mid-grey, not at the clip.
  tactic 3: peak = max(channel) is available after saturation and is discarded by the clamp.
ADD:
  1. Underexposure toe (§12.2A H&D) — when exposure is negative, shadows roll through scaled/(scaled+k) instead of a pure multiply. At exposure ≥ 0 the four curves see the same scaled color as before.
  2. Hue-stable highlight shoulder — after saturation, pixels near the clip pull toward their luma, then clamp. Mid-grey contrast is untouched.
FORBID: a local blur, a spring, a fifth curve, reading C as input (that would re-grade the grade), a second ACES on the output.
A PACKING: display RGBA, already tone-mapped (unchanged). No second ACES.
```
