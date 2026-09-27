# Artistic surface eight — Idea Cards (written before WGSL)

Batch: 2026-09-21, sixth batch today. Theme: ink, paper and surface materials in `artistic/`.
Selection: no `Ideas:` line, no `A.`–`D.` idea blocks, not touched by the uncommitted optical-eight / sim-six
files in the tree. Every file was read in full first. `plasmaBuffer` is still never uploaded by the renderer
(see memory), so every idea below must read without audio.

Claimed IDs: graphic-novel (graphic_novel.wgsl), rorschach-inkblot, polka-dot-reveal, frosty-window,
melting-oil, porcelain-fracture-glow, static-reveal, luminance-wind.

Rejected after reading: anisotropic-kuwahara (JSON `url` points at the -tensor multipass graph; the
standalone file isn't what runs), ink_dispersion_alpha (naga-decompiled halftone whose JSON describes a
fluid sim and whose four sliders mean different things; needs a rescue, not ideas), circular-pixelate
(already dense; nothing native left that stays "pixelate"), spirograph-reveal (the pattern is a
polar moiré field, not a spirograph, so ideas would be a rewrite).

---

```
SHADER: graphic-novel
IDENTITY: posterised photo printed as a comic page: rotated CMK dot screens, adaptive ink contours, paper fibre
KEEP VERBATIM: screenDot() screens + angles, adaptive contour threshold, registration offset, poster levels,
  paper fibres, held/click ink, 4 params, A = ACES display RGBA
ADD:
  1. Spot blacks — the deepest poster tones fill solid ink the way a comic inker "spots blacks"
     instead of leaving them as screened dots
  2. Tonal cross-hatching — pen strokes along the contour tangent in the shadows; a second set at
     ~60° once the tone is darker (pen-and-ink shading, not a new screen)
  3. Line weight — contours grow thicker on the shadow side of an edge (inkers' light-source line weight)
FORBID: springs, IQ palettes, new motion; do not replace the screens
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: rorschach-inkblot
IDENTITY: an ink blot mirrored across a vertical fold, advected by curl noise on paper
KEEP VERBATIM: mirroredUV fold, curl advection + held vortex + click blooms, threshold/softness ink key,
  history ink persistence, invert mode, 4 params
ADD:
  1. Fold crease — ink pools in the crease, and the paper shows a fold highlight/shadow
  2. Press-off transfer — the half across the fold is a print of the wet half: ink-starved stipple voids
     and a slightly lighter film, so the blot isn't mathematically symmetric
  3. Capillary feathering — the blot edge wicks along paper fibres in hairline tendrils
FORBID: Bousseau edge darkening (used by sim-ink-diffusion earlier today), springs
A PACKING: ACES display RGBA with ink alpha (unchanged). C is only read through mirroredUV (left of the
  axis), so the transfer voids on the right half never feed back
```

```
SHADER: polka-dot-reveal
IDENTITY: photo turned into polka-dot halftone whose dots get finer around the cursor
KEEP VERBATIM: density reveal by distance to smoothed mouse, luma-driven radius, alpha modes, trails,
  chroma offset, A state packing (R bass env, GB smoothed mouse, A alpha), 4 params
ADD:
  1. Chain-dot merge — above ~50% coverage the dot metric morphs from round to diamond so dots join
     their neighbours and the highlights read as holes (real halftone dot gain)
  2. Drag-stretched dots — near the cursor, dots elongate along the direction the mouse is moving
FLOOR FIX (not an idea): the "per-cell hash jitter" hashed per PIXEL (uv*131), so every pixel near a
  cell border picked a random cell — ragged, noisy dots. Jitter is now hashed from the cell id, as documented
FORBID: CMYK screens (that's graphic-novel), springs, click rings
A PACKING: unchanged state packing
```

```
SHADER: frosty-window
IDENTITY: frost crystals (voronoi facets + six-fold dendrites) on a window, melted by the cursor
KEEP VERBATIM: voro() facets, dend() branches, fbm warp, heat melt at pointer with Laplacian smoothing,
  blur/refract/SSS/caustic/sparkle look, 4 params
ADD:
  1. Frame nucleation and creeping front — frost starts at the cold window frame and grows inward from
     frosted neighbours. This also fixes the file being dead: C starts at zero, so the `frost < 0.005`
     early return fired forever and frost never appeared
  2. Meltwater runnels — frost melted by the cursor becomes water in A.g that runs down the glass,
     shows as clear lensing streaks, and holds off refreezing where it's wet
FLOOR: exact textureLoad for C (was textureSampleLevel on rgba32float)
FORBID: breath/fog overlays, springs, ripple rings
A PACKING: R = frost, G = meltwater (was a crystal diagnostic nobody read), B = caustic, A = alpha
```

