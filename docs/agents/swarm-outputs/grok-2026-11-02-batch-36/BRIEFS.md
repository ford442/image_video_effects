# Idea Cards — Grok (`cursor/batch-36`, Cursor(2), 2026-11-02)

Written before the idea edits. Twelve halftone, stipple, and ink shaders. Each card adds **two** new ideas. Earlier ideas stay. Saved `params` stay byte-exact. No shared spring, ripple stamp, or IQ palette.

`graphic-novel` is `public/shaders/graphic_novel.wgsl`.

Formula rule: a §12.2 row is used on at most one file here.

- `cyber-halftone-scanner` takes Field interlace and Dropout bursts (both §12.2B). The file is a scanner.
- `film-cross-process` takes Density-weighted grain (§12.2A). No other file takes a grain row.
- The other ten cards use device terms that are not §12.2 rows.

Prelude migration on `halftone-reveal`, `engraving-stipple`, `engraving-stipple-blue-noise`, `spec-blue-noise-stipple`, `stipple-render`, `polka-dot-reveal`, `rotoscope-ink`, and `film-cross-process` is infrastructure (`migrate_to_prelude.py`). It is not an idea and does not by itself bump `Upgraded:`.

```
SHADER: halftone
IDENTITY (one sentence): a newsprint halftone, mono or CMYK, with elliptical dots, plate misregistration, and paper grain
KEEP VERBATIM: elliptical AM dots, 15/75/0/45 screens, colorMode split, mouse focus scale, highlight skip, overprint gain, drifting plate offsets, paper grain, params Dot Scale / Contrast / Color Mode / Screen Angle
MECHANISM INTERROGATION:
  tactic 2: newsprint midtones print larger than the film, and the black plate is trapped so a loose register does not flash white
  tactic 3: `density` is already the geometric dot area and is thrown away as a linear radius
  tactic 6: C is not read; A stays display RGBA
ADD (2 native ideas):
  1. Murray-Davies midtone gain — the existing density fattens where area is near a half, before the ellipse is drawn
  2. Black trap — the K screen is cut a little larger and CMY is choked under it
FORBID on this file: a loupe, a scanline, a new spring, an IQ palette
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: halftone-reveal
IDENTITY (one sentence): a CMYK halftone that opens under the pointer like a loupe, with a magnified sample and depth-scaled dots
KEEP VERBATIM: reveal disk, loupe magnify, depth dot scale, rgbToCmyk / cmykToRgb, four screen angles, per-plate gain, highlight knockout, paper tint, params Dot Size / Angle / Reveal Size / Magnify
MECHANISM INTERROGATION:
  tactic 2: a handheld loupe twists the screen you are looking through, and newsprint dots are bitten by the paper tooth
  tactic 3: `loupe` and `hash2` are already computed and only scale the dot size or tint the paper
  tactic 6: C is not read; A stays display RGBA
ADD:
  1. Loupe twist — screen angles pick up a few degrees at the glass, falling off with the existing loupe
  2. Bitten dot edge — each plate's AM threshold is nibbled by that plate's cell hash, and only inside the reveal
FORBID on this file: black trap from halftone, a scanner dropout, a new spring
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: engraving-stipple
IDENTITY (one sentence): a copperplate of traveling hatches, roulette stipple, and a burin under the pointer
KEEP VERBATIM: contour / hatch / cross sines, burin taper from |grad|, roulette cells, hash stipple, held burin, click rings, ink pool, params Line Density / Stipple Scale / Contrast / Light Rotation
MECHANISM INTERROGATION:
  tactic 2: an etched plate foul-bites in the open copper, and the rag leaves a sheen on the wiped ground
  tactic 3: `gradMag` and `hatchDir` are already computed and only steer lines and taper
  tactic 6: C is not read; A stays telemetry (ink, hatch, burin, alpha). Do not ACES that store
ADD:
  1. Foul bite — sparse pits where the gradient is quiet, from the existing hash
  2. Wipe sheen — a tight highlight across the uninked plate, along the light direction the hatch already uses
FORBID on this file: blue-noise cells (that is the sibling shader), a new spring, spot blacks
A PACKING: telemetry RGBA (ink, hatch, burin, alpha). ACES on the display write only
```

