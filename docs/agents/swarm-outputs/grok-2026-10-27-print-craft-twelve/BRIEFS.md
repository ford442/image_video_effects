# Idea Cards — Grok (`cursor/print-craft-twelve`, 2026-10-27)

Written before the idea edits. Twelve print and craft shaders. Each card adds **two** new ideas. Earlier ideas stay. Saved `params` stay byte-exact. No shared spring, ripple stamp, or IQ palette.

Formula rule: a §12.2 row is used on at most one file here.

`impasto-swirl` on main is an unrelated stipple body (Sobel dots, no swirl, sliders wired to dot size / edge / posterize / ink). The catalog entry and the last oil-paint version are a wet swirl smudge with drying and canvas tooth. This card puts that body back, then adds two ideas. The stipple body is not the effect.

Prelude migration on all twelve is infrastructure, done with `migrate_to_prelude.py`. It is not an idea.

```
SHADER: impasto-swirl
IDENTITY (one sentence): wet oil paint the pointer stirs into a swirl, then dries back toward the photo
KEEP VERBATIM: perpendicular swirl sample, brush mask, dry-back outside the brush, thickness in A.a, canvas tooth, thickness-driven saturation
ADD (2–4 native ideas):
  1. Knife ridge — the stored thickness already has a slope; shade the paint by that slope so thick strokes catch a ridge light
  2. Lip bead — paint piles where the brush mask is halfway, the lift line of a loaded knife
FORBID on this file: the stipple/dot body that was sitting in the file; a spring; audio the effect does not use
A PACKING: linear paint RGB + thickness in A.a (C is read as paint). ACES on the display write only
```

```
SHADER: paper-cutout
IDENTITY (one sentence): the photo cut into stacked paper sheets, lit from the pointer
KEEP VERBATIM: luma layers, height-weighted shadows, lit core and far rim, per-sheet jitter, click emboss, sprung light
ADD:
  1. Deckle — the lit core breaks up along the cut instead of a straight pixel
  2. Paper tooth — fibre darkens the sheet, more inside the cast shadow
FORBID on this file: a halftone dot, foil, a new solver
A PACKING: ACES display RGBA (C is not read)
```

```
SHADER: cmyk-halftone-interactive
IDENTITY (one sentence): four angled CMYK screens with a registration target and a press slur
KEEP VERBATIM: 15/75/0/45 screens, registration mark, feed slur, CMYK persistence in A
ADD:
  1. Midtone dot gain — ink spreads most around a 50% dot, scaled by Ink Darkness
  2. Ink trap — a hairline of black under the colour-dot rims so misregister does not flash the paper
FORBID on this file: a second Euclidean spot (that belongs to dynamic-halftone); a new palette
A PACKING: [C, M, Y, K] coverage with light persistence. ACES on the display write only
```

```
SHADER: foil-impression
IDENTITY (one sentence): hot foil that takes the photo where the pointer presses
KEEP VERBATIM: foil noise normal, image-relief normal, press mix, brushed streaks, crinkle at the press boundary
ADD:
  1. Brushed streak — the specular widens along the brush tangent the file already builds
  2. Foil skip — steep emboss slopes miss the die and show paper
FORBID on this file: thin-film as a new look (the spectral tint stays the small term it is)
A PACKING: ACES display RGBA. C is not read
```

```
SHADER: poly-art
IDENTITY (one sentence): a low-poly Voronoi of the photo that tightens near the pointer
KEEP VERBATIM: Voronoi seeds, mouse densify, flat facet shade, border from the second-nearest seed
ADD:
  1. Detail cells — busy photo detail uses smaller facets; flat colour stays coarse. Cell Size still scales the base
  2. Lit bevel — the existing crease catches a highlight on the side facing the light
FORBID on this file: a new fractal, an IQ palette
A PACKING: ACES display RGBA. C is not read
```

```
SHADER: cross-stitch
IDENTITY (one sentence): the photo stitched as Xs on Aida, unraveling under the pointer
KEEP VERBATIM: X from two diagonals, half-stitch in dark cells, satin sheen, mouse unravel, cloth grid
ADD:
  1. Knot — a full stitch is darker and thicker where the two diagonals cross
  2. Aida holes — the cell corners open where the needle passes
FORBID on this file: a knit loop (that is knitted-fabric)
A PACKING: ACES display RGBA. C is not read
```

```
SHADER: knitted-fabric
IDENTITY (one sentence): a wool knit the pointer pulls open, with ply twist and heather
KEEP VERBATIM: offset courses, strain-thinned yarn, two-ply, heather, click pluck, material masks in B
ADD:
  1. Purl rows — odd courses turn the back loop outward
  2. Lint — fibres stick out of the yarn into the gap
FORBID on this file: cross-stitch Xs, a new solver
A PACKING: ACES display RGBA in A. B keeps yarn / pull / shimmer / alpha. C is not read
```

```
SHADER: interactive-halftone-spin
IDENTITY (one sentence): CMYK screens that spin and arc-smear, leaving an ink after-image
KEEP VERBATIM: four screen angles, arc smear, CMYK stored in A, ghost from last frame's coverage
ADD:
  1. Rosette hole — where C, M and Y all print and K does not, the cluster center is paper
  2. Wet tack — new ink on last frame's ink prints darker
FORBID on this file: the registration target and slur from cmyk-halftone-interactive
A PACKING: [C, M, Y, K] coverage. ACES on the display write only
```

```
SHADER: dynamic-halftone
IDENTITY (one sentence): halftone dots that swell, pool, and rag under the pointer
KEEP VERBATIM: Euclidean round/diamond spot, 3×3 pooling, ragged rims, premultiplied coverage alpha
ADD:
  1. Pointer stretch — dots elongate toward the pointer; the plate angle still spins the spot
  2. Edge swell — the center dot grows where the photo changes beside it
FORBID on this file: CMYK plates, a rosette hole
A PACKING: ACES display RGBA, premultiplied by coverage. C is not read
```

```
SHADER: charcoal-rub
IDENTITY (one sentence): a stick of charcoal builds on the paper where the pointer rubs
KEEP VERBATIM: reveal state in A.r, laid-paper fibre, vine-dust halo, fade-back
ADD:
  1. Photo pigment — the charcoal takes the colour of the photograph under it
  2. Burnish — a heavy rub flattens the grain and opens the photograph in the stroke core
FORBID on this file: a scratch-off that deletes the charcoal deposit
A PACKING: raw reveal mask in A.r. ACES on the display write only
```

```
SHADER: sequin-flip
IDENTITY (one sentence): disks that flip under the pointer onto a metal back
KEEP VERBATIM: hex grid, flip angle, GGX, gold/silver mix, click fronts
ADD:
  1. Stitch hole — a punch near the rim shows the cloth
  2. Edge-on glint — a sequin turned sideways is a bright slit
FORBID on this file: foil crinkle, a halftone
A PACKING: ACES display RGBA, read back as a short history. Unchanged
```

```
SHADER: stipple-engraving
IDENTITY (one sentence): tone stipple plus directional hatch, burnished by the pointer
KEEP VERBATIM: low-discrepancy threshold, tangent hatch, paper fibre, burnish, held pool, click rings
ADD:
  1. Elliptical stipple — dots stretch along the hatch tangent the file already has
  2. Burr — a pale shoulder sits one side of the engraved line
FORBID on this file: a CMYK screen, charcoal state
A PACKING: ACES display RGBA, the history the file already reads. Unchanged
```
