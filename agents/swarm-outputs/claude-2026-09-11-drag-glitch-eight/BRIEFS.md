# Batch: drag-glitch-eight (2026-09-11)

Theme: pointer-drag / trail / temporal effects that already own the mouse or a
feedback history buffer. IDs claimed: `glitch-ripple-drag`, `pixel-drag-smear`,
`slinky-distort`, `cyber-trace`, `neon-contour-drag`, `cyber-slit-scan`,
`temporal-echo`, `viscous-drag`. None carry an `Ideas:` tag yet; all already
sit on the plumbing floor (13 bindings, ACES, spring/ripple systems, semantic
alpha), so this batch is pure Idea-Card work, not hygiene.

---

```
SHADER: glitch-ripple-drag
IDENTITY: pointer drags a chromatic-tearing liquid-glitch trail behind a sprung origin
KEEP VERBATIM: extraBuffer[133..138] spring, displacement formula (direction+wave+ripples),
  quantized-angle glitch, persistence trail mix, red/blue history chroma taps
ADD:
  1. velocity-scaled chroma spread — scale the existing red/blue history tap offset by
     spring velocity magnitude (not just glitchAmt), so fast drags tear wider and slow
     drags stay tight: ties the chromatic split to the drag physics already driving it
  2. held-pointer strobe latch — while the pointer is held, quantize time into short
     steps for the wave phase, producing a stutter/freeze cadence (native to a "drag
     glitch"; off when not held so idle playback is unchanged)
FORBID: new spring systems, IQ palettes, unrelated liquid solver
A PACKING: unchanged — display RGBA in A (exact-history trail)
```

```
SHADER: pixel-drag-smear
IDENTITY: wet-paint smear that trails the cursor with curl-noise jitter and spectral tint
KEEP VERBATIM: brush/strength/decay/mode params, curl noise offset, lumaMix blend,
  velocity tint, comb/spectral highlight, ripple pigment fronts
ADD:
  1. bristle streak sampling — instead of one history tap, average 3 taps stepped along
     the drag offset vector (bristle sub-steps), so the smear reads as dragged bristles
     rather than a single soft blur
  2. treble-split pigment bleed — offset the curl displacement per RGB channel by a small
     phase keyed to audioTreble, giving chromatic paint bleeding at the brush edge that
     pulses with treble (extends the existing psychedelic-color/audio feature, not a new one)
FORBID: replacing curl noise with a different noise family; new particle system
A PACKING: unchanged — display RGBA
```

```
SHADER: slinky-distort
IDENTITY: mouse-centered spiral "slinky" coil warp with bass crest highlight
KEEP VERBATIM: coils/amplitude/depthWeight/tightness params, normal+tangent displacement,
  colorShift by spiral phase, bass crest highlight, advanced alpha functions
ADD:
  1. elastic overshoot echo — read dataTextureC (previous frame's warped display, since
     this shader already writes dataTextureA) at a slightly lagged spiral phase and blend
     with the current warp, giving the coil a springy trailing afterimage instead of a
     single static warp
  2. treble compression pulse — add a secondary term to spiralPhase driven by treble that
     travels outward as an accordion compression wave along the coil
FORBID: replacing the spiral kernel; generic ripple shockwave unrelated to the coil
A PACKING: display RGBA in A (newly added — HEAD did not read C, now stores/reads display
  history consistently)
```

```
SHADER: cyber-trace
IDENTITY: neon brush trail painted into a decaying history buffer, following a sprung cursor
KEEP VERBATIM: spring-follow position in extraBuffer[133..138], HSL hue-cycle stroke,
  history decay accumulation, band-based shimmer, glow composite + alpha
ADD:
  1. velocity-oriented arc stamp — stretch the brush stamp along the spring-velocity
     tangent instead of a pure radial disc, so the trace reads as a drawn arc, with arc
     length scaling with velocity magnitude
  2. treble circuit sparks — above a treble threshold, branch small perpendicular tick
     marks off the trail (hashed by position+time) that decay in the same history buffer,
     reading as circuit-trace branching consistent with the "Cyber" identity
FORBID: a second independent particle/spark system outside dataTextureA; new spring
A PACKING: unchanged — history RGB in A, alpha 1.0 (as HEAD)
```

