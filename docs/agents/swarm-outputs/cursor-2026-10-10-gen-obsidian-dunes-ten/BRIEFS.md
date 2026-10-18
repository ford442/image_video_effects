# Idea Cards — obsidian → dunes ten

Written 2026-10-10 before WGSL edits. Second pass on the 2026-09-14 upgrades.
September ideas stay. Saved `params` stay byte-exact. No shared spring / ripple / IQ stamp.

```
SHADER: gen-obsidian-echo-chamber
IDENTITY: a fly-through of glossy black monoliths pinged by sonar, with shell fractures and echo taps
KEEP VERBATIM: box-and-cuts monolith march, conchoidal fracture, three decaying echo taps, mouse look, click echoes, slider roles (intensity, speed, scale, mouse influence)
ADD:
  1. flutter echo — parallel glass faces already form a corridor; a rapid evenly spaced tap train when the view runs along them
  2. flow banding — volcanic glass carries faint longitudinal streaks the concentric fracture shells cut across
FORBID: a new spring, replacing the march with a 2D kaleidoscope
A PACKING: ACES display RGBA in A
```

```
SHADER: gen-opal-circuit
IDENTITY: hex-grid copper traces on Bragg opal, with Manhattan signal edges
KEEP VERBATIM: hex lattice, H/V traces and vias, Bragg play-of-colour, Manhattan edge + ringing, bass slot 133, slider roles (trace scale, pulse, iridescence, bloom)
ADD:
  1. solder-mask windows — dark green mask between traces, openings where copper and vias already sit
  2. bond-wire arc — a gold parabola leaving a via toward the next pad
FORBID: replacing the circuit with a new fractal, a new spring
A PACKING: ACES display RGBA in A
```

```
SHADER: gen-phase-transition-memory-weave
IDENTITY: an order-parameter field that freezes, melts, and remembers, with grains and a hysteresis latch
KEEP VERBATIM: order field, Schmitt latch, latent heat in A.a, Voronoi grain angle, memory weave in A.g, existing spring slots 133–138, slider roles (viscosity, phase scale, sharpness, glow)
ADD:
  1. critical opalescence — milky scatter that peaks where order sits on the transition they already draw
  2. twin lattice — a second hex lattice mirrored 30° inside the grain, faint beside the primary
FORBID: writing display color into A (A stays raw sim), a new spring
A PACKING: raw sim (R=order, G=memory, B=latch, A=signed latent heat); ACES on writeTexture only
```

```
SHADER: gen-phyllotaxis-galaxy-spiral
IDENTITY: golden-angle florets read as a spiral galaxy, with bulge, disk, dust lanes, and HII knots
KEEP VERBATIM: PHI placement, r = c√n, density-wave term, Sersic bulge, dust lane, HII knots, slider roles (spread, size, rotation, wave density)
ADD:
  1. flat-curve shear — inner florets lap outer ones; disk rotation still scales the whole spin
  2. parastichy sheen — the two spiral families of the same golden angle, drawn in the unresolved disk
FORBID: replacing florets with a different galaxy model, a new spring
A PACKING: ACES display RGBA in A
```

```
SHADER: gen-physarum-sacred-geometry
IDENTITY: slime-mold agents riding Flower-of-Life circles, thickening tubes that carry flux
KEEP VERBATIM: compass orbits, three-sensor turn, Tero conductance decay, A.a = trail density, slider roles (intensity, speed, scale, mouse influence)
ADD:
  1. shuttle streaming — brightness pulses along thick tubes, the streaming the conductance glow only implied
  2. five-fold dislocation — one hashed lattice site breaks the hex compass and shows as a warm scar
FORBID: changing A.a away from trail density, replacing the agent loop with Gray-Scott
A PACKING: ACES display RGBA; A.a is the trail field read back from C.a
```

```
SHADER: gen-plasma-mandala
IDENTITY: a folded plasma mandala whose ring wobbles with a diocotron mode and whose clicks repeat in every petal
KEEP VERBATIM: dihedral fold, plasma sum, diocotron ring, folded click pulses, slider roles (symmetry, spin, zoom, glow)
ADD:
  1. current filaments — radial spokes down the petal midline, separate from the mirror-edge seam
  2. Debye sheath — a dark gap just inside the existing glow ring
FORBID: a new fractal, copying the mushroom mandala, a new spring
A PACKING: ACES display RGBA in A
```

```
SHADER: gen-polar-rainbow-explosion
IDENTITY: polar neon rays and bursts around a cursor, with dispersed click shocks and Descartes bows
KEEP VERBATIM: 36 rays, particle bursts, 3 spirals, Cauchy click rings, primary/secondary bows, Alexander band, slider roles (intensity, speed, scale, color shift)
ADD:
  1. supernumerary fringes — Airy bands tucked inside the primary bow already drawn
  2. bow knots — the existing rays brighten where they cross that primary
FORBID: a third rainbow model, a new spring
A PACKING: ACES display RGBA in A (C is display; HDR trail via acesInverse)
```

```
SHADER: gen-prism-tide
IDENTITY: a refracted tide whose RGB wavefronts split, with dispersive click packets and breaking foam
KEEP VERBATIM: Cauchy splitPhase, tidePacket dispersion, Miche foam, OkLab grade, slider roles (wave scale, refraction, pulse, saturation)
ADD:
  1. capillary wrinkles — fine ripples on the forward face of a steep crest, ahead of the white foam
  2. trough set-down — water between crests darkens, the radiation-stress companion of the bright crest
FORBID: another Cauchy prism, a new spring
A PACKING: ACES display RGBA in A (premultiplied)
```

```
SHADER: gen-prismatic-crystal-growth
IDENTITY: growing octahedral crystals with facet fire and concentric growth zones
KEEP VERBATIM: lattice SDFs, Cauchy fire, growth zoning, caustics, slider roles (growth, density, prism, caustic)
ADD:
  1. hopper faces — face centers lag the edges, so the middle of a facet recesses as growth advances
  2. re-entrant twin notch — a bright groove where a twin plane meets the facet, distinct from the zone shells
FORBID: a different crystal system as the whole scene, a new spring
A PACKING: ACES display RGBA in A
```

```
SHADER: gen-prismatic-fractal-dunes
IDENTITY: wind-migrating fractal dunes with impact ripples, saltation glints, and prism geysers
KEEP VERBATIM: fbm dunes, windRipple sawtooth, KIFS geysers, saltation glints, slider roles (complexity, dispersion, geyser height, wind)
ADD:
  1. slip-face avalanche — a sand tongue running down the lee slope the shader already shades
  2. grainfall bedding — fine stripes on that same lee face, the layers the avalanche rides
FORBID: replacing dunes with a new terrain, copying the crystal-growth march
A PACKING: ACES display RGBA in A
```