```
SHADER: melting-oil
IDENTITY: the photo slides along the gradient of its own last frame like thick oil, with a PHI hue sheen
KEEP VERBATIM: Sobel of history R, mouse bend, turbulence, click stirs, advection step, PHI hue math,
  FFT band shimmer, alpha formula, 4 params
ADD:
  1. Accumulated melt — the advected sample now pulls from the exact C history as well as the source,
     so the displacement compounds into flowing streams instead of a fixed 1-px shift. Viscosity sets
     how much the oil holds
  2. Gravity sag — flow gets a downward bias weighted by luma, so bright paint drips and drips thicken
     at their heads
FORBID: new springs (the existing extraBuffer spring is dead because the region is re-uploaded every
  frame; left as is), new palettes
A PACKING: A = pre-sheen melted colour + alpha (the hue sheen is applied to writeTexture only, so it
  doesn't compound through feedback)
```

```
SHADER: porcelain-fracture-glow
IDENTITY: glossy porcelain over the photo, cracked along image edges with glowing kintsugi veins
KEEP VERBATIM: edge + fbm crack network, held mouse crack, click impact stars, vein colour, patina,
  hue-preserving ceiling, 4 params, A field packing (crack, leak, lightTemp, alpha)
ADD:
  1. Crack memory → gold seam — held and click cracks now persist through exact C.r and slowly turn
     from a dark open gap into a gold kintsugi fill instead of vanishing after release
  2. Stained crazing — a fine craquelure network in the glaze, density set by Patina Age, with
     tea-stain darkening in the crazing lines (how old porcelain actually ages)
FORBID: new springs, ACES swap (the file documents its hue-preserving ceiling)
A PACKING: unchanged field packing; R is now read back as crack memory
```

```
SHADER: static-reveal
IDENTITY: TV snow with VCR tracking noise that a brush wipes away to reveal the picture
KEEP VERBATIM: brush mask with regrowth, tracking bands, h-hold, snow, chroma noise, acquisition flash,
  A = display colour + mask in alpha, 4 params
ADD:
  1. Vertical-hold roll — while a region is only partly locked, the picture rolls vertically with a dark
     blanking bar passing through it (the VBI)
  2. Multipath ghost — partly revealed regions show a faint delayed echo of the image offset to the right,
     like antenna ghosting
FLOOR FIX: revealThreshold read zoom_config.y (mouse X), so how much the brush revealed depended on where
  the cursor sat horizontally. Now a constant 0.3. C loaded exactly
FORBID: springs, click rings
A PACKING: unchanged
```

```
SHADER: luminance-wind
IDENTITY: bright parts of the image blow away as luminous trails in curl-noise wind
KEEP VERBATIM: exact history advection, luma gate, curl layers, held-pointer direction, click gusts,
  raw HDR in A, 4 params
ADD:
  1. Lee-side shelter — pixels downwind of a nearer object (depth upwind > depth here) sit in its wind
     shadow and barely move, so foreground silhouettes carve calm pockets into the trails
  2. Cat's-paw gusts — bands of stronger wind travel along the wind direction, so trail length pulses in
     waves instead of being uniform
FORBID: springs, palettes
A PACKING: unchanged raw HDR + alpha
```

---

## Card corrections made during implementation (logged, not silent)

- graphic-novel #2: tangent-following hatch was dropped before shipping. `dot(pixel, n)` with a
  per-pixel direction n makes the stroke phase jump wherever the gradient turns (pixel coords are
  ~1000, so a small angle change shifts the phase by many strokes), which reads as noise. Shipped
  as fixed 45° strokes plus a crossing set at 130°, pen-pressure wobble along each stroke.
- polka-dot-reveal #1: dots here are the *bright* image (radius grows with luma), so the merge
  happens in the highlights, and the dark gaps between merged dots become the holes. Reworded.
- melting-oil #2: "drips thicken at their heads" dropped. The sag is a luma-weighted downward
  bias only.
