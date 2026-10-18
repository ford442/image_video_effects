# Cursor batch-03 — Idea Cards

Written before WGSL edits. 2026-10-17.

```
SHADER: rd-on-video-pass1
IDENTITY: Gray-Scott U/V continuously fed by the video's luminance
KEEP VERBATIM: feed/kill/diffusion/dt slider roles, 5-point laplacian, luma seed and memory, hover inoculation, click fronts, A = (U, V, luma memory, reaction activity), B never written
ADD:
  1. Contour stretch — extra diffusion of V along the video-luma tangent, so spots elongate with the picture's edges
  2. Spot fission — a central kill where V is high and its laplacian is flat, so wide spots pinch and divide
FORBID: a new palette, replacing Gray-Scott, ACES on the stored U/V
A PACKING: raw (U, V, source-luma memory, reaction activity)
```

```
SHADER: rd-on-video-pass2
IDENTITY: four-stop Turing palette of the V field, with an edge and a luma-seed lift
KEEP VERBATIM: palette stops, pattern gamma / edge gain / seed gain / hue shift, B = colorized rgb + pattern, no A write
ADD:
  1. Isochrone threads — narrow bands where the pattern crosses one-third and two-thirds, drawn in the next palette stop
  2. Substrate core — depleted U tints the interior of a high-V spot cooler than its rim
FORBID: a second solver, writing A (that would erase pass 1's chemistry), click springs
A PACKING: B = pre-ACES palette rgb + pattern. Pass 2 does not write A. Display ACES is on writeTexture only.
```

```
SHADER: rd-on-video-pass3
IDENTITY: the pattern composited over the video through a luminance gate
KEEP VERBATIM: luma gate, mask softness, glow, blend; no A write
ADD:
  1. Dye take-up — the overlay hue leans into the video's own color where the pattern is dense
  2. Gate meniscus — a bright hairline where luma crosses the gate and the pattern is present
FORBID: writing A, a new reaction-diffusion step
A PACKING: pass 3 writes display ACES RGBA only. C is the previous feedback (chemistry, because A wins the copy).
```

```
SHADER: liquid-optimized-pass1
IDENTITY: capillary plus gravity wave solver with a meniscus, click packets, and ambient micro-ripples
KEEP VERBATIM: laplacian/biharmonic split, meniscus, click packets, three ambient sines, A = (h_prev, h_curr, velocity, age)
ADD:
  1. Seiche beat — a slow basin envelope on the ambient ripples so the shimmer breathes
  2. Shore set-down — radiation stress lowers the waterline on the depth contact band
FORBID: replacing the wave equation, ACES on stored heights, crest-lean (that belongs to liquid-pass1)
A PACKING: raw (h_prev, h_curr, velocity, age). Turbidity (default 0) also adds drag so the slider is live on this pass.
```

```
SHADER: liquid-optimized-pass2
IDENTITY: Fresnel and Beer-Lambert shade of the height field over the photo
KEEP VERBATIM: height normal, Schlick Fresnel, per-channel absorption, specular, turbidity, no A write
ADD:
  1. Snell offset — the photo sample shifts along the normal, so the surface actually refracts
  2. Velocity glint — the highlight stretches with |velocity| into a streak along the wave
FORBID: writing A (that would erase the height field), fold-caustics (that belongs to liquid-pass2)
A PACKING: display ACES RGBA on writeTexture. Height stays in pass 1's A. Gravity and damping scale normal and spec power; at defaults the scales match the previous constants.
```

```
SHADER: gen-tectonic-plasma-crucible
IDENTITY: Voronoi crust plates over a blackbody magma ocean, with heat in the fissures
KEEP VERBATIM: Voronoi slabs, isostatic bob, bass rift, incandescent crack ramp, eruption spikes, heat haze, display-history A
ADD:
  1. Pillow rind — lumpy cooled lobes on the thermal margin between the crack and the obsidian
  2. Strike-slip striae — scratch grooves along the plate-slip direction, denser as tectonic stress rises
FORBID: a new creature, replacing the Voronoi crust, a spring overlay
A PACKING: ACES display RGBA (C read back as colour history)
```

```
SHADER: gen-luminescent-chrono-fluid-astrolabe
IDENTITY: geared astrolabe rings over a rete plate, ecliptic, and a cursor-led alidade
KEEP VERBATIM: limb graduations, gear train, almucantars, azimuths, stars, ecliptic and sun bead, alidade rule, spring, display-history A
ADD:
  1. Unequal-hour arcs — the seasonal hour curves engraved on the plate beside the almucantars
  2. Alidade shadow — a soft dark band offset from the sighting rule, so the bar sits above the chart
FORBID: a different instrument, removing the rete, a new spring
A PACKING: ACES display RGBA (C read back as colour history)
```

```
SHADER: gen-navier-stokes-ink
IDENTITY: semi-Lagrangian ink with vorticity confinement and sinking plumes, drawn as vortex tubes
KEEP VERBATIM: back-trace advection, viscosity mix, divergence clear, confinement, Boussinesq sink, click drops, tube corona, A = (vx, vy, ink, coverage)
ADD:
  1. Marangoni skim — ink lowers surface tension, so the velocity is pushed from dense ink toward clear water
  2. Coffee-ring rim — a pigment edge where the ink gradient is steep and the density is still moderate
FORBID: replacing the solver, ACES on the stored velocity, a new palette as the whole look
A PACKING: raw (vel.x, vel.y, ink density, coverage). ACES on writeTexture only.
```

```
SHADER: gen-magnetic-ferrofluid
IDENTITY: a mirror ferrofluid mass with Rosensweig peaks, labyrinth fingers, and Rayleigh ringing
KEEP VERBATIM: hex lattice, labyrinth mix while held, l=2/l=3 modes, softbox, droplet smin, spring orbit, display-history A
ADD:
  1. Secondary peak bifurcation — well above the critical field, each hex peak fattens into a pair
  2. Magnetite chains — thin dark streaks aligned with the applied field on the shaded surface
FORBID: a new creature, removing the lattice, tip-beads copied from ferrofluid-spikes
A PACKING: ACES display RGBA
```

```
SHADER: gen-auroral-ferrofluid-monolith
IDENTITY: a spiked ferrofluid monolith wrapped in a volumetric aurora
KEEP VERBATIM: spike SDF, aurora sheath, co-wound field, tip corona, cusp-knot whorls, substorm curtains, display A
ADD:
  1. Stable red arc — one monochromatic red band at a fixed magnetic latitude, separate from the green curtains
  2. Black-aurora lanes — narrow emission gaps cut through the curtains
FORBID: replacing the monolith, a second fluid solver, removing the substorm bands
A PACKING: ACES display RGBA
```
