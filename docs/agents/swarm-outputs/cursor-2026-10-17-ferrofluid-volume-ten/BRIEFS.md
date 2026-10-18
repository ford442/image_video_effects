# Idea Cards — ferrofluid → volume ten (2026-10-17)

Written before WGSL. Prior ideas stay. Two new native ideas each. No shared overlay.

```
SHADER: ferrofluid-spikes
IDENTITY: Rosensweig spike lattice under a moving magnet, lit as dark metal
KEEP VERBATIM: hexagonal peak family, magnet spring, eruption packets, GGX lighting, viscous C trail, saved magnet/density/viscosity/highlight
ADD:
  1. valley pool — fluid drawn into the spikes leaves a darker meniscus in the lattice valleys
  2. tip bead — the tallest peaks carry a small chrome bead above the existing height glow
FORBID: a new creature, a second palette family, rewiring the four sliders
A PACKING: pre-ACES HDR history RGBA (writeTexture is ACES, premultiplied)
```

```
SHADER: gen-quantum-entangled-ferrofluid-engine
IDENTITY: metallic ferrofluid body whose spikes follow |ψ|², with entangled satellite pairs
KEEP VERBATIM: wavefunction spikes, Rosensweig lattice, pair filaments, nodal contours, ACES display history
ADD:
  1. measurement scar — the mouse collapse brightens a local specular on the metal
  2. pair neck — the midpoint between an entangled satellite pair holds a meniscus
FORBID: replacing the SDF with a different engine; ACES inside a raw field
A PACKING: ACES display RGBA
```

```
SHADER: gen-sentient-ferro-silicate-swarm
IDENTITY: chrome beads that lock into a quartz lattice with Si-O struts
KEEP VERBATIM: assemble breath, facet lock, bond struts, curl wake, display RGBA in A
ADD:
  1. fluid inclusions — locked beads hold a dark bubble, the way quartz traps liquid
  2. shatter dust — bass that unlocks a cell throws a speck of silicate grit
FORBID: replacing the swarm with a new creature
A PACKING: ACES display RGBA (alpha = swarm occupancy)
```

```
SHADER: gen-magnetic-ferrofluid-sculpture
IDENTITY: raymarched ferrofluid sculpture with spikes, Taylor cones, and dipole chains
KEEP VERBATIM: cone lean, pinch-off droplets, dipole chains, thin-film bands, ACES display RGBA
ADD:
  1. contact meniscus — a bright ring where each spike meets the bulk sphere
  2. magnetite grain — dark specks of suspended particles in the metal
FORBID: a new sculpture motif
A PACKING: ACES display RGBA
```

```
SHADER: volumetric-cloud-nebula
IDENTITY: raymarched nebula with a light-echo shell, dark cores, and warp-flight stars
KEEP VERBATIM: Beer-Lambert march, echo shell, absorbing cores, star streaks, display history in A
ADD:
  1. silver lining — medium-density gas on the cloud edge re-emits a pale rim
  2. virga — dense knots shed a faint downward veil
FORBID: a different skybox or a spring cursor
A PACKING: ACES display RGBA
```

```
SHADER: liquid-warp
IDENTITY: RK4 liquid warp of the photo, with strain folds and click vortex rings
KEEP VERBATIM: RK4 departure, Cauchy-Green stretch, fold caustics, ring impulse, raw velocity in A
ADD:
  1. stretch threads — fine ridges follow the existing principal axis where the fluid is pulled thin
  2. vortex eye — high vorticity darkens a core so the spin reads as a hole
FORBID: replacing the photo warp with a generative scene; tone-mapping the stored velocity
A PACKING: raw velocity.xy, displacement, vorticity (B keeps shear telemetry)
```

```
SHADER: gen-neuro-fluid-plasma-lotus
IDENTITY: plasma lotus with phyllotaxis florets, flux ropes, veins, and reconnection plumes
KEEP VERBATIM: 8/13 florets, MHD ropes, capillary veins, click plumes, ACES display RGBA
ADD:
  1. anther pollen — dust specks sit in the valleys between florets
  2. petal scallop — the existing eight-petal crests catch a bright margin
FORBID: a different flower or a new solver
A PACKING: ACES display RGBA
```

```
SHADER: gen-rainbow-smoke
IDENTITY: curl-noise smoke with Mie cores, Rayleigh edges, vortex rings, and KH billows
KEEP VERBATIM: CFL clamp, spectral emitters, rings, KH edge, raw velocity/density/temperature in A
ADD:
  1. soot cap — hot smoke at the top of the plume darkens
  2. ash fall — cooled density settles as a grey skirt along the downward side
FORBID: replacing the smoke solver; ACES on the stored fields
A PACKING: raw (velocity.xy, density, temperature)
```

```
SHADER: quantum-foam-pass1
IDENTITY: pass 1 of the foam graph; it writes warp, pattern, and cell boundary for later passes
KEEP VERBATIM: curl layers, voronoi hybrid, three-wave interference, packing (warp.xy, pattern, cellBoundary)
ADD:
  1. diffused voids — cell centers become holes whose radius follows Diffusion Rate
  2. wavefront ridges — constructive interference of the three waves raises the cell boundary
FORBID: changing the four-channel packing or tone-mapping the field
A PACKING: raw warpX, warpY, pattern, cellBoundary (pass 2 reads these roles)
```

```
SHADER: volumetric-depth-zoom
IDENTITY: five depth slices of the photo with DOF, parallax, and fog
KEEP VERBATIM: five-slice march, focal plane from foreground speed, parallax, fog, edge specular
ADD:
  1. slice drift — foreground and background slices scroll at their own saved speeds
  2. focal sheet — a pale plane of light sits on the current focal depth
FORBID: a generative replacement of the photo; writing lighting state into extraBuffer[0..132]
A PACKING: display RGBA on writeTexture only (no A history)
```
