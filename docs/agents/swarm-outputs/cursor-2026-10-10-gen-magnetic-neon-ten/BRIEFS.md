# Idea Cards — magnetic → neon ten

Written 2026-10-10 before WGSL edits. Second pass on the 2026-09-14 upgrades.
September ideas stay. Saved `params` stay byte-exact. No shared spring / ripple / IQ stamp.

```
SHADER: gen-magnetic-field-lines
IDENTITY (one sentence): north/south dipole field lines with charged streaks, iron-filing chains, and an X-point flash
KEEP VERBATIM: dipole kernel (3(m·r)r − m)/r³; six sin²θ shells; 18 particle segments; LIC chain; Jacobian X-point; mouse dipole; trail from C; slider roles (strength, speed, dipole count, trail)
ADD (2–4 native ideas):
  1. cyclotron gyration — charges already stream along B; they also circle it, tighter where |B| is strong
  2. magnetic-mirror pile-up — the same streaks stall and brighten where the field line pinches near a pole
FORBID on this file: a new spring, IQ palette, replacing the dipole with curl noise
A PACKING: ACES display RGBA in A (C read as display history)
```

```
SHADER: gen-magnetic-kelp
IDENTITY (one sentence): holdfast-rooted kelp lanes that bend in the current, with gas bladders and a magnetic lean toward the cursor
KEEP VERBATIM: lane strands, Euler-Bernoulli cantilever, pneumatocyst lattice, fronds/tips, surge ripples, magnetic pull, bass slot 133, slider roles (density, current, magnetism, biolume)
ADD:
  1. Vogel reconfiguration — blades already feel the current; they streamwise-flatten as that current rises
  2. intercalary meristem — youngest blade tissue is pale just tip-ward of each existing bladder
FORBID on this file: a new creature, ferrofluid spikes, IQ candy as the whole look
A PACKING: ACES display RGBA in A
```

```
SHADER: gen-magnetic-storm
IDENTITY (one sentence): curl-flow field lines around a mouse pole, with Alfvén kinks and a green/red auroral oval
KEEP VERBATIM: dipole + curl bands, Alfvén kink ∝ √|B|, oval 557.7/630 nm, SSC shock ripples, slider roles (scale, flow, density, storm)
ADD:
  1. whistler chorus — rising-tone beads that ride the field lines this storm already draws
  2. plasmapause step — field lines bunch inside a cold-plasma boundary and a radial ledge marks it
FORBID on this file: replacing the storm with iron-filing LIC from the dipole shader, or a new spring
A PACKING: ACES display RGBA in A
```

```
SHADER: gen-mandelbox-explorer
IDENTITY (one sentence): a sliced Mandelbox colored by fold itinerary and lit from its distance estimate
KEEP VERBATIM: boxFold, sphereFold, scale, running-derivative DE, steel/gold/violet itinerary, mouse rotation, slice on held mouse.y, slider roles (scale, iterations, slice, specular)
ADD:
  1. space-diagonal trap — the box's (1,1,1) symmetry axis, tracked in the existing orbit loop
  2. bounded interior — orbits that never escape read as glassy volume instead of only boundary color
FORBID on this file: a different fractal (Mandelbrot, Julia bulb), spring cursor, IQ palette swap
A PACKING: ACES display RGBA in A
```

```
SHADER: gen-metaball-soft-body
IDENTITY (one sentence): metallic metaballs with Rayleigh shape modes and beaded necks, pulled by the cursor
KEEP VERBATIM: inverse-square field, l=2/l=3 modes, Rayleigh–Plateau neck, mouse gravity, env reflection, bass slot 133, slider roles (count, roughness, hue, caustic)
ADD:
  1. meniscus thin-film — the merging neck already exists; it now carries soap-film color along that bead
  2. nephroid caustic — the caustic slider draws a crescent inside the silhouette, not only a flat blue multiply
FORBID on this file: replacing metaballs with an SDF creature or a Gray-Scott solver
A PACKING: ACES display RGBA in A
```

```
SHADER: gen-micro-cosmos
IDENTITY (one sentence): raymarched cells in a current, seen in phase contrast or darkfield, dividing by binary fission
KEEP VERBATIM: ellipsoid map, fission furrow, Zernike thickness, darkfield on held mouse, marine snow, click blooms, slider roles (density, fluid, glow, color shift)
ADD:
  1. metachronal cilia — a phase wave of strokes around the rim the microscope view already lights
  2. contractile vacuole — a clear vesicle on the cell that fills and collapses, timed by fluid activity
FORBID on this file: replacing the raymarch with a 2D particle galaxy, or a new spring
A PACKING: ACES display RGBA in A
```

```
SHADER: gen-murmuration-phantom
IDENTITY (one sentence): a starling mass morphing sphere → torus → wave, with banking bands and sky showing through the core
KEEP VERBATIM: shape-morph SDF sequence, local curl, banking wave, marginal optical depth, C trail, slider roles (size, morph, glint, cohesion)
ADD:
  1. scale-free correlated turn — one long-wavelength curl so the whole flock wheels together, stronger with cohesion
  2. heading-defect eye — a clear hole where flock vorticity changes sign, so sky shows through a wheel
FORBID on this file: predator sprite, IQ palette, copying kelp or mycelium
A PACKING: ACES display RGBA in A (C.rgb colour history, C.a coverage → trail density)
```

```
SHADER: gen-mushroom-mandala-garden
IDENTITY (one sentence): a radial mandala of mushroom caps, tiered gills, and Buller's-drop spores
KEEP VERBATIM: polar cap/stem, lamella + lamellula II/III, ballistospore lattice, mycelium, fairy ring, slider roles (caps, breathe, gills, biolume)
ADD:
  1. partial-veil annulus — a pale ring left on the stipe the mandala already draws
  2. universal-veil warts — scattered pale spots on the cap, a different structure from the gill tiers
FORBID on this file: replacing the mandala with a 3D raymarched forest, or a spring overlay
A PACKING: ACES display RGBA in A
```

```
SHADER: gen-mycelium-network
IDENTITY (one sentence): chemotactic hyphae advancing in a growth zone, with click-germinated spores and anastomosis
KEEP VERBATIM: segment walk and cull, nutrient pull, autolysis vitality, germinate(), pulses, kick slots 133–135, slider roles (growth, branching, nutrient, biolume)
ADD:
  1. clamp connections — small bypass loops at septa on the existing hypha, not the cross-branch fusion already there
  2. septal cross-walls — dark compartments along hypha age, each with a guttation bead
FORBID on this file: a mushroom-cap mandala, Gray-Scott, a new spring
A PACKING: ACES display RGBA in A (rgb = decayed network light, a = glow mass)
```

```
SHADER: gen-neon-acid-geometry
IDENTITY (one sentence): a grid of neon triangles, hexes, and circles whose color is an indicator pH, with discharge striations and titration fronts
KEEP VERBATIM: triangle/hex/circle SDFs and smin morph, phToColor, positive-column striations, titration sigmoid, slider roles (intensity, speed, scale, color shift)
ADD:
  1. acid-etch bevel — a bright lip just outside each wall and a darker undercut just inside
  2. cathode spot — a hot glow fixed on each tube, brighter while the mouse is held (discharge current)
FORBID on this file: replacing the geometry with a fractal, or stamping the magnetic-storm aurora
A PACKING: ACES display RGBA in A
```
