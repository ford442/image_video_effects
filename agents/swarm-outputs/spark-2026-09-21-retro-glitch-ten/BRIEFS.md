# Retro-Glitch Ten — Idea Cards (written before any WGSL edit)

**Agent:** spark · **Date:** 2026-09-21 · **Contract:** `docs/SHADER_UPGRADE_BATCH.md` §0/§2/§7

## Why this batch is a *second pass*, not a first one

All ten files already carry the plumbing floor: canonical 13 bindings, `@workgroup_size(16,16,1)`,
ACES, semantic alpha, exact `textureLoad(dataTextureC, …)`, three-band `plasmaBuffer[0].xyz`,
`extraBuffer[133..139]` springs, capped ripple loops, live `zoom_params`, `updatedParams` in JSON.

Seven of them are stamped `// … Composer batch cyber/digital/glitch` and their header line reads,
verbatim, *"spring cursor, held burst, capped ripples, exact C loads, three-band audio, ACES +
semantic alpha."* That is §4.3 — the generic overlay — already applied. Per §9 these count as
**not upgraded**: floor present, zero native ideas.

So this batch adds **no springs, no ripple shockwaves, no IQ cosine palettes, no new conveyors.**
Every idea below extends the mechanism the file already simulates. Where a spring or a ripple loop
already exists it is left exactly as-is and, in three files, finally given something to *do*.

---

## 1. `crt-phosphor-decay`

```
SHADER: crt-phosphor-decay
IDENTITY: a photo burned into a CRT's phosphor — bright areas leave a coloured after-image that
          decays at a different rate per channel, under scanlines, a subpixel triad mask and halation.
KEEP VERBATIM: decay_rate / scanline_intensity / halation_spread / audio_sensitivity roles;
          the max(fresh, decayed) persistence rule; the per-channel decay ratios (G ×0.97, B ×0.94);
          halation() 5-tap; subMask triad; existing spring + click bloom (this shader is pointer-led).
ADD (3 native ideas):
  1. Two-rate phosphor knee — real P22 does not decay as one exponential. It dumps fast while the
     grain is hot, then crosses into a long tail. Split decayBase into a fast rate above an
     excitation knee and a slow tail below it, blended by the stored history's own luma.
     Belongs here because persistence IS the effect; right now it is a single flat multiply.
  2. Triad-aligned grain bleed — phosphor grains bleed into their neighbours in the mask, not into
     the pixel grid. Bleed the *decayed history* horizontally with weights taken from the subpixel
     mask, so the smear follows the triad. Belongs here because the mask is already drawn.
  3. Interlaced field parity — odd and even scanlines refresh on alternate fields, so half the raster
     is always one field older. Gates the decay by row parity against frame parity.
FORBID on this file: new palettes, new pointer mechanics, anything that stops it reading as a tube.
A PACKING: display RGBA in A (C is read as colour). Unchanged — the knee reads excitation from
          history luma rather than claiming a new channel.
```

## 2. `crt-magnet`

```
SHADER: crt-magnet
IDENTITY: a magnet held against a CRT — the raster is pulled toward the pointer, the three guns
          separate, the aperture grille and bloom follow the distortion.
KEEP VERBATIM: magnet_strength / bloom_intensity / color_shift / distortion_radius; barrel();
          falloff × sdfMask × depthAtten field; hex bloom taps; degauss ring; beam sweep; C echo;
          the existing palette calls (already shipped identity, not mine to strip).
ADD (3 native ideas):
  1. Tangential convergence error — the three guns sit on a ring 120° apart, so a magnet mis-converges
     them *around* the field, not along one axis. Rotate each gun's sample offset by its own gun angle
     scaled by field strength, replacing the fixed 1.35 / 1.00 / 0.70 scalar ladder. Belongs here
     because gun separation is the whole effect and it is currently a 1-D smear.
  2. Warped shadow-mask moiré — the grille is currently locked to `global_id.x % 3`, i.e. to the pixel
     grid, so it cannot beat. Drive it from the *displaced* screen position so the mask compresses
     where the raster is pulled and beats against the scan into moiré. That is the artifact a magnet
     actually produces.
  3. Purity stain with degauss erase — magnetisation leaves a colour stain that the degauss coil
     clears as it sweeps. Retain the C echo's *chroma* (not its luma) where the field is strong, and
     multiply that retention by (1 − degauss) so the existing ring visibly wipes the stain.
     Gives the already-present degauss ring its first actual job.
FORBID on this file: a fourth palette, more bloom layers, any new overlay — this file is already
          over-stacked; these three replace flat code paths rather than adding a layer.
A PACKING: display RGBA in A (C read as colour echo). Unchanged.
```