```
SHADER: engraving-stipple-blue-noise
IDENTITY (one sentence): copperplate stipple whose dots sit on a blue-noise jitter, lit by the pointer as a raking light
KEEP VERBATIM: plastic-constant jitter, primary and secondary dots, luma-sized radius, threshold against the mask, burr hash, plate tone, highlight tint from the source, params Stipple Density / Dot Size / Mouse Light / Burr Texture (x and y keep their existing double duty)
MECHANISM INTERROGATION:
  tactic 2: a drypoint dot throws a bright shoulder of metal, and a raking light casts a short shadow off each dot
  tactic 3: `distDot`, `dotCenter`, and `dist_vec` are already computed and only test the mask or the flashlight
  tactic 6: C is not read. This file did not write A; A becomes ACES display RGBA
ADD:
  1. Drypoint shoulder — a bright ring just outside the engraved dot, scaled by the existing burr slider
  2. Raking shadow — the dot darkens the plate a short step away from the pointer
FORBID on this file: foul-bite pits from engraving-stipple, a hatch sine field, a new spring
A PACKING: ACES display RGBA (C unread). This file previously wrote no A
```

```
SHADER: spec-blue-noise-stipple
IDENTITY (one sentence): blue-noise pointillism with a primary dot, a secondary, a golden tertiary, and click splatter
KEEP VERBATIM: plastic-constant jitter, dark-cell packing, four-neighbor occupancy skip, golden tertiary, click splatter, paper ground, chromatic cell shift, params Dot Scale / Dot Size / Color Variation / Dot Density
MECHANISM INTERROGATION:
  tactic 1: blue noise is a void process — the second dot should step away from the first when they land too close
  tactic 2: two stipple dots that land on each other stack pigment and go darker
  tactic 3: `dotCenter`, `dotCenter2`, `dotMask`, and `dotMask2` are already computed
  tactic 6: C is not read; A stays display RGBA
ADD:
  1. Void push — the secondary center steps away from the primary when the gap is under a cell-space minimum
  2. Stacked pigment — where the two masks overlap, the ink goes darker than either dot alone
FORBID on this file: a copperplate shoulder, a hatch, a new spring
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: stipple-render
IDENTITY (one sentence): weighted Voronoi stipple on paper, with wet bleed under the pointer and a contour hatch
KEEP VERBATIM: blue-noise cell center, luma-sized dots, Lloyd-style luma offset, wet radius, exact-C wet memory, contour hatch, color reveal, params Dot Scale / Contrast / Wet Ink Radius / Color Reveal
MECHANISM INTERROGATION:
  tactic 1: one more Lloyd pull moves the dot toward the dark side of the cell, using the Sobel the hatch already builds
  tactic 2: wet ink that is drying leaves a coffee ring — dark rim, pale center
  tactic 3: `wetMemory` and the Sobel are already computed and only open the bleed or draw the hatch
  tactic 6: C is display colour; prevInk stays a luma of that colour. A stays display RGBA
ADD:
  1. Downhill stipple — the dot center shifts along the existing Sobel, toward darker luma
  2. Coffee ring — where last frame was wet, the rim darkens and the core opens back toward paper
FORBID on this file: blue-noise void push, roulette stipple, a new spring
A PACKING: ACES display RGBA (unchanged). C is an exact load of display colour
```

```
SHADER: cyber-halftone-scanner
IDENTITY (one sentence): a CMYK scanner — rotated AM screens, a sweeping scanline, glitch skips, and click-fired scan bursts
KEEP VERBATIM: 15/75/0/45 AM cells, RGB split, scanline and glitch skip, click bursts, pointer bloom, hard-dot under the scan, plasma tint on the stripe, params Dot Scale / Scan Speed / RGB Split / Brightness
MECHANISM INTERROGATION:
  tactic 2: a flatbed is interlaced, and the lamp drops whole segments of a line
  tactic 5: a scanner technician names field shear and a lamp dropout; neither is drawn yet
  tactic 6: C is not read; A stays display RGBA
ADD:
  1. Interlaced field shear — odd rows lag half a dot on the existing screens (§12.2B Field interlace)
  2. Lamp dropout — a missed line goes to paper with an exponential tail along x (§12.2B Dropout bursts)
FORBID on this file: newsprint trap, a loupe, a new spring, an IQ palette
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: polka-dot-reveal
IDENTITY (one sentence): polka dots that grow with luminance and open around the pointer, with a trail
KEEP VERBATIM: density falloff from the smoothed mouse, chain-dot merge, drag stretch, per-cell jitter, depth / luma / edge alpha, bass envelope, chromatic cell shift, params Intensity / Speed / Scale / Detail
MECHANISM INTERROGATION:
  tactic 2: once polka dots chain, the gaps are holes, and a printed dot carries a small specular pip
  tactic 3: `chain`, `circle`, and `local` are already computed and only build the mask and the drag
  tactic 6: A is state (bass envelope, smoothed mouse, trail alpha). Do not ACES that store. C is that state
ADD:
  1. Chain holes — where the dots have chained, the gaps lose alpha so the lattice reads as punched holes
  2. Dot pip — a small highlight inside the dot, offset toward the pointer
FORBID on this file: CMYK plates, a scanline, a new spring (the mouse smooth stays in C)
A PACKING: R bass envelope, GB smoothed mouse, A trail alpha. ACES on the display write only
```

