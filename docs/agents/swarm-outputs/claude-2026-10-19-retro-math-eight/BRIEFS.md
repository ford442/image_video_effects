# Claude retro-math-eight — Idea Cards

Written before WGSL edits. 2026-10-19.

Batch: digital-glitch, phosphor-decay, vhs-chroma-bleed, crt-tv, poincare-tile, anaglyph-3d,
complex-exponent-warp, tile-twist. Only tile-twist pasted the 13 bindings; it was migrated to
`#include "_prelude.wgsl"` first in a separate header-only commit (not counted). Six files already
carry `Ideas:` (phosphor-decay, vhs-chroma-bleed, crt-tv, poincare-tile, anaglyph-3d,
complex-exponent-warp); their prior ideas stay and new ideas continue the numbering.

## digital-glitch

```
SHADER: digital-glitch
IDENTITY (one sentence): the photo pushed through byte-level corruption — block shifts and tears,
  per-channel bit flips / rotations / XOR / nibble swaps, neighbour error mixing, bit-depth decay
  and posterize, RGB split, block inversion — with an error mask carried in C.
KEEP VERBATIM: 4 params (corruption intensity, bit manipulation, error propagation, decay rate);
  spring [133..138]; ripple bursts; block displacement and tears; the per-channel corruption loop
  and corruptByte op set; propagateError; applyDigitalDecay's bit-depth + posterize chain; RGB
  split; inversion; scanlines; vignette; ACES; A = (errorMask, luma, intensity, alpha).
MECHANISM INTERROGATION:
  t6 (use the history): A.r is an error mask, but C is only read at the pixel itself, so
    "error propagation" never actually spreads.
  t2 (physics one step further): the bit-depth decay uses `time·decayRate`, which never resets —
    after ~15 s at full decay the picture is permanently 1-bit. Real memory decays between
    refreshes and is restored by a refresh cycle.
  t5 (artifact of the real device): a stuck line on a data bus forces the same bit in every word
    that crosses it — coloured vertical bands.
ADD (3 native ideas):
  1. Error infection — the mask spreads from C: each pixel takes the max of four neighbours'
     C.r 3 px away, scaled by Error Propagation, so corruption grows outward frame by frame and
     recedes when the source stops.
  2. Refresh cycle — bit decay accumulates per row over a refresh period (shorter at higher Decay
     Rate) and a refresh line sweeps down restoring full depth, with a faint bright refresh
     scanline. Bounded in time.
  3. Stuck bus lines — a few column groups (re-rolled every few seconds, more at higher intensity)
     force one bit high or low in every channel byte.
FORBID on this file: springs beyond the existing one, new click fronts, IQ palette.
A PACKING: (errorMask, luma, intensity, alpha) — unchanged.
```

## phosphor-decay

```
SHADER: phosphor-decay (second pass; first pass 2026-09-28)
IDENTITY (one sentence): the picture as persistent CRT phosphor — per-channel decaying trails mixed
  in OkLab, bloom, shadow mask, scan blanking, burn-in, held static charge, vblank flicker,
  blackbody grade.
KEEP VERBATIM: 4 params (decay rate, bloom spread, shadow mask, scan blanking); per-channel decay
  constants; OkLab merge; burn-in EMA in A.a; crackle + dust; vblank; click bloom; haze; blackbody;
  vignette / ACES / dither; A = linear HDR phosphor RGB + burn-in.
MECHANISM INTERROGATION:
  t2 (physics one step further): real phosphor afterglow is not exponential — trap recombination
    gives a hyperbolic (bimolecular, dI/dt = −kI²) tail: bright excitation drops fast, a dim tail
    lingers.
  t5 (artifact of the real device): light from a bright phosphor spot reflects inside the
    faceplate glass and returns as a halation ring at a fixed radius (≈ 2× glass thickness).
ADD (2 native ideas):
  4. Hyperbolic afterglow — the per-channel decay factor is divided by (1 + k·I) and renormalised
     at a reference level, so bright trails collapse quickly and dim ones linger.
  5. Faceplate halation ring — 8 exact C taps on a ring (radius ~9 px) gather last frame's bright
     phosphor and add a dim warm ring around highlights; rides Bloom Spread.
FORBID on this file: springs, click fronts, IQ palette, any new feedback channel.
A PACKING: linear HDR phosphor RGB + burn-in luma — unchanged.
```

