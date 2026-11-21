# Idea Cards — Grok (optical / geometry ten, 2026-11-21)

Written before the WGSL edits. Ten shaders the user listed by size. Each card adds two ideas in the existing main path. Saved `params` stay byte-exact. No shared spring, shockwave, or palette is added. Springs, click paths, and earlier ideas that are already in a file stay as they are.

Seven files still paste the binding header (`pp-chromatic`, `pixel-storm`, `gen-temporal-motion-smear`, `infinite-fractal-feedback-hdr`, `gen-hyperbolic-tessellation`, `solarize-warp`, `spec-importance-sampled-bokeh`). Migrating them to `#include "_prelude.wgsl"` is infrastructure and is not an idea.

Formula rule: a §12.2 row is newly applied on at most one file here.

- Field interlace (§12.2B) is `crt-clear-zone` only.
- Energy-conserving bloom (§12.2F) is `infinite-fractal-feedback-hdr` only.
- Airy disc (§12.2F) is `spec-importance-sampled-bokeh` only.
- No other §12.2 row is newly applied. Cauchy on `pp-chromatic` is already in the file.

```
SHADER: pp-chromatic
IDENTITY (one sentence): a photo through a pointer-centered lens with five-wavelength Cauchy fringes, a mode-mixed smear direction, vignette, and click refraction.
KEEP VERBATIM: Chromatic Amount / Distortion / Vignette / Mode; lensWarp Brown-style r²+r⁴; five Cauchy wavelengths and the R/G/B binning; mode mix radial→axial→tangent; longitudinal defocus disc; purple fringe on clipped highlights; click fronts; spectral caustic; exact-C fringe persistence; ACES display.
MECHANISM INTERROGATION:
  tactic 2: a real lens focuses on a curved Petzval surface, and off-axis points grow a radial coma tail. Focus depth is a single sample at the lens centre. The smear direction is already radial.
  tactic 3: field radius is computed for the vignette and then unused by the focus.
  tactic 6: C is display color. The fringe persistence mix stays. Do not pack focus into A.
ADD:
  1. Petzval field curvature — the existing focal depth bows with field angle squared, sign following Distortion, so axial CA goes soft toward the corners on a curved focal surface.
  2. Comatic smear — red and violet samples, already offset along `direction`, gain an extra radial kick proportional to field angle squared and Chromatic Amount. Green stays the reference.
FORBID: a new spring, a new dispersion law, shockwaves beyond the click lens already here, replacing the five-band binning
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: crt-clear-zone
IDENTITY (one sentence): a barrel-distorted CRT around a circular clear window at the cursor — slot mask, scanlines, beam, misconvergence, halation, phosphor, degauss.
KEEP VERBATIM: Distortion / Aberration / Clear Radius / Scanlines; barrel; slot mask; corner misconvergence; beam raster and phosphor from C; halation; degauss wobble and purity blotches; clear-zone mix back to the clean photo.
MECHANISM INTERROGATION:
  tactic 2: a CRT draws two fields and the horizontal oscillator takes a moment to lock at the start of each line.
  tactic 5: name the artifact — interlace twitter, H-sync hook. Mask, beam, and degauss are already here.
  tactic 6: C is the phosphor image. Do not store a sync latch in it.
ADD:
  1. Field interlace (§12.2B) — odd lines sample a scanline late, scaled by the Scanlines slider, under the mask that stays put.
  2. H-sync recovery — the picture bows at the left of each line and settles across the width. Amount rides Aberration, the gun-error slider.
FORBID: a new spring, chroma-delay as a VHS look, another purity model, replacing the slot mask
A PACKING: ACES display RGBA (unchanged; C is that phosphor image)
```