## 3. `vhs-tracking`

```
SHADER: vhs-tracking
IDENTITY: a tape whose tracking is off — every row walks horizontally, chroma smears from azimuth
          loss, the head-switch band tears the bottom, dropouts punch white.
KEEP VERBATIM: Tracking Error / Noise Level / Color Drift / Scanlines mapping; the per-row random-walk
          read from C at (0, y); capstan sine; YIQ transform pair; azimuth chroma blur; head band;
          A's raw-state packing (walk, dropoutMask, phaseShift, headBand).
ADD (3 native ideas):
  1. Head-switch skew / flagging — after the head switches, tape tension has not settled, so the top
     few percent of the frame bends horizontally. Add an exponential-in-y skew to the existing
     totalOffset, scaled by Tracking Error. The single most recognisable VHS artifact and it is absent.
  2. Dropout-compensator line repeat — a real VCR conceals a dropout by repeating the *previous line*,
     not by printing white noise. Where dropoutMask fires, pull the row above and blend, leaving the
     hash only as residue. Turns a crude flash into the actual artifact.
  3. Line-alternate chroma phase — VHS records chroma "under" with phase inverted on alternate lines.
     Flip the sign of the existing phaseShift by row parity so chroma crawl reads as a comb pattern
     instead of a uniform hue wobble.
FORBID on this file: colour palettes, bloom, anything that is not a tape transport or a signal path.
A PACKING: raw sim state in A — walk / dropout / phase / headBand, exactly as HEAD. Unchanged.
```

## 4. `signal-noise`

```
SHADER: signal-noise
IDENTITY: a composite signal falling apart over the photo — head-switch band, 8×8 block artifacts,
          chroma noise injected in YUV, fbm smear, temporal decay.
KEEP VERBATIM: vhsIntensity / artifactStrength / smearAmount / chromaStrength; rgbToYuv/yuvToRgb;
          vhsHeadSwitch(); dctBlockArtifact() ring+checker; fbm smear vectors; C temporal decay.
ADD (3 native ideas):
  1. Luma-shouldered noise — tape and composite noise is not uniform: it sits in the darks and cleans
     up in the highlights. Weight the injected noise by a shoulder on Y instead of adding it flat.
  2. Real quantisation staircase — the block artifact is currently a decorative ring. Actually quantise
     each 8×8 block's mean luma to a level count driven by artifactStrength, so flat areas band and
     the tiles become visible as compression, which is what the ring is gesturing at.
  3. Dot crawl on vertical luma edges — composite crosstalk puts a frame-alternating subcarrier
     pattern along sharp vertical transitions. Native to the signal path already modelled in YUV.
FORBID on this file: springs beyond the one already present, new pointer mechanics, palettes.
A PACKING: display RGBA in A (C read as colour). Unchanged.
```

## 5. `byte-mosh`

