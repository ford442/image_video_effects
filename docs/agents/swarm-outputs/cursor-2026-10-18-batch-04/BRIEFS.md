# Cursor batch-04 — Idea Cards

Written before WGSL edits. 2026-10-18.

```
SHADER: aurora-rift-pass1
IDENTITY: curl-flow volumetric aurora handed to pass 2 as color plus density
KEEP VERBATIM: curl parallax layers, Voronoi foam, 4D noise, interference, Birkeland curtain folds, OI 557.7 / OI 630.0 / N2+ 427.8 emission, diffusion-rate temporal mix, A = (color, density), video passthrough on writeTexture
ADD:
  1. Rayed beads — bright knots that climb the existing curtain striations
  2. Dark gap — a narrow emission break under the curtain, the gap above the horizon glow
FORBID: a second solver, ACES on the stored color/density, STEVE (that belongs on aurora-rift-2 pass 2)
A PACKING: raw volumetric (RGB = aurora color, A = density). Pass 1 does not tone-map A.
```

```
SHADER: aurora-rift-pass2
IDENTITY: atmospheric grade of the pass-1 aurora over the photo — dispersion, quaternion hue, spectral power, haze, vignette, ACES
KEEP VERBATIM: chromatic dispersion, quaternion rotate, spectral power, sky haze, grade, vignette, ACES on the display only
ADD:
  1. Airglow limb — a thin green band near the horizon, thickness from Scale, drift from Flow Speed
  2. Rayleigh reddening — the long path toward the horizon strips blue and leaves red; FBM Octaves sets the fine haze
FORBID: a new raymarch, writing graded RGB into A (that would erase pass 1's density), click springs
A PACKING: A echoes the volumetric handoff (aurora color, density) so pass 1's next frame still reads a field. Display ACES is writeTexture only.
```

```
SHADER: aurora-rift-2-pass1
IDENTITY: the second aurora volume — vortex tubes, substorm flashes, and a diffusion smear of the previous field
KEEP VERBATIM: curl parallax, foam, hyper-noise, interference, Birkeland vortex tubes, substorm ripple flashes, diffusion mix, A = (color, density), video passthrough
ADD:
  1. Omega band — an equatorward tongue of luminosity that folds along a slow east-west wave
  2. Picket fence — a row of narrow vertical rays on the poleward edge, separate from the helical tubes
FORBID: copying pass 1's curtain beads and dark gap, replacing the HSV aurora, ACES on A
A PACKING: raw volumetric (RGB = aurora color, A = density)
```

```
SHADER: aurora-rift-2-pass2
IDENTITY: the second aurora's grade — dispersion, quaternion hue, purple sky, vignette, ACES
KEEP VERBATIM: chromatic dispersion, quaternion rotate, spectral power, dual glow haze, grade, vignette, ACES on the display only
ADD:
  1. STEVE arc — a narrow mauve east-west ribbon, width from Scale, drift from Flow Speed
  2. Nitrogen pink border — a 427.8 nm pink fringe where the density meets the lower sky
FORBID: the green airglow limb (that belongs on aurora-rift pass 2), writing graded RGB into A
A PACKING: A echoes the volumetric handoff (aurora color, density). Display ACES is writeTexture only.
```

```
SHADER: gray-scott-tank
IDENTITY: Gray–Scott U/V in a tank — Jacobi step, hold-paint and click inject, HSV render of V
KEEP VERBATIM: feed/kill/diffusion/seed slider roles, 5-point Laplacian, dt, hold disk, click spots, A = (U, V, age, seed mask) on every node, ACES only in the render's writeTexture
ADD:
  1. Tangent stretch — extra diffusion of V along the concentration tangent, so worms elongate
  2. Feed shadow — high V locally starves the feed, so a spot's center hollows into a ring
  3. Paint comet — the held brush stretches behind the pointer
  4. Iso-V threads — hairlines where V crosses two fixed concentrations, drawn in the render
FORBID: a new palette family, replacing Gray–Scott, ACES on the stored U/V, contour-stretch stolen from the video RD shader
A PACKING: raw (U, V, age, seed mask) on step, inject, and render
```

