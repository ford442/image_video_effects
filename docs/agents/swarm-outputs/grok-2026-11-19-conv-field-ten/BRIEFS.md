# Idea Cards — Grok (conv / field ten, 2026-11-19)

Written before the WGSL edits. Ten shaders the user listed by size. Each card adds **two** ideas in the existing main path. Saved `params` stay byte-exact. No shared spring, ripple stamp, or new palette.

Every file except `multi-turing` and `iso-hills` already carries an earlier idea pass. This pass deepens that mechanism. `multi-turing` keeps the rescued Gray-Scott kernel and only changes the display. `iso-hills` still pastes the binding header; migrating it to `#include "_prelude.wgsl"` is infrastructure and is not an idea.

Formula rule: a §12.2 row is newly applied on at most one file here.

- Density-weighted grain (§12.2A) is `film-gate-weave` only.
- No other §12.2 row is newly applied. The other ideas are the shader's own operator (patch window, structuring element, notch kernel, Lloyd site, grid slice, spiral arc, Turing fields, contour index).

```
SHADER: conv-non-local-means
IDENTITY: non-local means — a search window of patches, luma-weighted SSD, weights biased along the gradient, mouse tightening h, ripples widening it.
KEEP VERBATIM: patch radius / search radius / filter strength (h) / overdrive; luma-vs-chroma SSD; tangent bias on the search; self-weight 1; overdrive mix back to the centre; focus zone and ripple echo on h.
MECHANISM INTERROGATION:
  tactic 1: the patch SSD treats every tap equally. Buades windows the patch so the centre texel dominates.
  tactic 2: a neighbour whose own centre differs a lot is not a match, even before the patch vote.
  tactic 3: neighbour luma is already loaded for the blend and then ignored as a gate.
  tactic 6: C is display colour. The temporal mix stays as it is.
ADD:
  1. Gaussian patch window — centre tap weight 1, corners fall off. Same SSD, same h.
  2. Centre-luma preselection — exp of (neighbour luma − centre luma) against h, multiplied into the existing weight.
FORBID: a new search motif, a spring, another palette
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: film-gate-weave
IDENTITY: a 35mm gate — vertical weave at 24 fps, frame-line bars, wandering scratches in C.g, cue dots, dust, hair, splice, flicker, lens-breathe chroma.
KEEP VERBATIM: weave / dust / scratches / flicker slider roles; frame-line strip; scratch field in C.g; cue-dot cycle; splice and click flash; A packing (rgb.r, scratch, 0, alpha). The extraBuffer[133..138] spring stays the HEAD no-op it already is.
MECHANISM INTERROGATION:
  tactic 2: grain on a print follows density. The dye-cloud grain is flat.
  tactic 5: a registration pin also kicks the gate sideways, once per frame, not per scanline.
  tactic 6: C.g is the scratch. Do not repack it.
ADD:
  1. Density-weighted grain (§12.2A) — the existing dye-cloud grain, amplitude × sqrt(L(1−L)).
  2. Registration-pin weave — one horizontal offset per 24 fps frame, scaled by the weave slider, added to the sample x.
FORBID: halation (that pair already shipped on analog-film-degrade), a new spring, an IQ palette
A PACKING: (rgb.r, scratch, 0, alpha) — C.g is the scratch field (unchanged)
```