## vhs-chroma-bleed

```
SHADER: vhs-chroma-bleed (second pass; first pass 2026-09-28)
IDENTITY (one sentence): a VHS tape playback of the photo — R/B bleed, tracking wobble, colour-under
  chroma delay, cross-colour crawl, dropout rows, grain, scanlines, barrel, warmth.
KEEP VERBATIM: 4 params (chroma shift, noise, jitter, bleed width) and HEAD's slot use; Ideas 1–3;
  bleed / jitter / drift / tracking / vhsCA chain; grain, scanlines, vignette, warmth, roll-off,
  compression, noise bands; ACES; A = display RGB + source alpha.
MECHANISM INTERROGATION:
  t5 (artifact of the real device): head-switching noise — the bottom few lines of every VHS frame
    are skewed sideways and noisy where the drum switches heads.
  t5: a VCR's playback "sharpness" circuit is a luma peaking filter — bright/dark halos ringing on
    edges, on Y only.
ADD (2 native ideas):
  4. Head-switching band — the bottom ~2.5% of the frame shears sideways (growing toward the
     bottom, re-jittered ~30×/s) and picks up line noise. Scales with jitterAmt (the Noise
     slider, zoom_params.y).
  5. Luma peaking — Y gets Y + k·(Y − mean(Y±1.5 px)) before the chroma path, so edges carry
     the VCR's sharpness halo while chroma stays soft.
FORBID on this file: springs, ripple fronts, IQ palette, a second tracking system.
A PACKING: ACES display RGB + source alpha — unchanged.
```

## crt-tv

```
SHADER: crt-tv (second pass; first pass 2026-09-28)
IDENTITY (one sentence): the photo on a curved CRT — beam-width scanlines, aperture grille,
  halation, phosphor glow and decay, rolling hum bar, rounded faceplate with glare, C persistence.
KEEP VERBATIM: 4 params (scanline intensity, phosphor glow, halation, barrel); spring; Ideas 1–3;
  curveUv, tube mask, chromaticAberration offset, scanBeam, grille, halation, decay, vignette;
  ACES; A = pre-ACES HDR phosphor RGB.
MECHANISM INTERROGATION:
  t5 (artifact of the real device): the three guns misconverge toward the corners — R and B
    beams land radially offset from G, growing with r²; here the split is a constant horizontal
    shift.
  t2 (physics one step further): a bright picture draws beam current, the high voltage sags and
    the raster grows ("breathing").
ADD (2 native ideas):
  4. Corner misconvergence — R/B sample offsets gain a radial term ∝ r² on the curved raster,
     scaled by Barrel, on top of HEAD's horizontal split.
  5. High-voltage breathing — a 9-tap average picture level scales the raster about the centre
     (bright frames bloom outward by up to ~2.5%), scaled by Barrel.
FORBID on this file: springs beyond the existing one, new click fronts, faceplate ideas
  duplicated from phosphor-decay.
A PACKING: pre-ACES HDR phosphor RGB + semantic alpha — unchanged.
```

## poincare-tile

```
SHADER: poincare-tile (second pass; first pass 2026-10-16)
IDENTITY (one sentence): the photo tiled through Möbius-transformed coordinates in the Poincaré
  disk, cut into p angular sectors with geodesic ink and rim cusps, drifting with time and pointer.
KEEP VERBATIM: 4 params (curvature, symmetry, anim speed, tile scale); hyperbolicTranslate /
  rotate chain; getPolyParams; sector reduction; texUV = fract(w·scale); ripples; boundary;
  edgeDarken; tile hue; Ideas 1–2; ACES; A = display RGBA.
MECHANISM INTERROGATION:
  t5 (artifact of the real thing): in a reflection-group tiling adjacent tiles are mirror images
    of each other; here every sector shows the same orientation.
  t3 (promote an intermediate): `hyperbolicDist` exists, but the metric itself is never visible —
    equal hyperbolic steps crowd toward the rim.
ADD (2 native ideas):
  3. Reflection parity — odd sectors sample the image reflected across their own axis, so
     neighbouring tiles mirror each other like a true kaleidoscopic tiling.
  4. Equidistant rings — faint rings at equal hyperbolic distance from the moving centre
     (d = 2·atanh|w|), which crowd toward the rim and show the metric.
FORBID on this file: springs, IQ palette, a different tiling algorithm.
A PACKING: ACES display RGBA — unchanged.
```

