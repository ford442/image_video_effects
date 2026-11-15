# Idea Cards — Grok (trace-grade ten, 2026-11-15)

Written before the WGSL edits. Ten shaders at 80–106 lines. Each card adds **two** ideas in the existing main path. Saved `params` stay byte-exact. No shared spring, ripple stamp, or new IQ palette.

This is a second pass. Earlier ideas stay. The new pair is what this batch adds.

Formula rule: a §12.2 row is newly applied on at most two files here. In this batch each row below is on one file.

- Density-weighted grain and halation (§12.2A) are `analog-film-degrade` only. This is the worked second pass in the batch contract.
- Cauchy and Fresnel–Schlick (§12.2F) are `chroma-depth-tunnel` only.
- Dropout tail (§12.2B) is `glitch-ripple-drag` only.

Prelude migration on `rgb-iso-lines`, `mirror-drag`, and `green-tracer` is infrastructure (`migrate_to_prelude.py`). It is not an idea and does not by itself bump `Upgraded:`.

```
SHADER: hex-circuit
IDENTITY (one sentence): a hex-grid circuit traced over the photo, lighting where the picture has an edge, with via pads at the cell centers and a mouse pulse running out from the pointer.
KEEP VERBATIM: axial hex cell (fractA/fractB), distToEdge / distToCenter, gridSize / glowStrength / pulseSpeed / edgeSens roles, mouse-distance pulse, via pad, exact-C edge persist in A.a, cold cyan-to-magenta pulse color
MECHANISM INTERROGATION:
  tactic 2: a real trace follows the signal, and a trace that stays live heats from cyan copper toward orange
  tactic 3: lumaR and lumaU are already the image gradient and are collapsed into one scalar imgEdge
  tactic 6: C.a is the persisted edge; it already knows how long this pixel has been a trace
ADD:
  1. Edge-aligned trace — the hex wall lights when its normal faces the image gradient, and stays quiet when it merely crosses the edge
  2. Joule heating — high C.a persist shifts that live trace from the pulse color toward hot copper
FORBID on this file: a new spring, click shockwaves, an IQ palette, a second grid
A PACKING: ACES display RGBA. C.a is the edge persist (unchanged)
```

```
SHADER: rgb-iso-lines
IDENTITY (one sentence): per-channel contour lines of the photo, split by pointer parallax, with wavelength alpha.
KEEP VERBATIM: thickness / frequency / parallax / background-opacity roles, R sampled at +offset, G at uv, B at −offset, the fract iso test, wavelength alpha, the existing runners / ticks / click fronts / hsv slick
MECHANISM INTERROGATION:
  tactic 1: a topo sheet thickens every fifth contour; the current line is one width
  tactic 7: the contour has a downhill direction, and the green sample is the unshifted field
  tactic 6: C is mixed as color, but A stored line masks. That is a packing lie. A becomes the linear composite
ADD:
  1. Index contours — every fifth iso, per channel, is drawn at about 2.4× the line width
  2. Downslope ticks — short marks along the green-channel gradient, gated by the line mask
FORBID on this file: a new palette, a spring, another ripple system
A PACKING: linear display RGBA in A (the composite). ACES on writeTexture only. C is that composite
```

```
SHADER: mirror-drag
IDENTITY (one sentence): a horizontal mirror of the photo, dragged away from the pointer, with a chromatic ghost, a decaying trail, and audio shatter into angular shards.
KEEP VERBATIM: drag / mirror / trailDecay / shatter roles, mix(uv.x, 1−uv.x, mirror), chromatic R/B offsets, history trail mix, shard angle quantization, click fronts, the existing spectral shatter glow
MECHANISM INTERROGATION:
  tactic 2: a hinged mirror has a dark joint on the fold, and a glass shard is shaded across its face, not only at the crack
  tactic 3: shardAngle is computed and then used only to hash a runner
  tactic 6: C is the trail color. A stays linear trail RGB so the decay is not tonemapped twice
ADD:
  1. Hinge crease — the straight sample and the mirrored sample disagree, and that disagreement is drawn as a joint on the fold, scaled by Mirror Amount
  2. Facet shade — a slow light/dark across each existing shard, scaled by Shatter Amount
FORBID on this file: a new spring, a second spectral palette, replacing the mirror mix
A PACKING: linear trail RGBA in A. ACES on writeTexture only
```

```
SHADER: chroma-depth-tunnel
IDENTITY (one sentence): a pointer-centered tunnel that maps the photo onto angle and inverse radius, with chromatic split along the flight and a throat ring at the center-fog radius.
KEEP VERBATIM: speed / density / chroma / centerFade roles, tunnelBase (angle, inverseRadius, helix, flight), symmetric angular chroma, throat ring, ribs, runners, click shocks, the existing palette, history streak
MECHANISM INTERROGATION:
  tactic 2: glass dispersion is not symmetric — violet runs farther than red — and a tube wall brightens at grazing
  tactic 3: radius is already the view angle down the bore and is only a fog input
  tactic 6: C is color history along the flight. Leave that streak alone
ADD:
  1. Cauchy path split — the existing path-length chroma is scaled per channel so blue leads red (§12.2F)
  2. Wall Fresnel — a Schlick term on the bore angle lifts the outer wall (§12.2F)
FORBID on this file: a new palette, a spring, a second shockwave
A PACKING: ACES display RGBA (unchanged). C is color history
```

