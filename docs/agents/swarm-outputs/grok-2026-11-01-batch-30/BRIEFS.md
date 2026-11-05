# Idea Cards — Grok (`cursor/batch-30`, Cursor(2), 2026-11-01)

Written before the idea edits. Twelve physical-material shaders (paper, plastic, pins, bubbles, folds, gold repair, blinds, tiles, emboss, texture analysis, zipper). Each card adds **two** new ideas. Earlier ideas stay. Saved `params` stay byte-exact. No shared spring, ripple stamp, or IQ palette.

Formula rule: a §12.2 row is used on at most one file here. Only `texture` takes a row (structure tensor and anti-halo, both photographic, both on the taps this file already fetches).

`kinetic-tiles` is `public/shaders/kinetic_tiles.wgsl`.

Prelude migration on `paper-burn`, `bubble-wrap`, `venetian-blinds`, and `interactive-emboss` is infrastructure (`migrate_to_prelude.py`). It is not an idea and does not by itself bump `Upgraded:`.

```
SHADER: crumpled-paper
IDENTITY (one sentence): a photo printed on crumpled paper that the pointer irons flat
KEEP VERBATIM: fbm5 height and ridge, mouse smooth disk, ironing memory in C.a, crease-tangent fibre, crease specular, params Crumple Scale / Depth / Smooth Radius / Light Strength
MECHANISM INTERROGATION:
  tactic 2: a real crumple buckles the flat facets between creases, and a hot iron burnishes those facets glossy
  tactic 3: `ridge` and `smoothFactor` are already computed and then only gate height and fibre
  tactic 6: C.a is the ironed height; cockle lives in the same height so the iron flattens it too
ADD (2 native ideas):
  1. Facet cockle — a fine buckle added only where the ridge is weak, so panels pillow and creases stay sharp
  2. Calender sheen — the ironed disk broadens the specular, warms the paper, and presses the fibre flat
FORBID on this file: a burn front (that is paper-burn), a new spring, an IQ palette
A PACKING: display RGB + height in alpha (C.a is the ironed height). ACES on the display write only
```

```
SHADER: paper-burn
IDENTITY (one sentence): paper that chars and opens into holes along the fibre, lit by an ember line
KEEP VERBATIM: burn state in A.r, 8-neighbour fibrous diffusion, held-pointer and click ignition, ember / char / hole bands, params Burn Speed / Spread Speed / Char Width / Reset
MECHANISM INTERROGATION:
  tactic 2: paper browns before it ignites, and the burning edge curls off the page
  tactic 3: left/right/top/bottom burns are already loaded for the diffusion and then discarded as a gradient
  tactic 6: C.r is the burn field; the curl reads that gradient and does not change the packing
ADD:
  1. Scorch browning — just ahead of the ember the photo yellows and desaturates
  2. Char curl — the live edge samples the photo along the burn gradient, and the depth lifts there
FORBID on this file: facet cockle from crumpled-paper, a new solver, gold seams
A PACKING: raw burn in A.r (C.r is the burn). ACES on the display write only
```

```
SHADER: plastic-bricks
IDENTITY (one sentence): the photo rebuilt as staggered toy bricks with studs, tubes, and a knit line
KEEP VERBATIM: half-brick row offset, stud and mortar masks, underside tubes, injection knit, plastic BRDF, pointer deconstruct, params Density / Stud Size / Relief / Bevel
MECHANISM INTERROGATION:
  tactic 2: an injection stud has a gate pip, and the mold leaves a parting line down the shell
  tactic 3: `studDist` and `cell` already exist; the pip and the parting line are thresholds on them
  tactic 5: a mold technician names the gate mark and the flash line; neither is drawn yet
ADD:
  1. Stud pip — a small recess in the stud crown where the plastic was injected
  2. Parting line — a vertical flash seam on the shell, absent on the stud, catching the existing gloss
FORBID on this file: a knit loop that replaces the knit line, a new palette, grout from kinetic-tiles
A PACKING: ACES display RGBA (C is not read)
```

