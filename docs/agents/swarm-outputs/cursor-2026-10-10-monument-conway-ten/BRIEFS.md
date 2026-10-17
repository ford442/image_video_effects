# Idea Cards — monument → Conway ten

Written 2026-10-10 before WGSL edits. Second pass on the 2026-09-27 upgrades
(monolith resonator already carries the 2026-10-10 Chladni / wake / core-leak pass).
Prior ideas stay. Saved `params` stay byte-exact. No shared spring / ripple / IQ stamp.

```
SHADER: gen-brutalist-monument
IDENTITY (one sentence): board-formed concrete pillars around a floating brass octahedron in fog
KEEP VERBATIM: pillar grid and 3×3 clearing; octahedron artifact; sun / fog / scale / complexity; board-form lines, tie holes, ledge stains
ADD:
  1. pour joints — cold seams between lifts of the same board-formed pour
  2. aggregate pop-out — pale stones and dark pits in the vertical concrete mix
FORBID on this file: a new spring, IQ palette, replacing the monument with a city
A PACKING: pre-ACES display RGBA in A; ACES on writeTexture
```

```
SHADER: gen-buddhabrot-aura
IDENTITY (one sentence): Buddhabrot density from escaping orbits, with nebulabrot channels and an interior dust
KEEP VERBATIM: z²+c samples; early/mid/late escape RGB; anti-Buddhabrot interior; min-distance spine; escape-argument streaks; slider roles (threshold, density, zoom, aura)
ADD:
  1. main-cardioid limb — the set these orbits are sampling, drawn as a thin contour in the c-plane
  2. period-2 bulb — the circle at c=−1, the next bulb on that same boundary
  3. dwell isochrones — thin rings of escape time, separate from the RGB time bins
FORBID on this file: a Julia rewrite, a new spring, an IQ palette swap
A PACKING: ACES display RGBA in A (C read as display history)
```

```
SHADER: gen-cellular-automata-tapestry
IDENTITY (one sentence): Gray-Scott tapestry whose feed and kill follow the picture, with anisotropic stripes
KEEP VERBATIM: 3×3 Gray-Scott; feed/kill/diffusion sliders; kill-rate bands; anisotropy; spot nucleus; substrate halo; raw A = (nextA, nextB)
ADD:
  1. weft threads — cloth lines across the anisotropy grain the solver already has
  2. apoptosis pits — dark holes where B is falling and A is recovering
FORBID on this file: replacing Gray-Scott with Conway, a new spring, IQ candy as the stain
A PACKING: raw sim (nextA, nextB, 0, 1); ACES on writeTexture only
```

```
SHADER: gen-chaos-game-ifs
IDENTITY (one sentence): a three-vertex chaos game over a raymarched orbit sculpture
KEEP VERBATIM: three-map IFS; chromatic offsets; rings; last-vertex tint; Sierpinski hole; iterate age; median scaffold; sculpture SDFs; existing spring; slider roles (iterations, glow, rings, saturation)
ADD:
  1. fixed-point glints — bright points at the three vertices the scaffold already draws
  2. contraction echo — a fainter glow at twice the last-iterate radius, the previous scale step
FORBID on this file: a fourth vertex, a different fractal, a new spring
A PACKING: ACES display RGBA in A
```

```
SHADER: gen-chromatic-acid-drip
IDENTITY (one sentence): pH-colored metaball drips with necks, menisci, and channel lag
KEEP VERBATIM: metaball field; universal-indicator color; Plateau-Rayleigh necks; coffee-ring menisci; down-gravity channel lag; slider roles (intensity, speed, scale, color shift)
ADD:
  1. pendant beads — a small satellite drop just down-gravity of each blob the neck already thins
  2. etch scars — the trailing edge of a drip bites a dark scar into the glass
FORBID on this file: a new spring, replacing drips with a 3D raymarch, IQ palette
A PACKING: HDR display RGBA in A; ACES on writeTexture only
```

```
SHADER: gen-chromatic-zonohedron
IDENTITY (one sentence): a four-generator rhombic zonohedron with spectral faces, zone belts, and an inset
KEEP VERBATIM: four generators; dichroic face hue; pair IDs; vertex stars; zone belts; Minkowski inset; slider roles (scale, spin, edge, color cycle)
ADD:
  1. rhomb diagonal — the short diagonal of the winning cell, the line the inset does not draw
  2. zone-axis shade — face brightness follows how aligned that cell's generator is with the screen
FORBID on this file: a fifth generator, a spring, replacing the tiling with a 3D raymarch
A PACKING: ACES display RGBA in A
```

```
SHADER: gen-conway-game-of-life
IDENTITY (one sentence): Conway Life morphing through Day & Night and HighLife, with heat, still-life amber, and glider lean
KEEP VERBATIM: three rule families; neighbor heat; still-life amber; isolation vs overcrowding deaths; glider lean; generation in A.g; existing spring; slider roles (seed, morph, grid, trail)
ADD:
  1. cell bezel — a dark inset edge so a live cell reads as a tile
  2. oscillator strobe — young survivors blink; still lifes stay the amber they already are
FORBID on this file: a new spring, replacing the rules with Gray-Scott, IQ palette
A PACKING: raw alive, generation, activity, alpha
```

```
SHADER: gen-chronos-labyrinth
IDENTITY (one sentence): an Escher maze of shifting cells, stairs, and temporal rifts
KEEP VERBATIM: four structure types; stair nosing; shift-ghost; masonry; rift echo in A.r; clock sigil; existing spring and shockwaves; slider roles (complexity, shift, rifts, atmosphere)
ADD:
  1. worn treads — a pale centerline on the upward face of each stair
  2. rift limb — a bright grazing shell on the anomaly, separate from its fill glow
FORBID on this file: a new spring, replacing the maze with a different monument, IQ candy as the stone
A PACKING: rift echo, depth, material, alpha
```

```
SHADER: gen-celestial-forge
IDENTITY (one sentence): contra-rotating forge rings around a plasma core, tempered by ring index
KEEP VERBATIM: core, rings, hammer flats, greeble, plasma arcs; temper gradient; existing spring and hammer strikes; slider roles (speed, complexity, ring scale, core)
ADD:
  1. hammer scale — dark oxide flakes on the cooler outer rings that flash when a strike lands
  2. quench collar — a pale steam ring just outside the core
FORBID on this file: a new creature, a second spring, replacing the rings with a zonohedron
A PACKING: ACES display RGBA in A
```

```
SHADER: gen-chronos-monolith-resonator
IDENTITY (one sentence): a KIFS obsidian monolith with orbiting plasma ribbons and a leaking crystal core
KEEP VERBATIM: KIFS box folds; three ribbon capsules; Chladni node lines; ribbon time-echo wakes; fracture core-leak; slider roles (flow, plasma, complexity, resonance)
ADD:
  1. fold seams — a crease where the absolute-coordinate sum meets the KIFS fold limit
  2. braid knots — gold points where two of the existing ribbons pass close
FORBID on this file: a new spring, replacing KIFS with a different fractal, copying the labyrinth clock
A PACKING: HDR display RGB + semantic alpha (C read as colour history); ACES on writeTexture only
```