## anaglyph-3d

```
SHADER: anaglyph-3d (second pass; first pass 2026-06-28)
IDENTITY (one sentence): a red/cyan anaglyph of the photo from its depth map — forward-warp view
  synthesis per eye, ghosting, crosstalk, convergence shimmer, plus grain / scanlines / vignette /
  grade / streaks / dirt.
KEEP VERBATIM: 4 params (separation, depth curve, ghost, grain); synthEye structure; mouse focal
  depth; Ideas 1–3; post chain; C ghost persistence; ACES; A = display RGBA.
MECHANISM INTERROGATION:
  t1 (deepen the kernel): the eyes are combined by raw channel split (R from left, GB from right);
    the colour-optimised standard is Dubois' least-squares projection through the filter spectra.
  t2 (physics one step further): stereographers keep parallax inside a depth budget;
    here parallax grows linearly with separation × depth curve without limit.
ADD (2 native ideas):
  4. Dubois projection — each eye's full RGB goes through Dubois' red/cyan matrices, blended 50%
     with HEAD's channel split: less retinal rivalry on saturated reds and cyans.
  5. Depth budget — inside synthEye the landing shift is soft-compressed (budget·tanh(raw/budget)),
     so extreme separation stays fusible instead of tearing.
FORBID on this file: springs, click fronts, IQ palette.
A PACKING: ACES display RGBA — unchanged.
```

## complex-exponent-warp

```
SHADER: complex-exponent-warp (second pass; first pass 2026-10-05)
IDENTITY (one sentence): the photo mapped through z^w (w from the pointer) with fbm warp, Riemann
  sheet crossfade, conformal magnification, mirrored tiling, Julia orbit glow, Newton overlay and
  a cardioid mask.
KEEP VERBATIM: 4 params (scale, spiral, exponent spread, uv warp); complex_pow; Ideas 1–3;
  overlays; fog; ACES; A = display RGBA.
MECHANISM INTERROGATION:
  t3 (promote an intermediate): result_z is the value of the map; complex analysts read a
    conformal map through iso-arg / iso-log-modulus contours, which cross at right angles.
  t1 (deepen the kernel): chromatic aberration is a linear radial offset unrelated to the map; a
    dispersion native to the map is a per-channel exponent.
ADD (2 native ideas):
  4. Conformal grid — faint contour lines of arg(z^w) and log|z^w| (domain-colouring grid) over
     the image; they stay orthogonal under any w.
  5. Exponent dispersion — red and blue are sampled with w·(1 ± δ), so colour fringes follow the
     map's own spirals; δ rides UV Warp and treble, offset length capped.
FORBID on this file: springs, click fronts, IQ palette, a new fractal overlay.
A PACKING: ACES display RGBA — unchanged.
```

## tile-twist

```
SHADER: tile-twist
IDENTITY (one sentence): the photo cut into a jittered grid of tiles, each rotating the image
  about its own centre (Lissajous + hash + bass pulse + pointer drag), with quilt palette, moiré
  seams, CA and a C trail.
KEEP VERBATIM: 4 params (tile size, twist, radius, edge smoothness); grid / jitter / angle
  formula; domain warp; voronoi ridge; quilt + moiré; CA; hue rotate; sparkle; A = (bass env,
  trail RGB).
MECHANISM INTERROGATION:
  t5 (artifact of the real thing): a twisting tile is a plate — when it turns, its corners leave
    the cell and reveal the grout behind, and its edges catch light at a turning angle. Here the
    edge mask is static and never shows the rotation.
  t2 (physics one step further): a tile turning fast smears along its arc; the angle formula is
    analytic in time, so its angular velocity is free.
ADD (2 native ideas):
  1. Turning plates — a rounded-box SDF in the tile's ROTATED frame: grout shows where the turned
     plate leaves the cell, and a fixed-light bevel shades its rotating edges.
  2. Arc blur — two extra taps along the rotation arc between the angle at t − 1/30 s and now,
     weighted by angular speed.
FORBID on this file: springs, new click fronts, replacing the quilt palette.
A PACKING: (bass envelope, trail RGB) — unchanged.
```