```
SHADER: byte-mosh
IDENTITY: an 8×8-block bitstream decoder coming apart — an LFSR good/bad Markov state per block,
          GF(2) XOR masks on packed RGB8, wrong-frame block displacement, rainbow at block boundaries.
KEEP VERBATIM: operationMix / bitShift / errorRate / blockSize; lfsr_step / lfsr_advance / galois_mult;
          the good→bad / bad→good transition probabilities; pack_rgb8 / unpack_rgb8; the raw block
          state packed into A as (lfsr, burstMask, corruptionAge, mode); the left/up boundary read.
ADD (3 native ideas):
  1. Motion-vector inheritance — this is what datamosh actually is. A corrupt block should inherit its
     neighbour's displacement so corruption smears in connected streaks, instead of every block drawing
     an independent random offset. Decode an offset from the already-loaded left/up block state and
     blend it in by corruptionAge.
  2. Keyframe recovery flash — an I-frame resets the decoder. On the bad→good transition, snap the
     block back to clean source with a visible bloom so the effect breathes between corruption and
     recovery rather than sitting at a constant error rate. corruptionAge is already tracked.
  3. Row desync trail — a bitstream error desyncs the decoder for the remainder of the scan row.
     Propagate a per-row desync from the erroring block's x so corruption trails rightward and decays.
FORBID on this file: display-RGBA promotion of A, palettes, any new sim.
A PACKING: raw block state in A, read back at block origin. Unchanged — new ideas ride existing fields.
```

## 6. `xerox-degrade`

```
SHADER: xerox-degrade
IDENTITY: a photocopy — sigmoid-crushed contrast, halftone dots over Bayer dither, paper white,
          toner smear dragged sideways.
KEEP VERBATIM: contrast / grain / smear / threshold; sigmoidContrast(); bayer4x4(); halftoneDot();
          the paper colour and the ink colour; smear UV displacement; edgeVignette.
ADD (3 native ideas):
  1. Toner starvation bands — a copier low on toner leaves slow vertical light streaks that follow the
     drum. Modulate the final ink coverage by a drifting drum-phase band, strongest where coverage is
     highest. The most recognisable photocopier failure and it is absent.
  2. Mach-band edge halo — copiers over-sharpen. Subtract a blurred copy of the *thresholded* luma so
     dark regions get a white fringe just outside their edge, the way copied text does.
  3. Compounding generation loss — the C history is currently a flat 12 % blend that does nothing.
     Re-thresholdiing the history through the same sigmoid each frame makes contrast compound and
     midtones fall out over time: a copy of a copy of a copy. Gives the existing memory a meaning.
FORBID on this file: colour, bloom, pointer mechanics beyond the smear that is already there.
A PACKING: display RGBA in A (C read as colour). Unchanged.
```

## 7. `ascii-flow`

```
SHADER: ascii-flow
IDENTITY: the photo re-rendered as a grid of eight procedural glyphs chosen by cell brightness,
          drifting on a noise flow field and repelled by the cursor.
KEEP VERBATIM: intensity / speed / scale / detail; all eight draw_glyph() shapes and their indices;
          grid_dims; the flow + repel + held-vortex field; the cosine tint and its mix weight;
          the light C smear.
ADD (3 native ideas):
  1. Ink-coverage ramp — index→glyph is currently arbitrary (dot, |, —, +, /, \, X, box), so the tonal
     ramp is non-monotonic and the source image does not read through the glyphs. Remap brightness to
     the glyphs *ordered by how much ink they actually put down*. Same eight shapes, now a real ramp.
  2. Coverage-weighted glyph weight — a half-lit cell should render a half-weight glyph. Weight the
     glyph by the cell's target coverage instead of drawing it binary, so tone survives quantisation.
  3. Typed-cell wake — cells the pointer crosses latch a bright "just typed" state that decays through
     the existing C smear, so the cursor *writes* characters rather than only shoving them.
FORBID on this file: replacing the glyph set, a second palette, springs (this file has no spring and
          does not need one — its pointer term is a flow-field repel and stays that way).
A PACKING: display RGBA in A (C read as colour). Unchanged.
```

## 8. `pixelation-drift`

```
SHADER: pixelation-drift
IDENTITY: a mosaic whose block grid drifts on noise, with chromatic split per block, block size
          scaled by depth, and a sharpening focus lens under the cursor.
KEEP VERBATIM: pixelSize / driftSpeed / colorBleed / depthInfluence; the floor-quantised UV; the
          depthFactor and focusLens; the R/B chroma split; colour bleed branch; C persistence.
ADD (3 native ideas):
  1. Block area average — the mosaic currently point-samples one corner of each block, so it flickers
     as the grid drifts and loses the picture. Average four taps inside the block. Mosaic means
     averaging; this is the core mechanism finally being correct.
  2. Block colour quantisation — quantise each block's colour to a level count tied to its size, so
     large blocks also get coarse colour. Position and colour quantise together, which is the
     low-bit mosaic look the effect is reaching for.
  3. Drift-lit tile bevel — the existing edge glow is a flat 1.2× multiply. Light the tile edge from
     the drift direction so tiles read as being pushed, which is what "drift" promises.
FORBID on this file: ripple shockwaves beyond the click pulse already present, palettes, new sims.
A PACKING: display RGBA in A (C read as colour). Unchanged.
```

