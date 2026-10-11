# Cursor (Grok 4.7) — crackle palm through echo chamber

Written before WGSL edits. `gen-evolutionary-cellular-gardens` is skipped: ledger event 2026-10-09, header `Upgraded: 2026-10-10` (chrono-ferro ten). `gen-feedback-echo-chamber` was on that October 9 list but has an empty ledger history, so it stays in this batch.

No overlap with the 2026-10-10 fireworks ten (`fan-shell` through `wind-ripple`) or the Sonnet fractal set.

```
SHADER: gen-fireworks-crackle-palm
IDENTITY (one sentence): a mortar shell that bursts, then crackles, then droops into a palm of paired leaflets
KEEP VERBATIM: ascent then primary sparks; crackle born on those spark positions; opposite leaflet pairs; shell energy / stage delay / crackle / palm spread; held mouse command shell; ACES display RGBA history
ADD:
  1. rachis filament — a continuous midrib between frond samples so leaflets hang off a spine
  2. frond-tip pistil — a hotter spark at the end of each frond
FORBID on this file: fan-shell ribs, willow drip, generic spring overlay
A PACKING: ACES display RGBA
```

```
SHADER: gen-fireworks-crossette
IDENTITY (one sentence): a traveling star that forks into four colored arms with an X flash at the split
KEEP VERBATIM: parent star then four-way fork; split-instant X flash; arm colors; hex bokeh; gravity; shell power / split delay / arm spread / hue shift; held mouse crossette; ACES display RGBA history
ADD:
  1. parent comet sheath — the star is stretched along its travel before the fork
  2. split stagger — each cardinal arm forks a few milliseconds after the previous one
FORBID on this file: palm leaflets, crackle pops, peacock fan
A PACKING: ACES display RGBA
```

```
SHADER: gen-fluffy-raincloud
IDENTITY (one sentence): a curl-advected thunderhead with silver lining, an anvil top, and virga
KEEP VERBATIM: density / velocity.xy / moisture packing (no ACES on A); curl noise; vorticity confinement; anvil deck; virga; Mie silver; coverage / turbulence / rain / wind; spring gust in extraBuffer[133..136]; click gusts
ADD:
  1. mammatus pouches — hanging lobes on the underside of the anvil
  2. shelf-cloud roll — a wind-sheared density lip where the deck meets the rain
FORBID on this file: fireworks sparks, ACES on stored fields, a second spring
A PACKING: raw density, velocity.xy, moisture
```

```
SHADER: gen-fourier-epicycles
IDENTITY (one sentence): nested harmonic wheels whose pen draws a trail
KEEP VERBATIM: epicycle chain; arm-segment glow; pen ink into the C trail pack; rotation speed / cycle count / rim intensity / trail persistence; mouse gravity and held shock; A stores bassEnv, trail.r, trail.g, alpha (ACES on writeTexture only)
ADD:
  1. phase tick — a short radial mark where each arm meets its rim
  2. cusp ink — the pen blot thickens when the chain is barely moving
FORBID on this file: gear teeth, escapement, ruby jewels
A PACKING: bassEnv, trail.r, trail.g, alpha
```

```
SHADER: gen-fractal-clockwork
IDENTITY (one sentence): an infinite field of brass gears that step one tooth per escapement tick
KEEP VERBATIM: gear SDF and cell parity; tooth sparks; mesh line; dead-beat tick; ruby jewel bearings; gear scale / teeth / rotation speed / material; spring orbit in extraBuffer[133..138]; click torque from ripples; ACES display RGBA
ADD:
  1. oil weep — an amber film along the existing mesh contact
  2. hairspring — a spiral in the axle bore on the gear face
FORBID on this file: Fourier pen trails, epicycle rims
A PACKING: ACES display RGBA
```

```
SHADER: gen-fractal-ember-lattice
IDENTITY (one sentence): a hot triangular lattice that shatters into rigid shards and reforms
KEEP VERBATIM: tri-lattice; triple junctions; cell-core heat; heat crawl; shard cooling and re-ignition; glow / shard size / lattice scale / spark density; mouse shatter; A.rg displacement, A.b seed, A.a reform (no ACES on A)
ADD:
  1. oxide scale — dark crust on cooled shard faces, away from the hot edges
  2. pop-off sparks — embers that leave the lattice along the shatter displacement
FORBID on this file: monolith SDF, ghost-flame fluid
A PACKING: raw shard state — A.rg displacement, A.b seed, A.a reform
```

```
SHADER: gen-fractured-monolith
IDENTITY (one sentence): a levitating fractured slab over a liquid floor, with seam light in the cracks
KEEP VERBATIM: box fracture and cell drift; per-shard tint; fracture-plane glints; seam light pool; rising seam pulse; fracture spread / levitation / glow / rotation; mouse orbit; ACES display RGBA
ADD:
  1. spall chips — small stone chips knocked off shard corners
  2. crack dust — a gray veil mixed into the seam glow where the spread opens the slab
FORBID on this file: ember lattice, gear train
A PACKING: ACES display RGBA
```

```
SHADER: gen-ghost-flame
IDENTITY (one sentence): a buoyant ghost flame with a wick, a blue ignition band, puffing packets, and heat haze
KEEP VERBATIM: temperature, fuel, vx, age (no ACES on A); wick; chemiluminescence; puff pinch-off; schlieren; flame height / turbulence / cooling / diffusion; mouse heat; click bursts; bass/RMS envelope in extraBuffer[133..134]
ADD:
  1. inner cone — a cooler blue core hugging the wick, inside the ignition band
  2. soot streak — dark spent carbon where the gas has aged and the fuel is gone
FORBID on this file: fireworks shells, lattice shatter
A PACKING: raw sim state (temperature, fuel, vx, age); ACES on display only
```

```
SHADER: gen-feedback-echo-chamber
IDENTITY (one sentence): a delay chamber that recycles the picture through spaced echo taps and standing-wave nodes
KEEP VERBATIM: echo loop and decay; harmonic ladder at 2x spacing; nodal interference; echo count / decay / spacing / color shift; mouse gravity; held shock; click ripples; bass envelope in extraBuffer[133]; ACES display RGBA
ADD:
  1. early wall reflections — one mirror tap off each frame edge, dimmer than the delay ladder
  2. comb-filter notches — dark bands whose spacing follows the echo-spacing slider
FORBID on this file: obsidian flutter-echo costume, a new sim
A PACKING: ACES display RGBA
```