```
SHADER: pin-art-3d
IDENTITY (one sentence): a bed of pins pushed in by the photo and by the pointer, with shafts and neighbour shade
KEEP VERBATIM: luma height, pointer push, bass vibration, sphere-cap shade, neighbour occlusion, shaft under the cap, params Density / Pin Radius / Push Strength / Metallic
MECHANISM INTERROGATION:
  tactic 2: real pins stick at discrete heights, and the cap has a machined rim at the equator
  tactic 3: `height` is a continuous luma and is thrown away as a smooth field
  tactic 5: a pin-art board has friction steps and a cap rim; the hole grid is already implied by the shaft
ADD:
  1. Friction steps — height locks to seven levels so neighbouring pins sit on shelves
  2. Cap rim — the sphere's equator darkens where the cap was turned
FORBID on this file: a brick stud, a new spring, replacing the cap with a flat tile
A PACKING: ACES display RGBA (C.rgb is a short colour trail)
```

```
SHADER: bubble-wrap
IDENTITY (one sentence): hex bubbles the pointer pops, with a sympathetic pop from neighbours
KEEP VERBATIM: hex lattice, pop flag and pop time in A.rg, sympathetic 6-neighbour pop, collapse and jiggle, refraction, params Bubble Size / Pop Strength / Refraction / the fourth slider as highlight
MECHANISM INTERROGATION:
  tactic 2: the sheet between bubbles is a welded web, and a pop starts as a white membrane bursting
  tactic 3: `d` (radius in the cell) and `agePop` are computed and only flatten z
  tactic 6: A.rg stays the pop flag and time; the flash reads age and writes nothing new
ADD:
  1. Seal web — the plastic between bubbles darkens in a weld ring outside the dome
  2. Membrane flash — the first moments of a pop bleach the dome, then the existing collapse takes over
FORBID on this file: thin-film as the whole look, a new pop solver, pin caps
A PACKING: raw pop flag, pop time, neighbour count in A.rgb. ACES on the display write only
```

```
SHADER: interactive-origami
IDENTITY (one sentence): the photo folded into mountain and valley planes around the pointer
KEEP VERBATIM: three triWave creases, fold parity, wet-fold shadow, crease runners, click rings, params Fold Scale / Fold Depth / Light Intensity / Depth Influence
MECHANISM INTERROGATION:
  tactic 2: a scored sheet shows a hairline in the hinge, and the reverse of the paper is duller than the face
  tactic 3: `h0` and `foldParity` are computed for lighting and then not drawn as a score or a back
  tactic 7: parity already names which facet is the back of the sheet
ADD:
  1. Score line — a dark hairline where the fold crosses zero and the gradient is steep
  2. Reverse face — negative-parity facets are duller and cooler; the foil stays on the front
FORBID on this file: crumpled-paper fibre, a second fold family, gold repair
A PACKING: ACES display RGBA (C.rgb is a short colour trail)
```

```
SHADER: kintsugi-repair
IDENTITY (one sentence): the photo shattered into shards and mended with a raised gold seam
KEEP VERBATIM: Voronoi edge and F2 T-junction, gold width, shatter shift, sparkle, meniscus highlight, params Shard Size / Gold Width / Shatter Amount / Gold Sparkle
MECHANISM INTERROGATION:
  tactic 2: real kintsugi lays black urushi wider than the gold, and the glaze chips at the break
  tactic 3: `edgeDist` already measures the seam; the bed and the chip are wider bands on it
  tactic 5: a restorer names the urushi bed and the glaze lip; the meniscus is already the gold bead
ADD:
  1. Urushi bed — a dark lacquer shoulder wider than the gold, so the gold sits in a black line
  2. Glaze lip — a light chip just outside the gold and a short shadow beyond it
FORBID on this file: a second Voronoi (the F2 ridge stays), paper burn, an IQ palette
A PACKING: ACES display RGBA (C is not read)
```

```
SHADER: venetian-blinds
IDENTITY (one sentence): horizontal slats over the photo, opened by the pointer's Y and by bass
KEEP VERBATIM: slat count, openness, slat brightness, phase, mouse-Y openness, bass snap, mids glint, downward gap shadow
MECHANISM INTERROGATION:
  tactic 2: tilted slats show a shifted slice of the room, and the ladder tapes hang at the sides
  tactic 4: Base Openness is one scalar; the view through the gap should move with that tilt
  tactic 5: a window tech names the tilt view and the ladder tape; the slat cylinder is already there
ADD:
  1. Tilt view — the gap samples the photo shifted by how open the slat is
  2. Ladder tape — two vertical tapes, with a darker stitch where each tape crosses a slat
  3. Slat bounce — the gap just under a slat picks up a little of the slat colour
FORBID on this file: a spring, pin rows, a new palette
A PACKING: ACES display RGBA (C is not read). This file had no ACES; adding it is the floor under the ideas
```