```
SHADER: polka-wave
IDENTITY (one sentence): four CMYK polka plates whose grid rides a wave from the pointer
KEEP VERBATIM: four-plate loop, fixed screen angles, wave from mouse distance, click fronts, invert, dot gain from sample brightness, rosette spectral, params Grid Density / Wave Amp / Wave Freq / Wave Speed
MECHANISM INTERROGATION:
  tactic 2: a dot on a wave crest squashes into an oval, and a four-plate rosette has a paper eye where every plate overlaps
  tactic 3: `cellUv` and each plate `invertMask` are already computed and only test a round dot
  tactic 6: C is not read; A stays display RGBA
ADD:
  1. Crest squash — the cell metric stretches along the wave the grid is already riding
  2. Rosette eye — the product of the four plate masks punches paper white
FORBID on this file: black trap, loupe twist, a new spring
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: rotoscope-ink
IDENTITY (one sentence): posterized cels with a tapered ink line that follows the edge
KEEP VERBATIM: edge threshold, posterize levels, ink density, shade mix, edge-magnitude ink weight, hold-flats, brush sine, fast-edge chroma, mouse ink, params Edge Threshold / Posterize Levels / Ink Density / Shade Mix
MECHANISM INTERROGATION:
  tactic 2: a rotoscope line is a dry-brush halo under a darker core, and a held cel boils a pixel at the exposure rate
  tactic 3: `brushStroke` and `holdFlat` are already computed and only mask the one line and the flat mix
  tactic 6: C is not read; A stays telemetry (outline, motion, mouse, alpha). Do not ACES that store
ADD:
  1. Double weight — a wider dry-brush under the existing tapered core
  2. Cel boil — flats resample a pixel away on a 12-per-second hold; the line stays on the stable sample
FORBID on this file: comic spot blacks (that is graphic-novel), a hatch screen, a new spring
A PACKING: telemetry RGBA (outline, motion, mouse, alpha). ACES on the display write only
```

```
SHADER: film-cross-process
IDENTITY (one sentence): E-6 shot developed in C-41 — split S-curves, a cyan/yellow skew, grain, and a vignette
KEEP VERBATIM: per-channel scurve pivots, skew mix, shadow desaturate, per-channel grain seeds, vignette, highlight cyan-green crossover, developer spring in extraBuffer[133..138], chemical rings, params Contrast Punch / Colour Skew / Film Grain / Vignette
MECHANISM INTERROGATION:
  tactic 2: grain follows density, and cross-process shadows go teal while the highlights stay the existing cyan-green
  tactic 3: `luma` and `shadowMix` are already computed for the desaturate and then discarded
  tactic 6: C is not read; A stays display RGBA. The spring stays; it is the enlarger the file already has
ADD:
  1. Density-weighted grain — the existing per-channel hash is scaled by sqrt(L*(1-L)) (§12.2A)
  2. Shadow teal — the shadow mix, times the existing skew, pulls red down and blue up
FORBID on this file: halftone dots, a second spring, halation (leave that for a film file that does not already own the highlight crossover)
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: graphic-novel
IDENTITY (one sentence): a comic page — posterized color, rotated screens, spot blacks, pen hatch, and a weighted contour
KEEP VERBATIM: adaptive contour, shadow-side weight, spot blacks, 45° hatch plus the crossing set, screen dots, registration fringe, paper fiber, held ink, click rings, C history mix, params Dot Size / Edge Strength / Color Levels / Paper Grain
MECHANISM INTERROGATION:
  tactic 2: pen strokes feather into a spotted black instead of stopping on a hard edge, and a comic page is boxed by a panel rule
  tactic 3: `spotBlack` and `hatch` are already computed and only composite as a max
  tactic 6: C is display colour, mixed a little into the page. A stays that display RGBA
ADD:
  1. Feather into the spot — hatch thickens on the shoulder of the solid, then the black takes over
  2. Panel rule — a thin ink rectangle inset from the frame, skipped where the spot black already fills
FORBID on this file: rotoscope boil, a CMYK loupe, a new spring
A PACKING: ACES display RGBA (unchanged). C is an exact load of display colour
```