```
SHADER: pixel-storm
IDENTITY (one sentence): pixels blown radially off a spring-followed cursor, with chaos spin, click cells, and a trail.
KEEP VERBATIM: Storm Strength / Chaos / Trail Length / Radius; spring in extraBuffer[133..138]; radial wind, chaos rotation, sector voices, click cells, suck-while-held; luma-weighted debris; exact-C sample along the wind; ACES display.
MECHANISM INTERROGATION:
  tactic 5: a pixel storm is chunks, and the eye of a storm has a tangential jet at the wall. The wind is a smooth UV slide.
  tactic 4: Chaos is one angle. The spatial version that still matches the name is a per-block grid.
  tactic 6: C is advected color at the wind source. Keep that load; quantize the same coordinate.
ADD:
  1. Pixel blocks — while the wind is up, the sample cell snaps to a grid whose size follows Chaos, so debris is chunks.
  2. Eye-wall jet — a tangential ring at about 0.72 of Radius, scaled by Storm Strength, added onto the radial wind before the suck reversal.
FORBID: a second spring, an IQ palette, a new click system, replacing the radial wind
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: gen-temporal-motion-smear
IDENTITY (one sentence): frame-difference motion painted as a directional smear with a decaying light trail.
KEEP VERBATIM: Trail Persistence / Motion Sensitivity / Smear Directionality / Color Intensity; luma difference times a neighbor gradient; warm-fast / cool-slow tint; max-blend trail; hue shift from trail age; directionality scales the blur length (0 = no directional smear).
MECHANISM INTERROGATION:
  tactic 1: the blur is a flat box of 8 taps stepping only forward. A shutter is bright at the head and fades down the tail.
  tactic 6: C is the trail color, read at the same pixel, so the ghost blooms in place. The motion vector is already computed.
  tactic 2: the history loads use a filtering sampler on rgba32float. Exact loads are the floor; the idea is where they are taken.
ADD:
  1. Shutter tent — the same eight taps along the same motion direction, weighted so the head is full and the tail thins.
  2. Upstream trail — the decayed ghost is loaded from C one motion-step upstream, and that step is zero when Directionality is zero.
FORBID: a spring, a pointer the effect never had, a new palette, replacing the difference detector
A PACKING: ACES display RGBA (C is that trail). Motion taps are exact textureLoad.
```

```
SHADER: infinite-fractal-feedback-hdr
IDENTITY (one sentence): a six-fold polar zoom of the photo around a sprung focal point, mixed with feedback, plus a hue ring and click fronts.
KEEP VERBATIM: Zoom Rate / Spiral Tightness / Color Shift / Feedback Strength; spring focal point in extraBuffer[133..138]; polar fract and 6-fold fold; hue ring; click fronts; the source still sampled at sampleUV.
MECHANISM INTERROGATION:
  tactic 6: C is read at this pixel, so feedback is a local fade. sampleUV is already the preimage the zoom should pull history through.
  tactic 8: the bloom is a luma multiply on the same pixel. Light that blooms has to leave the core.
  tactic 3: lum is already computed and then only used as a threshold and as alpha.
ADD:
  1. Fractal preimage feedback — mix Feedback Strength from C at sampleUV, not from C at this pixel, so the previous frame is pulled into the kaleidoscope.
  2. Energy-conserving bloom (§12.2F) — four taps around sampleUV spread highlight energy, and the core is dimmed by the same luma gate.
FORBID: a second spring, an IQ palette, a new symmetry count, replacing the polar map
A PACKING: clamped linear feedback RGB in A (C read as that color); ACES on writeTexture only. Was ACES stored in A and mixed back into linear.
```

```
SHADER: gen-hyperbolic-tessellation
IDENTITY (one sentence): a Poincaré disk of recursive tiles, {p,5} geodesics, horocycles, and an Escher two-coloring.
KEEP VERBATIM: Tile Symmetry / Depth Color / Rotation Speed / Boundary Glow; Möbius translation; the 8-step kaleidoscope fold; ideal vertices; origin horocycles; circle-inversion geodesics and Jacobian width; inversion-parity coloring; click glow; raw HDR in A.
MECHANISM INTERROGATION:
  tactic 2: the Poincaré metric dims area as (1−r²), and a second horocycle family crowds an ideal point on the boundary rather than the origin.
  tactic 3: originalRadius is already the disk radius. The fill is lit flat.
  tactic 6: C is raw HDR color. The 0.26 mix stays. Do not ACES A.
ADD:
  1. Poincaré area darkening — the tile fill, not the edges or the boundary glow, is multiplied by a softened (1−r²).
  2. Ideal-point horocycles — circles crowded toward a boundary point that drifts with Rotation Speed, gated by Boundary Glow, drawn outside the inner disk.
FORBID: mapping the photo into the tiles, a new palette family, a spring, replacing the {p,5} inversion
A PACKING: raw HDR tessellation RGB + coverage alpha (unchanged); ACES on display only
```