```
SHADER: kinetic-tiles
IDENTITY (one sentence): square tiles that rotate and shrink in a wave under the pointer
KEEP VERBATIM: grid, spring cursor in extraBuffer[133..138], domino row delay, grout compression, rotation and scale, click fronts, bevel glint, params Grid Density / Mouse Radius / Rotation Amt / Tile Scale
MECHANISM INTERROGATION:
  tactic 2: a spinning ceramic tile shows a lit lip on the leading edge, and the joint is mortar rather than a dim photo
  tactic 3: `currentAngle` and the out-of-tile branch already exist
  tactic 7: the spin has a direction; the lip should face it
ADD:
  1. Leading lip — the tile edge that faces the spin lights, and the trailing edge darkens
  2. Mortar joint — the gap is sandy grout with the photo showing through, darker in the valley of the joint
FORBID on this file: a new spring, a second IQ palette (the existing glow stays), brick studs
A PACKING: linear pre-ACES trail RGB in A (C.rgb is that trail). ACES on the display write only
```

```
SHADER: interactive-emboss
IDENTITY (one sentence): a directional emboss of the photo lit from the pointer, with crest shadow and a glint
KEEP VERBATIM: luma gradient, Strength / Intensity / Color Mode / Emboss Depth, self-shadow march, Blinn glint, click stamp, ridge packets
MECHANISM INTERROGATION:
  tactic 2: a press squeezes pigment off the crest, and the tool leaves a dark groove on the downhill side
  tactic 3: `grad` and `h0` are the height; the downhill step is one more tap along `-grad`
  tactic 8: the crest should lose colour, not gain a new light
ADD:
  1. Ink squeeze — steep relief desaturates toward the plate gray
  2. Tooled groove — a thin dark line one texel downhill of the crest
FORBID on this file: a paper crumple field, a new spring, gold seams
A PACKING: ACES display RGBA (C.rgb is the light trail)
```

```
SHADER: texture
IDENTITY (one sentence): the photo sharpened by a Laplacian and an unsharp mask, with a temporal blend
KEEP VERBATIM: 3×3 Laplacian, box unsharp, Temporal Blend from C, Edge Strength and Unsharp Amount as the gains, golden vignette, treble sparkle, voronoi glitch, Audio Reactivity scaling those overlays
MECHANISM INTERROGATION:
  tactic 1: the kernel is an isotropic Laplacian; the next-better use of the same taps is a structure tensor
  tactic 2: unsharp rings; the anti-halo envelope is the same neighbourhood's min and max
  tactic 3: the eight neighbour taps are fetched and then discarded after the sums
ADD:
  1. Structure-tensor gain (§12.2A) — edge and unsharp amount rise where the neighbourhood is a real edge and stay quieter on flats
  2. Anti-halo envelope (§12.2A) — the sharpened colour is clamped to the same 3×3 range, widened by Unsharp Amount
FORMULA ADMISSION: both rows are in the photographic table; both consume the 3×3 taps already loaded; deleting either leaves this analyzer; neither is an analyzer by itself
FORBID on this file: a spring, a material costume (paper, bricks), replacing the Laplacian
A PACKING: ACES display RGBA. C is read with textureLoad as colour history (the filtering sample was a packing lie)
```

```
SHADER: zipper-reveal
IDENTITY (one sentence): a zipper splitting the photo, with staggered teeth and a slider at the head
KEEP VERBATIM: spread, tooth size, angle, tooth amplitude, staggered teeth, puller, weave, metal spec, under-fabric in the opening
MECHANISM INTERROGATION:
  tactic 2: teeth are sewn to a tape with a dashed thread, and the opened slot is darker against each lip
  tactic 3: `halfGap`, `toothPitch`, and `underColor` are already the seam geometry
  tactic 5: a tailor names the binding stitch and the shadow in the opening
ADD:
  1. Binding stitch — a dashed thread just outside the teeth, hidden under the puller
  2. Lip shadow — the opened slot darkens next to each fabric edge
FORBID on this file: venetian tapes, a new tooth shape, an IQ palette
A PACKING: ACES display RGBA (C is not read)
```
