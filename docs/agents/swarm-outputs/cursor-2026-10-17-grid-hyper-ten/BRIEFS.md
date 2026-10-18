# Idea Cards — grid → hyper ten (2026-10-17)

Written before WGSL. Second pass: September / 10 October ideas stay. Two new native ideas each. No shared spring / ripple / IQ stamp.

```
SHADER: gen-grid
IDENTITY (one sentence): domain-warped FBM lattice with moiré sub-grids, chromatic edges, and a mouse gravity well
KEEP VERBATIM: domainWarp FBM, gridLine H/V, Jacobian stretch, chromatic dispersion, recursive mini-grid, intersection phosphor from C, spring attractor, click warp pulses, saved warp/density/thickness/palette
ADD (2–4 native ideas):
  1. cell-field wash — each lattice cell keeps a stable interior tint so the grid reads as a field of tiles, not only strokes
  2. Jacobian crease — where the existing warp stretch ratio folds, a bright ridge sits on the anisotropic lines
FORBID on this file: a new motif (fluid, fractal creature), rewiring the four sliders
A PACKING: ACES display RGBA
```

```
SHADER: gen-grok4-life
IDENTITY (one sentence): two-species SmoothLife with Lotka–Volterra predator-prey
KEEP VERBATIM: Rafler annular kernel, birth/survival intervals, hunt-front gradient term, age ramp, edge-flash activity, extinction bloom, raw A = prey/predator/age/activity
ADD:
  1. carrying dimple — dense prey interiors darken on the display where the inner average nears capacity
  2. phase-portrait tint — coexistence hue follows atan2(predator, prey) so the orbit reads across the front
FORBID on this file: replacing SmoothLife with Conway cells or a Gray-Scott costume; ACES on stored fields
A PACKING: raw prey/predator/age/activity (never ACES)
```

```
SHADER: gen-grok4-perlin
IDENTITY (one sentence): stratified erosion terrain with sediment, water table, and wind
KEEP VERBATIM: hydraulic incision, hardness layers, seismic uplift, bedding terraces, shoreline foam, raw A = erosion/sediment/water/uplift
ADD:
  1. talus apron — deposited sediment skirts the base of steep slopes
  2. drainage rills — thin downhill channels follow the existing height gradient
FORBID on this file: a new biome (city, crystal garden); tone-mapping the stored fields
A PACKING: raw erosion, sediment, water, uplift
```

```
SHADER: gen-grok41-mandelbrot
IDENTITY (one sentence): Buddhabrot orbit accumulation with a Mandelbrot body under the nebula
KEEP VERBATIM: escaping-orbit histogram, orbital rainbow, set body, dwell bands, spectral stars, linear RGB accumulation in A
ADD:
  1. slow-escape comet — long orbits tint their contribution warm so filaments read as dwell comets
  2. antenna tip — a bright knot at the real-axis spike (c ≈ −1.75) anchors the classic silhouette
FORBID on this file: switching the map to Julia-only or a Mandelbox; ACES inside the history buffer
A PACKING: linear RGB accumulation + presence (ACES display only)
```

```
SHADER: gen-grok41-plasma
IDENTITY (one sentence): spherical-harmonic gas giant with jets, storms, and a Rayleigh limb
KEEP VERBATIM: Ylm coefficients and normalizations, zonal jets, Worley storm eye, lightning, raw A = pattern/storm/limb/validity
ADD:
  1. polar hood — high-latitude haze from |cos θ| so the poles read as a separate cap
  2. belt boundaries — zero-crossings of the existing jet sine darken into stripe edges
FORBID on this file: replacing Ylm with a different planet shader; ACES on the telemetry write
A PACKING: raw pattern, stormMask, limbT, validity
```

```
SHADER: gen-grokcf-interference
IDENTITY (one sentence): circular membrane whose Bessel modes draw Chladni figures
KEEP VERBATIM: J0–J3 modes, audio family weights, radial vs azimuthal node tint, displacement Lambert, mallet strikes, raw A = u/r/phi/alpha
ADD:
  1. antinode disks — soft peaks where |u| is large and away from the node lines
  2. radial beat — the (0,1)/(0,2) difference frequency breathes the radial family
FORBID on this file: replacing Bessel modes with a plate FEM or a generic oscillator overlay
A PACKING: raw u_total, r, phi/2π, blendAlpha
```

```
SHADER: gen-grokcf-voronoi
IDENTITY (one sentence): animated Worley cells with thin-film walls, nuclei, and crack ridges
KEEP VERBATIM: F1/F2 Worley, nucleus at the site, F2−F1 crack, per-cell starfield, edge afterglow, A = cell id / edge / F1
ADD:
  1. site comet — the drifting feature point leaves a short tail opposite its existing drift
  2. triple junctions — Voronoi vertices where F1≈F2≈F3 flare brighter than the wall ridge
FORBID on this file: swapping Worley for a Voronoi SDF crystal or a Gray-Scott interior
A PACKING: cell id xy, edge mask, F1 (telemetry)
```

```
SHADER: gen-hopf-fibration-fiber-bundle
IDENTITY (one sentence): Hopf fibers as linked circles, with knot gaps, phase beads, and an S² inset
KEEP VERBATIM: stereographic Hopf map, over/under gaps, U(1) beads, base-space inset, denominator horizon, transverse hot crossings, ACES display RGBA
ADD:
  1. equatorial generator — the fiber over θ≈0 is the brighter reference circle of the Hopf link
  2. longitudinal phase seam — a double-angle stripe on each fiber so the circle reads as a ruled tube
FORBID on this file: a new 4D object (tesseract, Klein bottle); a second spring
A PACKING: ACES display RGBA
```

```
SHADER: gen-hyper-labyrinth
IDENTITY (one sentence): raymarched 4D gyroid maze with neon veins and a W-slice tint
KEEP VERBATIM: gyroid SDF, 4D XW rotation, midline zero-ridge, W-slice hue, volumetric glow, neon history in A
ADD:
  1. cul-de-sac chambers — warm pools where the gyroid gradient vanishes on the wall
  2. floor treads — surfaces facing world-up darken into worn walkways
FORBID on this file: replacing the gyroid maze with a different SDF scene
A PACKING: raw HDR neon RGB + semantic alpha (ACES display only)
```

```
SHADER: gen-hyper-warp
IDENTITY (one sentence): layered domain warp with fold caustics, flow stretch, etched isolines, and prismatic history
KEEP VERBATIM: q/r fBm warp, palette mix, fold caustic, stretch, level-set etch, flow-dispersed C loads, pre-ACES history in A
ADD:
  1. radial flux — outflow along the existing flow vector brightens, inflow darkens
  2. octave grit — the finest noise octave of the warped field reads as surface grain
FORBID on this file: a new creature or a spring cursor; tone-mapping the stored history
A PACKING: raw HDR history RGBA (pre-ACES chromatic color, coverage alpha)
```