```
SHADER: neon-contour-drag
IDENTITY: dual-scale Sobel edge-glow warped around the mouse, with hue conveyor and a
  hot inverted core
KEEP VERBATIM: dual-scale sobel blend, mouse warp, hue-by-distance/time/colorShift,
  contourRunner/hueConveyor traveling pulses, click-front rings, hotCore inversion,
  emissive alpha function
ADD:
  1. edge-tangent glow streaks — return the sobel gradient direction (not just magnitude)
     and stretch the glow along the edge tangent, so neon light runs along contours
     instead of glowing isotropically around each edge pixel
  2. bass core pulse — modulate the hotCore threshold with bass so the inverted "pupil"
     at the cursor visibly pulses on the beat
FORBID: replacing sobel with a different edge operator; unrelated liquid/spring additions
A PACKING: unchanged — emissive RGBA, no A history
```

```
SHADER: cyber-slit-scan
IDENTITY: traveling slit-scan head with a diagonal tear region, aurora/oil-slick bands,
  held-pointer bend and click injections
KEEP VERBATIM: slit column sampling, bit-crush quantization, diagonal-tear source-row
  logic, conveyor decay, click-front glow, hue rotation
ADD:
  1. second lagged scan head — add a phase-offset second head reading from a different
     source column, interleaved with the primary head, so "traveling scan heads" (already
     claimed in the header) is actually two heads, not one
  2. treble artifact bursts — modulate bitCrush upward briefly on treble transients for
     crunchy bit-crush bursts layered on top of the static slider value
FORBID: a full multi-pass motion-vector datamosh (out of scope for this file); new spring
A PACKING: unchanged — display RGBA in A
NOTE: params[3] "Unused" is already read as `artifactAmt` in code — renaming to
  "Artifact Amount" in JSON to match reality (§8 "tell the truth"), not a new param.
```

```
SHADER: temporal-echo
IDENTITY: brightness-driven feedback echo with ripple-pinned history frames and
  accumulative alpha
KEEP VERBATIM: accumulativeAlpha/depthLayeredAlpha functions, brightness-driven
  history_offset, ripple-pin logic, echoDecay blend
ADD:
  1. user-controlled echo depth — `temporalOffset` (zoom_params.w) is read but never
     used; wire it as an additive frame-lag bias on history_offset so the slider
     actually deepens/shallows the echo independent of brightness
  2. bass-transient echo pinning — detect a rising bass edge (via a lightweight
     extraBuffer-free heuristic: compare plasmaBuffer bass to a fixed decay threshold
     approximated from time) — pin a fresh echo frame on the beat, layered alongside the
     existing click-ripple pin, for rhythmic strobing
FIX (prerequisite, not the idea): `audioOverall = u.zoom_config.x` reads time, not audio
  (zoom_config.x duplicates config.x per BINDING_CONTRACT). Audio-reactive claims must
  read `plasmaBuffer[0].xyz`. Also clamp the unbounded dataTextureC coordinate in the
  "past" lookup, which could read outside the texture.
FORBID: replacing the offset-history mechanism with a ring-buffer redesign
A PACKING: unchanged — accumulated RGBA in A
```

```
SHADER: viscous-drag
IDENTITY: pointer-dragged thick-liquid displacement field, advected by a slow rotating
  jet, with traveling vortex packets and click pressure fronts
KEEP VERBATIM: RG offset diffusion/advection via dataTextureC, viscosity/dragStrength/
  recovery/scale params, jetDirection rotation, vortexForce, click force/pressure,
  specular ridge lighting, ACES tonemap
ADD:
  1. shear-thinning viscosity — modulate the diffusion mix weight by the already-computed
     `strain` so heavily-sheared regions temporarily thin (lower effective viscosity),
     mimicking real non-Newtonian shear-thinning fluid
  2. bass jet surge — a bass transient briefly adds a secondary burst direction on top of
     the constant rotating jetDirection, reading as the liquid getting "pumped" on the beat
FORBID: replacing the advection/diffusion solver; new particle system
A PACKING: unchanged — RG offset, thickness, drag energy in A (raw sim state, not display)
```