```
SHADER: gen-islamic-geometric-tiling
IDENTITY (one sentence): interlaced star-and-rosette tiles, with a girih dart, gold leaf at the vertices, ceramic glaze, and a strap that passes over and under.
KEEP VERBATIM: star point count, tile scale, line width, ornament depth, the star / interlace / dart / rosette loops, over-under crossing mask, gold glints, glaze, gilded click waves, raw HDR in A
MECHANISM INTERROGATION:
  tactic 2: ceramic tiles are separated by grout, and a woven strap is bright on the outer lip and dark on the inner lip
  tactic 3: the cell square is computed and then only used as a frame for the star
  tactic 6: C is raw HDR history. Do not ACES A
ADD:
  1. Grout joint — the pre-rotation cell edge is a dark joint, width following Line Width
  2. Strap bevel — the outside of the star stroke catches gold and the inside falls into shade
FORBID on this file: a new motif, a spring, replacing the star equation
A PACKING: raw HDR display RGBA (ACES on writeTexture only). Unchanged
```

```
SHADER: green-tracer
IDENTITY (one sentence): the photo pushed toward green, with a phosphor trail that lasts longer on edges and a glow on motion.
KEEP VERBATIM: trailLen / glowInt / greenTint / noiseAmt roles, trail fade from trailLen, edge gate, motion threshold, exact-C trail in A.rgb, ACES only on writeTexture
MECHANISM INTERROGATION:
  tactic 2: P43 phosphor strikes yellow-green and decays deep green, and a bright strike blooms into the neighbors
  tactic 3: motion and edgeGate are already the strike; they only scale one green glow
  tactic 6: C is the previous trail. Neighbor loads of that trail are the bloom, no new field
ADD:
  1. Phosphor strike color — fresh motion on an edge pushes the trail yellow-green; the rested trail is deeper green
  2. Phosphor bloom — four loads of the previous trail, green-weighted, added as a halo scaled by Glow Intensity
FORBID on this file: film halation (red), a spring, a night-vision scanline costume, ACES on the stored trail
A PACKING: trail RGB in A.rgb (not tonemapped). A.a is coverage. ACES on writeTexture only
```

```
SHADER: ascii-shockwave
IDENTITY (one sentence): the photo broken into glyph cells inside a radial shockwave from the pointer, with the character chosen from the cell luma.
KEEP VERBATIM: intensity / speed / scale / detail roles as the shader actually maps them (x drives ascii amount, y wave speed, z cell count, w dot size), dot / cross / box / fill ramp, held amount, click fronts, conveyor and packets, the 0.28 trail mix
MECHANISM INTERROGATION:
  tactic 1: a character ramp has a bar between the dot and the box; the cell luma is one center tap
  tactic 3: local.y and lum are already computed and only pick among three shapes
  tactic 6: C is the displayed trail. Store the pre-ACES composite so the mix is not tonemapped twice
ADD:
  1. Mid-ramp bar — a horizontal stroke in the mid-luma band, between the cross and the box
  2. Cell-average luma — four corner taps inside the cell join the center sample before the glyph is chosen
FORBID on this file: a new palette, a spring, rewiring the four sliders to the JSON display names
A PACKING: linear display RGBA in A. ACES on writeTexture only
```

```
SHADER: analog-film-degrade
IDENTITY (one sentence): the source photo as a worn projected print — grain, fade, scratches, dust, vignette.
KEEP VERBATIM: grain / fade / scratchFreq / vignette roles, per-channel grain seeds, gate-weave hairlines, dust, sepia and desat fade, 0.10·fade C print-through, vignette falloff
MECHANISM INTERROGATION:
  tactic 2: print grain is a function of density, and light through the emulsion bounces off the base into the red layer
  tactic 3: luma is already computed for the fade chain
  tactic 6: C stays the print-through mix. No new field
ADD:
  1. Density-weighted grain — σ(L)=k·sqrt(L(1−L)) multiplies the existing gR/gG/gB (§12.2A)
  2. Halation — four-tap clipped-highlight bloom, red-biased, core bleached toward luma, amount riding Fade (§12.2A)
FORBID on this file: springs, click fronts, an IQ palette, any new param, any change to the sepia mix constants
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: color-blindness
IDENTITY (one sentence): a severity mix from protanopia through deuteranopia to tritanopia, with an optional split against the original and a confusion hatch on the assist slider.
KEEP VERBATIM: the three matrices, type as a 0–2 mix, severity, split at the pointer x, seam, assist hatching amount, the "Unused" param name and range
MECHANISM INTERROGATION:
  tactic 2: a CVD simulation changes confusion, not exposure, and the hatch should run along that type's confusion axis
  tactic 3: the type mix t is already 0 at protan and 2 at tritan and is thrown away after the matrix blend
  tactic 6: C is not read. A stays display RGBA
ADD:
  1. Luminance restore — after the matrix mix, scale so the simulated luma matches the source luma
  2. Confusion-axis hatch — the existing hatch runs nearly horizontal for protan, diagonal for deutan, vertical for tritan
FORBID on this file: a spring, a palette, renaming the Unused slider, a second hatch
A PACKING: ACES display RGBA (unchanged). C is not read
```

```
SHADER: glitch-ripple-drag
IDENTITY (one sentence): a dragged ripple around a sprung pointer, with click fronts, a held time-strobe, and chroma that widens with pointer speed.
KEEP VERBATIM: drag / freq / persistence / glitch roles, extraBuffer[133..138] spring, direction quantization, held strobe time base, velocity-scaled chroma spread, click-front displacement, exact C loads
MECHANISM INTERROGATION:
  tactic 2: a glitch tear shifts a whole scanline by one offset, and the ripple leaves a dropout tail
  tactic 3: heldWave and mouseDist are the front; they end in a hard ring
  tactic 6: C is display history. Do not steal A.a (it gates valid history)
ADD:
  1. Scanline tear — while the ripple is up, the drag offset collapses to one horizontal shift per row
  2. Dropout tail — an exponential streak just off the existing ring (§12.2B)
FORBID on this file: a second spring, an IQ palette, storing a latch in A.a
A PACKING: ACES display RGBA (unchanged)
```