```
SHADER: gen-klein-bottle-walk
IDENTITY (one sentence): a lit walk on the parametric tube, with an orientation-reversing seam, chart lines, a pinch specular, and a footprint trail.
KEEP VERBATIM: Walk Speed / Texture Density / Light Intensity / Color Shift; kleinBottlePoint; seam flip of normal and texture u; chart lines from Texture Density; derivative-area pinch; footprint from C; diffuse and specular.
MECHANISM INTERROGATION:
  tactic 2: crossing the seam should carry the hue to the other sheet, and the surface already has a second fundamental form the pinch does not use.
  tactic 3: du, dv, and the normal are computed for lighting. Three more surface points give Gaussian curvature.
  tactic 4: Color Shift is a global saturation. The sheet-dependent version still matches the name.
ADD:
  1. Sheet hue transport — the flipped sheet offsets hue by half a turn times Color Shift. Saturation stays on that slider.
  2. Gaussian curvature tint — saddle cools and elliptic regions warm, mixed a little into the lit color. The pinch specular stays.
FORBID: replacing kleinBottlePoint, a raymarched bottle, a spring, a new palette
A PACKING: ACES display RGBA (unchanged; C is the footprint color)
```

```
SHADER: solarize-warp
IDENTITY (one sentence): a Sabattier invert with a Mackie line, twisted around a sprung pointer, with a domain-warp conveyor and click threshold fronts.
KEEP VERBATIM: Twist Strength / Solarize Threshold / Effect Radius / Effect Intensity; sabattier invert of highlights and the Mackie line; spring; conveyor; click fronts; split-tone tints; the flat C mix outside the brush.
MECHANISM INTERROGATION:
  tactic 2: color paper solarizes per emulsion, so the three layers cross the threshold at different exposures. The second exposure lands where the developing image is most sensitive — on the contour.
  tactic 3: luma-versus-threshold is already the Mackie distance.
  tactic 6: C is display color. Keep the existing outside-the-brush mix; add the contour term beside it.
ADD:
  1. Per-channel Sabattier — red crosses a little below the threshold, blue a little above, scaled by Effect Intensity. At zero intensity the invert masks match.
  2. Re-exposure along the Mackie line — a partial invert of last frame's color, weighted by proximity to the threshold.
FORBID: a new spring, a new warp, grain cadence changes, replacing the luma Mackie line
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: spec-importance-sampled-bokeh
IDENTITY (one sentence): a golden-angle bokeh whose taps are weighted by highlight brightness, with a sprung focus pull and depth-of-field.
KEEP VERBATIM: Bokeh Radius / Highlight Shape / Brightness Boost / Chromatic Aberration; 48-tap golden spiral; importance pow(luma); per-tap chroma split; focus spring in extraBuffer[133..138]; depth defocus; click sharp rings; center sharp blend.
MECHANISM INTERROGATION:
  tactic 2: off-axis blur is a cat's eye, and a point highlight diffracts as an Airy disc. The kernel is a round disk and the weight is only a luma power.
  tactic 3: each tap already has luma and a radius fraction r/radius.
  tactic 6: C is unread. Do not start a history blend.
ADD:
  1. Cat's eye — the existing offset is squeezed along the vector from the frame centre, more as Bokeh Radius grows. The centre of the frame stays round.
  2. Airy disc (§12.2F) — bright taps are weighted by an Airy profile of r/radius. Dim taps keep the flat disk so the background stays smooth. Highlight Shape stays the luma power.
FORBID: a new spring, a blade-count rewire of Highlight Shape, a second chroma model, reading C
A PACKING: linear bokeh RGB + importance alpha in A (C unread); ACES on writeTexture only
```

```
SHADER: gravity-lens
IDENTITY (one sentence): a point-mass gravitational lens on the photo — Einstein ring, counter-image, photon ring, redshift, accretion arc, dark-matter subhalos.
KEEP VERBATIM: Mass / Horizon / Accretion / Aberration numeric roles as the shader uses them (mass, ring width, chromatic split, dark-matter); lens equation; inner counter-image dim; blackbody redshift; 3-lobe accretion arc; photon ring; subhalo caustics; shadow; raw lens fields in A.
MECHANISM INTERROGATION:
  tactic 2: surface brightness is magnified by the inverse Jacobian, and an accretion disk is brighter on the approaching limb.
  tactic 3: b and einsteinR already determine that Jacobian. phi is already the disk angle.
  tactic 8: the ring glow is added light. Magnification should scale the photo that was sampled, not replace the glow.
ADD:
  1. Point-mass magnification — color is scaled by a clamped 1/|1−(θE/b)⁴| outside the hole, and the existing inner dim is kept inside θE.
  2. Doppler limb — the existing 3-lobe arc is multiplied by a slow one-sided brightening so the approaching side leads.
FORBID: a spring, a new lens model, replacing the counter-image or the photon ring, retitling saved params
A PACKING: raw lens fields (impact b, potential, ringGlow, |deflection|) — no C reader. Unchanged.
```