```
SHADER: conv-morphological-erosion-dilation
IDENTITY: per-channel erosion and dilation, Beucher gradient, top-hat and black-hat, a disk SE that elongates toward the pointer, a ridge skeleton on that axis.
KEEP VERBATIM: kernel radius / erosion-dilation blend / gradient boost / mouse influence; per-channel min and max (the colour of the winning texel, not a luma proxy); top-hat, black-hat, skeleton darken; mouse rotation of the SE.
MECHANISM INTERROGATION:
  tactic 1: the SE is a flat disk. A parabolic SE is the same support with a quadratic penalty, so far texels have to be darker (or brighter) to win.
  tactic 3: which offset won the min and the max is thrown away. That pair is the contact axis of the element.
  tactic 6: C is display colour. The temporal mix stays.
ADD:
  1. Parabolic structuring element — compare sample ± k·r², store the unpenalized winning colour. Radius and disk support unchanged.
  2. Contact relief — the dilation contact minus the erosion contact shades the existing gradient (light side / dark side). Flat texels stay put.
FORBID: a second morphology (opening/closing pass), a spring, a new palette
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: conv-frequency-domain-notch
IDENTITY: a bank of cosine kernels that notch or boost spatial frequencies, oriented toward the pointer, with the cut applied as a residual mix.
KEEP VERBATIM: band count / bandwidth / boost-cut / mouse frequency; per-band cosine kernel and gaussian envelope; notch response; residual cut mix; the existing response palette.
MECHANISM INTERROGATION:
  tactic 1: a single cosine leaves the first harmonic in the passband. A notch kernel also carries a half-amplitude double frequency.
  tactic 2: the rectangular support rings. A Hann window on the same radius is the window a spectrum analyser puts on that kernel.
  tactic 3: kernel weight is already the cosine. No new band loop.
  tactic 6: C is display colour. The temporal mix stays.
ADD:
  1. First-harmonic cosine — 0.4 × cos(2·ω) added inside the existing kernel.
  2. Hann window — the kernel support tapers to the search radius so the notch rings less.
FORBID: a second palette, a DFT, a spring
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: conv-stochastic-stipple
IDENTITY: blue-noise stipple — cells sized by the cell slider, dots where the neighbourhood is bright, paper ground, ellipses stretched along the gradient.
KEEP VERBATIM: cell size / threshold / saturation / mouse resolution; blue-noise threshold; luminance density (bright → dot); paper ground; gradient ellipse; local-mean colour.
MECHANISM INTERROGATION:
  tactic 1: the site is a hash in the cell. One Lloyd step moves it toward the bright centroid. That is stippling.
  tactic 2: a nibbed dot is darker at the rim than in the core.
  tactic 3: cell luma is already the density. The four corner samples are the centroid the hash threw away.
  tactic 6: C is display colour. The short temporal mix stays.
ADD:
  1. One Lloyd step — mix the hash site 70% of the way toward the luma-weighted centroid of the cell's four corners.
  2. Nib rim — inside the existing ellipse, the rim darkens and the core stays the saturated colour.
FORBID: inverting the stipple (dots stay on the lights), a new palette, a spring
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: conv-bilateral-grid-splat
IDENTITY: a bilateral gather with a luma-bin splat, an adjacent-bin mix, a depth range weight, and a pointer detail zone.
KEEP VERBATIM: spatial sigma / intensity sigma / grid resolution / mouse detail; spatial × intensity × depth weights; joint depth range; the mouse zone tightening both sigmas.
MECHANISM INTERROGATION:
  tactic 1: the adjacent bin is mixed at a constant 0.35. A slice reads the two bins around the centre luma with weights (1−frac, frac).
  tactic 3: centre − splat is the detail the grid is built to separate, and it is thrown away.
  tactic 6: C is display colour. The temporal mix stays.
ADD:
  1. Trilinear centre slice — a sample counts only in the centre's bin and the next bin, weighted by the fractional bin position. Replaces the constant 0.35 mix.
  2. Base-detail reconstruction — add back (centre − splat) in proportion to how coarse the luma bins are. Fine grids add less.
FORBID: a second joint-bilateral (depth is already in), a chroma range (that one is on bilateral-dream), a spring
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: multi-turing
IDENTITY: two-scale Gray-Scott (McCabe), Sims Laplacian, scale 1 at 1 px and scale 2 at 2 px, luminance-weighted spot seeds, kill centred on the pattern band.
KEEP VERBATIM: DA, DB, DT, Sims weights, feed/kill maps, seed spots, cross-scale b coupling, mouse and ripple seeding. The solver is not retuned.
MECHANISM INTERROGATION:
  tactic 2: spots eat substrate a before b rises. That ring is already in the state and is not drawn.
  tactic 3: |b1 − b2| and its pixel gradient are the place the two scales meet.
  tactic 6: A is (a1, b1, a2, b2) and C is that state. Display is a separate write. Do not ACES A.
ADD:
  1. Substrate depletion halo — darken the display where scale-1 a has fallen and b has not yet spotted.
  2. Cross-scale membrane — a pale line where |b1−b2| changes across a pixel.
FORBID: any change to feed, kill, diffusion, or dt; writing display colour into A; a new palette function
A PACKING: raw sim (a1, b1, a2, b2). ACES on the display write only.
```

```
SHADER: conv-bilateral-dream
IDENTITY: a bilateral dream — spatial gaussian times a luma-and-depth range weight, then an optional hue shift and a little temporal hold.
KEEP VERBATIM: spatial sigma / colour sigma / hue shift / mouse influence; joint depth inside the range; luma range; hue slider still the only hue amount (zero means no shift); ripple tightening of sigma.
MECHANISM INTERROGATION:
  tactic 1: the range is luma + depth. Two colours of the same luma still share a weight. Chroma distance belongs in that same range.
  tactic 6: the temporal mix is a flat 0.08 everywhere. A dream holds in the smooth regions and lets edges go.
  tactic 3: |centre − result| is already the edge the chromatic fringe uses.
ADD:
  1. Chroma-aware range — length of the chroma residual added to the existing range distance.
  2. Flat-region hold — the existing C mix is stronger where the bilateral barely moved the texel, weaker on the edge.
FORBID: a grid slice (that one is on bilateral-grid-splat), a hue shift at slider 0, a spring
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: conv-spiral-blur
IDENTITY: a spiral blur — samples along arms that mix Archimedean and log radius, spaced by the golden ratio, centred on the pointer.
KEEP VERBATIM: tightness / arm count / sample count / mouse centre; the Archimedean/log mix; golden arm offset; exp falloff along the arm; the existing golden tint.
MECHANISM INTERROGATION:
  tactic 1: each station is a point. A spiral pen has a width perpendicular to the tangent.
  tactic 2: arc length on a spiral grows with radius, so the outer arm should carry less exposure than the tight centre. The exp falloff does not know the radius.
  tactic 6: C is display colour. The temporal mix stays.
ADD:
  1. Finite arm width — average the station with a sample one pen-width along the tangent normal.
  2. Arc-length exposure — divide the existing arm weight by the arc element r·dθ.
FORBID: a second spiral family, a new palette, a spring
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: iso-hills
IDENTITY: a topographic relief — fbm plus image luma, stepped contours, valley/meadow/rock/snow, hachures, a sun, haze, pointer and ripple carving.
KEEP VERBATIM: contour steps / height scale / smoothness / haze; the elevation palette; the existing sine hachure; analytic normal; hydraulic erosion and river carve; A packing (smoothHeight, contour, shade, alpha).
MECHANISM INTERROGATION:
  tactic 2: every fifth contour on a map is an index line, drawn heavier.
  tactic 7: the hachure is a sine across the line. The downhill direction is already the normal, and real hachures run that way.
  tactic 6: C is not read. A stays the raw relief tuple. Do not ACES it.
ADD:
  1. Index contours — every 5th level uses a wider line.
  2. Fall-line ticks — short strokes along the downhill vector, added on the index contours beside the existing sine hachure.
FORBID: a new terrain primitive, a spring, a new palette
A PACKING: raw relief (smoothHeight, contour, shade, alpha). ACES on the display write only. C is not read.
```
