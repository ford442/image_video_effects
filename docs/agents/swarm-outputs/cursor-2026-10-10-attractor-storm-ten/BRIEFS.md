# Idea Cards — attractor → storm ten

Written 2026-10-10 before WGSL edits. Second pass on the existing upgrades.
`gen-electric-kaleidoscope-storm` already carries the 2026-10-10 Lichtenberg / return-stroke / seam / corona pass; the new ideas sit on that identity.
Prior ideas stay. Saved `params` stay byte-exact. No shared spring / ripple / IQ stamp.

```
SHADER: gen-de-jong-attractor
IDENTITY (one sentence): Peter de Jong lace, x' = sin(a y) − cos(b x), with a lifted tube orbit
KEEP VERBATIM: the map; stretch tint; dwell rings; critical curves; antipodal ghost; tube SDF; existing spring; slider roles (morph A, morph B, glow, decay)
ADD:
  1. stall glints — bright knots where the map barely moves, the fixed-point slowdown of this attractor
  2. Jacobian caustic — orbits pile up where the determinant of the map's derivative vanishes
FORBID on this file: a different attractor, a new spring, replacing the lace with a Julia set
A PACKING: accumulated density, hue phase, tube depth, alpha (raw); ACES on writeTexture only
```

```
SHADER: gen-dla-copper-deposition
IDENTITY (one sentence): a copper dendrite growing by diffusion-limited aggregation, oxidizing as it ages
KEEP VERBATIM: deposit / depletion / oxidation / activity packing; tip screening; growth-front sheen; cathode and click seeds; slider roles (scale, arms, oxidation, spark)
ADD:
  1. dendrite twin — a pale ridge along the existing arm crest, the twin habit of the copper
  2. electrolyte meniscus — a wet line where depletion is half full, outside the deposit
FORBID on this file: replacing DLA with Gray-Scott, a new spring, IQ candy as the metal
A PACKING: raw deposit, depletion, oxidation, activity
```

```
SHADER: gen-dmt-fractal-zoom
IDENTITY (one sentence): a zooming Mandelbrot / burning-ship hybrid with orbit traps and a second layer
KEEP VERBATIM: escape radius |z|²>4; hybrid abs mix; orbit trap; second layer; slider roles (intensity, speed, scale, color shift)
ADD:
  1. escape-argument spokes — the angle of the escaping z colors the exterior
  2. interior nucleus — points that never escape glow from how small the final |z| is
FORBID on this file: replacing the zoom with a Buddhabrot, a new spring, a different palette family
A PACKING: ACES display RGBA in A (C read as display history)
```

```
SHADER: gen-dragon-curve
IDENTITY (one sentence): a Heighway dragon drawn as a folded neon paper strip
KEEP VERBATIM: turn rule from the lowest set bit; paper crease; generation thickness; slider roles (zoom, glow, chromatic, feedback)
ADD:
  1. paper selvedge — the other edge of the strip, a parallel line at a fixed offset from the fold
  2. fold-generation bands — brightness steps at powers of two along the curve, the paperfold order
FORBID on this file: a Hilbert or Koch replacement, a new spring, a 3D dragon
A PACKING: ACES display RGBA
```

```
SHADER: gen-dynamic-tessellation-ornate-fractal-tiles
IDENTITY (one sentence): a grid of Julia tiles with grout and a blackbody interior
KEEP VERBATIM: per-tile z²+c; grout; blackbody mix; slider roles (detail, speed, density, mouse warp)
ADD:
  1. corner rosettes — a small ornament inside each tile corner, on the tiling the grout already marks
  2. equipotential contours — thin rings of the tile's own iteration count
FORBID on this file: replacing the Julia tile with a zonohedron, a new spring, an IQ swap of the blackbody
A PACKING: HDR in A; ACES on writeTexture
```

```
SHADER: gen-echo-dunes
IDENTITY (one sentence): wind-driven dunes with a leeward slipface, sand streaks, mirage, and echo rings
KEEP VERBATIM: three ridge sines; slipface; wind streaks; echo rings; mirage; slider roles (scale, wind, mirage, echo)
ADD:
  1. crest saltation — bright grains only on the ridge crest, not across the whole face
  2. avalanche tongue — a darker grainflow lobe down the existing slipface
FORBID on this file: replacing dunes with strata, a new spring, a city
A PACKING: HDR display RGBA in A; ACES on writeTexture
```

```
SHADER: gen-erosion-strata
IDENTITY (one sentence): eroded sedimentary beds with contacts, cross-beds, veins, and a water line
KEEP VERBATIM: layer index; bedding contacts; cross-beds; mineral veins; water; slider roles (erosion, density, veins, water)
ADD:
  1. ripple marks — small waves on the top of a bed, the surface the cross-beds sit under
  2. iron concretions — round ochre nodules inside the sand beds
FORBID on this file: replacing the cliff with dunes, a new spring, IQ candy
A PACKING: ACES display RGBA
```

```
SHADER: gen-emergent-script-gardens
IDENTITY (one sentence): phyllotactic ink gardens with opposing spiral veins and ligatures
KEEP VERBATIM: golden-angle spirals; parastichy veins; ligature bridges; paper/neon mix; slider roles (density, curvature, scale, ink/neon)
ADD:
  1. serif terminals — a short crossbar at the end of each primary stroke
  2. ink bleed — a feathered halo in the paper around the stroke, wider than the line
FORBID on this file: replacing script with a maze, a new spring, a fractal zoom
A PACKING: pre-ACES color RGB + totalInk in A.a; ACES on writeTexture only
```

```
SHADER: gen-cymatic-plasma-mandalas
IDENTITY (one sentence): a folded mandala whose outline is a three-band Chladni plate, with sand at the nodes
KEEP VERBATIM: three-band sum; sand at shared zeros; polygon fold; slider roles (symmetry, density, frequency, swirl)
ADD:
  1. antinode bellies — the plate is brightest where the summed wave is fullest, opposite the sand
  2. circular nodal rings — the bass wave's zero crossings as rings, under the angular fold
FORBID on this file: replacing the plate with a kaleidoscope storm, a new spring, a different creature
A PACKING: ACES display RGBA in A
```

```
SHADER: gen-electric-kaleidoscope-storm
IDENTITY (one sentence): kaleidoscope-folded lightning with leader and return strokes, seam arcs, and tip corona
KEEP VERBATIM: folded bolts; Lichtenberg trail; leader vs return; mirror-seam arcs; tip corona; slider roles (intensity, flicker, symmetry, color)
ADD:
  1. leader pause beads — a bright knot at the middle of each bolt segment, where the stepped leader hesitates
  2. ground streamers — faint upward spikes at the outer radius, reaching toward the folded storm
FORBID on this file: a new spring, replacing bolts with a mandala plate, copying the dragon curve
A PACKING: HDR trail RGB in A; ACES on writeTexture only
```