```
SHADER: liquid-viscous
IDENTITY: incompressible Navier–Stokes dye — midpoint advection, vorticity confinement, local Jacobi pressure
KEEP VERBATIM: viscosity / turbulence(confinement) / ripple(injection) / color-shift roles, shared stencil, streamline diffusion, Reynolds transition, per-band dye, audio vortices, click rings, A = (velocity, dye, pressure), B = diagnostics
ADD:
  1. Ekman veer — viscosity turns the velocity a few degrees with picture depth, so dye paths spiral
  2. Filament beads — Rayleigh–Plateau pearls along quiet dye threads, stronger as viscosity drops
FORBID: replacing the projection, ACES on the stored velocity, a second Gray–Scott field
A PACKING: raw (velocity.xy, dye, pressure). Display ACES is writeTexture only. B stays the diagnostic pack.
```

```
SHADER: gen-superfluid-quantum-foam
IDENTITY: raymarched bubble foam with film drainage, a Kelvin vortex line, and second-sound fronts
KEEP VERBATIM: sphere lattice, smooth-min necks, black-film pop, Kelvin core and 1/r swirl, second sound, reconnection sparks, click cavitation, existing spring, premultiplied display history
ADD:
  1. Abrikosov dimples — a shallow triangular dent in each bubble when the vortex radius is up, the flux lattice pressed into the foam
  2. Andreev sheen — a cool counterflow rim on the silhouette, where excitations bounce off the superfluid
FORBID: a different creature, removing the film cycle, a new spring
A PACKING: ACES display RGBA, premultiplied (col*alpha, alpha). C is read back as colour history.
```

```
SHADER: gen-gravitational-ferrofluid-singularity-engine
IDENTITY: a ferrofluid sphere orbiting a black-hole horizon, with Rosensweig crests and a photon-ring sheen
KEEP VERBATIM: sphere SDF, angular×radial spikes, Rosensweig crest specular, horizon disc, photon-ring sheen, droplets, click rings, display-history advection
ADD:
  1. Frame-dragging lean — Lense–Thirring winds the inner spikes tighter than the outer ones; viscosity resists
  2. ISCO hot ring — a thin amber orbit outside the photon ring, brightening with bass
FORBID: replacing the ferrofluid SDF with a plain disk, a second creature, ACES on a sim field (A is display)
A PACKING: ACES display RGBA (C read back as colour history)
```

```
SHADER: hyper-tensor-fluid-coupled
IDENTITY: a photo-edge structure tensor that steers a viscous fluid the pointer stirs
KEEP VERBATIM: structure-tensor eigenflow, semi-Lagrangian velocity and density, mouse stir and vortex, click bursts, edge damping, A = (velocity, vorticity, density) with the pointer stashed at (0,0)
ADD:
  1. Weissenberg pile-up — density thickens on the tensor edge, the fluid climbing the image contour
  2. Die swell — downstream of an edge the flow spreads along the minor axis, the jet widening as it leaves the contour
FORBID: replacing the tensor with a Gray–Scott field, ACES on the stored velocity, a spring overlay
A PACKING: raw (velocity.xy, vorticity, density). Display ACES is writeTexture only. Pixel (0,0) remains the pointer stash.
```

```
SHADER: wave-equation-rgba-fluid
IDENTITY: a 2D wave equation coupled to a dye, with breaking foam on steep downhill faces
KEEP VERBATIM: c² laplacian, damping, viscosity, source, pressure Jacobi, mouse and ripple injection, foam, dye stretch, A = (height, wave velocity, pressure, dye)
ADD:
  1. Stokes drift — dye walks a little farther in the wave direction, second-order in amplitude
  2. Capillary precursors — short ripples on the uphill face, ahead of the break
FORBID: replacing the wave equation, ACES on the stored height, the seiche envelope that belongs to liquid-optimized
A PACKING: raw (height, velocity, pressure, dye). Display ACES is writeTexture only.
```
