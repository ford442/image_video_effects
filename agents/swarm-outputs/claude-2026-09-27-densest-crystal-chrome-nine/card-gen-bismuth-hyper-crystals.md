```
SHADER: gen-bismuth-hyper-crystals
IDENTITY: a raymarched field of stepped boxes folded by a KIFS abs-fold loop with an xz rotation, shaded with the
  existing cosine iridescence palette, Blinn specular and step-count AO — a growing bismuth hyper-crystal.
KEEP VERBATIM: rot (L30), abs-fold + box map structure (L36-63), the stepping term floor(length(p)*10)/10 as the
  bismuth staircase (may soften its normal spikes), iridescence() palette (L75) as the base colour, 4 slider roles
  (x Complexity = fold count, y ColorShift = palette phase, z GrowthSpeed = rotation/growth, w Specular), saved params.
FIX/WIRE (major first):
  - HEAD CAMERA INSIDE GEOMETRY: at t=0/bass=0 the fold fills a cube of half-size ~n+1, so map(0,0,-5) < 0 for
    Complexity >= ~0.2 INCLUDING the default 0.5 -> every ray hits at step 0, frame is one flat colour. Pull the camera
    back / bound the fold region so map(ro) > 0 for x in {0,0.5,1}; prove with a numpy port of map() (camera outside,
    a surface exists in view).
  - uv not flipped (L88-91): screen top = -y -> flip.
  - z GrowthSpeed: rotation = config.x*z*0.1 (L49) -> phase jumps when the slider moves; accumulate phase as time*const
    with z scaling something continuous, or keep but make growth idea carry the slider (explain).
  - w Specular: exponent w*100 (L127) -> pow(x,0)=1 white sheet at w=0 and pow(0,0) undefined; floor the exponent (e.g.
    max(w*100, 2)); default 0.8 must stay 80.
  - Audio from extraBuffer[0] (L42) -> plasmaBuffer[0].x; FFT read extraBuffer[4u+bin] (L130) is off by one -> 5u+bin.
  - No A write, no depth, no C read, no ACES (gamma only, specular clips), alpha 1.0. Add: A = HDR + alpha, exact C
    read (a light temporal blend is optional, not an idea), depth near 1/miss 0, ACES on writeTexture, semantic alpha.
  - Integer fold count i32(x*5+3) pops (L46) — folded into idea 2.
ADD (native ideas):
  1. Nucleation seed under the cursor — HEAD computes distToMouse (L40) and never uses it. Map the pointer to a seed
     point in the crystal and let the fold offset (1.0 at L47) shrink with distance to the seed, so the crystal is
     densest/finest where it nucleates and coarsens outward. Default mouse (0.5,0.5) = a centred seed that reproduces
     roughly the HEAD structure.
  2. Fractional fold growth — the crystal actually grows: blend fold iteration n and n+1 by a fractional growth phase
     (Complexity picks the base count continuously, GrowthSpeed advances the growth cycle), so new terraces of folded
     boxes emerge smoothly instead of popping.
  3. Fold-lineage colour — record the sign-flip history (which abs() planes flipped, per iteration) inside the fold
     loop and offset the EXISTING iridescence palette phase by that lineage, so sibling crystals of the same fold
     branch share a hue family.
FORBID: thin-film/oxide/tarnish, hopper terraces, twin seams, melt-pool bands, axial beacon, self-assembling sectors,
  spring cursor, ripple rings.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha.
DEFAULT-LOOK SHIFT: HEAD is one flat colour at default; now a visible crystal. Not GPU-verified.
```

STATUS: draft (coordinator) -> superseded by Final below


## Final (implementer, 2026-09-27)

Audit claims (HEAD):
- Camera inside geometry: CONFIRMED by numpy port (scratch `gen-bismuth-hyper-crystals/head_port.py`). map(0,0,-5) < 0 for
  Complexity 0.2/0.5/1.0 at t=0/10/60; Complexity 0 is barely outside (0.07 at t=10). The fold is a solid cube of
  half-size n+1 (numpy occupancy: 17.6% of the bounding box, flat histograms), so HEAD's default was one flat colour.
- uv not flipped, rotation phase = time*z*0.1, pow(x, w*100) at w=0, extraBuffer[0] audio, FFT off-by-one
  (extraBuffer[4u+bin]), no A/depth/C/ACES, alpha 1.0, integer fold pop: all CONFIRMED.

FIX done:
- Camera: corner view (fwd = normalize(-0.75,-0.7,1)), distance 1.3*R where R = (folds+1)*1.75+0.25 bounds the solid
  (numpy max-radius 10.4/15.5 vs bound 10.75/16). Numpy: map(ro) > 0 for Complexity {0,0.5,1} x t {0,10,60,300};
  hit fraction ~0.37 of frame, three faces with terraces visible. March starts at bounding-sphere entry, step x0.9.
- uv flipped (screen top = +y); spec exponent max(w*100, 2) (default 0.8 still 80); audio bass = plasmaBuffer[0].x;
  FFT = extraBuffer[5u+bin]; staircase keeps floor(length(p)*10)/10 but the riser is a smoothstep bevel (normal
  spikes softened); normal epsilon scales with ray distance.
- A = HDR (pre-ACES) + semantic alpha, exact textureLoad(dataTextureC, coord, 0) 0.12 blend; ACES only on
  writeTexture; depth = 1 near .. 0 far on hit, 0 on miss; alpha = 1 on hit, near-miss rim glow on miss.
- GrowthSpeed: kept as time*z (HEAD role: rotation rate) - stateless, so dragging the slider still jumps phase
  (extraBuffer scratch does not persist; no A texel hijack). The growth cycle rides the same phase.

Ideas as implemented (public/shaders/gen-bismuth-hyper-crystals.wgsl):
1. Nucleation seed under the cursor - L39-40, L72-75 (foldOff = 1 - 0.3*gauss(dist to seed)), L166-169 (seed on the
   pointer ray, 0.55R inside the near surface). Numpy render: finer terrace grid under the seed, coarse elsewhere.
2. Fractional fold growth - L37, L77-81, L101-107 (dN after n folds, dN1 after n+1, mix by fraction), L146-154
   (folds = x*5+3 + (0.5-0.5cos(6*phase)); at GrowthSpeed 0 exactly the HEAD count, continuous).
3. Fold-lineage colour - L88-93 (3-bit abs-plane sign code per generation, weights 0.5^i), L218-222 (phase offset
   lineage*0.4 on the EXISTING iridescence thickness).

Audio roles (not ideas): bass nudges fold rotation (HEAD bass_mod), FFT bin by height shifts palette phase (HEAD).
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha; C read back as HDR.
Refused/skipped: no ripples/spring (HEAD had none); no persistent growth phase (no valid state slot).
DEFAULT-LOOK SHIFT: HEAD default = one flat colour (camera inside). Now a corner-viewed iridescent terraced cube
crystal with a finer nucleus at the pointer. Numpy-previewed only; NOT GPU-verified.
Gates: naga OK; wgsl_precommit_gate PASS; audit_dead_sliders PASS (1305 scanned, all 4 zoom_params read).
JSON: params byte-exact; features += mouse-driven, upgraded-rgba.

STATUS: final