## 9. `spectrum-bleed`

```
SHADER: spectrum-bleed
IDENTITY: hue-rotating ink bleeding out of a blurred copy of the photo, persisting in a
          velocity-advected history and saturating where the pointer clicks.
KEEP VERBATIM: intensity / hue speed / blur scale / saturation detail mapping; rgb2hsv / hsv2rgb;
          blurSource(); the spring and the advected historyUv read; click ink saturation; fft hue push.
ADD (3 native ideas):
  1. Wavelength-ordered bleed distance — a spectrum bleed should separate *by* wavelength. Give
     blurSource a per-channel radius (blue furthest, red least) so the bleed produces real spectral
     fringes instead of one uniform blur. The name of the effect, finally true.
  2. Chromatographic advance front — ink on paper piles into a travelling band, it does not smear
     evenly. Gate the history persistence on the local saturation gradient so the bleed accumulates
     into a front instead of a flat wash.
  3. Dry-edge rim — where the front halts, concentration leaves a darker ring (the coffee-ring line).
     Derive it from current-minus-history saturation and darken there.
FORBID on this file: a second palette, new pointer mechanics — the spring and click ink stay as-is.
A PACKING: display RGBA in A; C is read as colour through a velocity-advected coord. Unchanged.
```

## 10. `vinyl-scratch`

```
SHADER: vinyl-scratch
IDENTITY: the photo spinning on a record — rotation about the label, groove rings, wobble, dust,
          sparkle, chromatic wobble, warm vignette.
KEEP VERBATIM: the four saved params exactly as mapped in HEAD (zoom_params.x→rotationSpeed,
          .y→scratchAmount, .z→wobble, .w→noiseIntensity — the JSON names read
          scratch_density/dust/warping/sepia; this mismatch is HEAD's and is NOT rewired here);
          rotation, groove rings, vinylDust, grooveReflection, grooveSparkle + its C coherence,
          temporalGrain, vignette, analogWarmth, saturationRolloff, lensDirt, radialChromatic.
ADD (3 native ideas):
  1. Eccentric spindle wow — an off-centre hole makes the whole image swing once per revolution.
     Orbit the rotation centre itself by a small eccentric offset at the rotation rate. This is *the*
     vinyl artifact; the current "wobble" is an angular ripple, not eccentricity.
  2. Radius-dependent groove pitch + label — real grooves tighten toward the centre and stop at the
     label. Make the ring frequency a function of radius instead of a constant 400, and cut an inner
     label disc. Makes it read as a record rather than as concentric rings.
  3. Stylus scratch marks — a click currently only nudges rotation. Let it cut a short damaged arc at
     the clicked radius that rides the rotation and decays with the ripple's own lifetime, so
     scratching the record leaves a mark on the record.
FORBID on this file: new palettes, new solvers, promoting A away from display RGBA.
A PACKING: display RGBA in A. Note HEAD reads C.a back as a sparkle-coherence proxy; that is alpha
          being reused, documented here and left intact rather than silently repacked.
```

---

## Shared discipline for this batch

- Zero new springs. Zero new ripple loops. `ascii-flow` deliberately stays spring-free.
- No file gets an idea that appears in another file's card. Ten cards, thirty distinct ideas.
- The two CRT files are the only adjacency risk: `crt-phosphor-decay` is persistence chemistry,
  `crt-magnet` is deflection geometry. No shared code path between them.
- Saved `params` byte-exact everywhere. `updatedParams` aligned additively only.
- `Upgraded:` / `Ideas:` / `A packing:` header lines added only where an idea actually landed.
