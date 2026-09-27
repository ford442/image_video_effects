# Classic sim ten — 2026-09-27

Idea cards written before WGSL edits. Saved slider names and ranges stay. Plumbing is the floor.

```
SHADER: gen-wave-equation
IDENTITY: height/velocity wave solver with click droplets on a photo
KEEP VERBATIM: 9-point Laplacian, Klein-Gordon/sine-Gordon term, rising-edge droplets, extraBuffer[133] mouse edge, A = (height, velocity, energy, waveIntensity). Sliders Intensity / Speed / Scale / Detail.
ADD:
  1. dispersive biharmonic — Scale adds a ∇⁴ term so short ripples outrun long swells
  2. bathymetric refraction — wave speed follows readDepth so ripples bend over the photo
FLOOR: bass rain was max(bass-1, 0) and never fired; one-frame bass delta in extraBuffer[134] retriggers the existing beat droplet
FORBID: caustic ridges (wave-equation.wgsl), breaking foam (wave-equation-rgba-fluid), springs
A PACKING: raw sim state; ACES on the display mix only
```

```
SHADER: gen-stable-fluids-jos-stam
IDENTITY: one Jacobi step of Stam stable fluids (RG velocity, B pressure, A dye)
KEEP VERBATIM: semi-Lagrangian advection, viscosity mix, curl stir, mouse impulse, dye injection, pressure projection. Sliders Viscosity / Curl Strength / Dye Injection / Color Intensity.
ADD:
  1. vorticity confinement — curl-aligned force scaled by Curl Strength so eddies stay tight
  2. buoyancy — dye lifts velocity so injected dye rises
FLOOR: dataTextureC reads become textureLoad bilinear, not the filtering sampler
FORBID: RGB dye packing, a second Jacobi loop, obstacle rewrite
A PACKING: raw (vel.x, vel.y, pressure, dye); ACES on display only
```

```
SHADER: gen-turing-morphogenesis
IDENTITY: activator-inhibitor coat; Feed Rate picks spots, stripes, or labyrinth
KEEP VERBATIM: noise-field activator/inhibitor, feed/kill split, mouse deposit, 2026-09-15 inhibitor halo and chemical-front ridges. Sliders Feed Rate / Evolution Speed / Pattern Scale / Color Shift.
ADD:
  1. coat grain — stripe regime only, stripes follow the activator gradient
  2. slow domain patches — a larger inhibitor scale picks which existing window wins locally
FORBID: Gray-Scott state in A, springs
A PACKING: ACES display RGBA (color persistence)
```

```
SHADER: gen-von-karman-vortex
IDENTITY: analytic alternating point-vortex street behind the mouse obstacle
KEEP VERBATIM: vortex_field streamfunction and analytic velocity, ten pairs, obstacle disk, curl-noise warp. Sliders Flow Speed / Vortex Separation / Vortex Spacing / Colour Hue.
ADD:
  1. wake deficit — dark channel between the rows downstream of the obstacle
  2. alternating core pulse — top and bottom rows brighten out of phase at the shedding rate
FLOOR: bass envelope moves from extraBuffer[0] to extraBuffer[133]
FORBID: grid Navier-Stokes, a new spring
A PACKING: display RGBA trail blend
```

```
SHADER: gen-verlet-cloth-wind
IDENTITY: pinned 64×64 height cloth in wind, lit as fabric
KEEP VERBATIM: pin at y == 0, gust-front wind, thread-tension sheen, lattice (h, v) store. Sliders Wind Strength / Fabric Weight / Stiffness / Sheen.
ADD:
  1. hem lead — free edge, far from the pin, leads the body
  2. fold occlusion — concave neighborhoods darken; stretch sheen stays on slope
FORBID: full XY particle Verlet, a new spring
A PACKING: raw (h, v, 0, 0) on the 64×64 lattice; display RGBA elsewhere
```

```
SHADER: gen-string-theory
IDENTITY: five vibrating strings with partials and a pointer pluck
KEEP VERBATIM: five-string eval, harmonic loop, pluck profile, pointer spring extraBuffer[133..138], click rings. Sliders Fundamental Frequency / Harmonic Richness / Damping / Pluck Strength.
ADD:
  1. stiff-string inharmonicity — partials sharp of the integer series, amount tied to Harmonic Richness
  2. bridge reflection — the pluck image travels back from the far end
FORBID: another spring, more full-frame sine veils
A PACKING: ACES display RGBA
```

```
SHADER: gen-supernova-remnant
IDENTITY: stacked expanding shells, Rayleigh-Taylor fingers, temperature color, mouse gravity
KEEP VERBATIM: multi-shell loop, finger modulation, temperature ramp, mouse tug, blue shock ring. Sliders Explosion Energy / Shell Density / Turbulence/Chaos / Gas Opacity.
ADD:
  1. Sedov-Taylor slowdown — radius grows as age^(2/5) so outer shells bunch
  2. reverse-shock rim — thin hotter line on the inner edge of each shell
FLOOR: bounds guard, ACES display, dataTextureA display store (no field feedback)
FORBID: click-ripple shockwaves, blackbody rewrite of temperatureColor
A PACKING: display RGBA
```

```
SHADER: gen-topology-flow
IDENTITY: Morse height field with relief color, gradient streaks, peaks / valleys / saddles
KEEP VERBATIM: height FBM, relief lighting, contour lines, valley haze, existing particle loop, mouse stir. Sliders Flow Speed / Height Complexity / Particle Density / Trail Persistence.
ADD:
  1. real Morse index — Hessian determinant, not laplacian sign alone
  2. separatrix whiskers — short bright ticks along the saddle's unstable axis
FLOOR: delete extraBuffer[6..13] FFT read; contour shimmer uses plasmaBuffer treble
FORBID: a spring, a second particle family
A PACKING: linear/HDR history in A; ACES on writeTexture only
```

```
SHADER: gen-sonic-lava-flow
IDENTITY: curl-advected molten surface, Voronoi crust, Fresnel, Beer-Lambert glow
KEEP VERBATIM: curl velocity, domain-warped temperature, crust SDF, Fresnel, glow, video shimmer, mouse heat. Sliders Viscosity / Flow Speed / Crust Detail / Glow Intensity. Decay formula mix(0.8, 0.99, Crust Detail) stays.
ADD:
  1. cooling skin — crust thickens in slow flow and opens in shear; Crust Detail scales that contrast around 1 at default 0.5
  2. pahoehoe ropes — crust Voronoi stretched along the flow
FLOOR: ACES on writeTexture; A stays linear color history
FORBID: volcanic-ink fissures, packing temperature into A
A PACKING: linear display history in A
```

```
SHADER: gen-volcanic-ink
IDENTITY: dark ink torn by fissures, with magma, soot, and embers
KEEP VERBATIM: fissure fbm, lava body, soot, blue-noise embers, ink trail, dataTextureB field dump. Sliders Fissure Density / Magma Flow / Soot / Ember Intensity.
ADD:
  1. capillary ink margin — a wider dark wet edge around each hot crack
  2. cooling rind — lava off the cracks skins darker and still advects with Magma Flow
FLOOR: neighbor blur uses textureLoad, not the filtering sampler
FORBID: sonic-lava Voronoi crust, a new spring, ideas that read B
A PACKING: linear ink trail in A; ACES on display; B store unchanged
```
