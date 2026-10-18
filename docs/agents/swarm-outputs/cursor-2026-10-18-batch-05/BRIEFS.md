# Cursor batch-05 — Idea Cards

Written before WGSL edits. 2026-10-18.

```
SHADER: fabric-of-reality
IDENTITY: a pinned mass-spring cloth — hold to tear, Self Heal knits, the photo rides the weave
KEEP VERBATIM: Verlet (pos, prev pos), top-row pin, gravity curve, mouse push/rip, wind, 4-neighbor Jacobi, tear threshold, self-heal, B = (strain, tear, weave phase, debris age), SSS and spotlight, render commits positions to A
MECHANISM INTERROGATION:
  tactic 1: the Jacobi step is structural springs only; a cloth also has shear (bias) springs
  tactic 2: gravity on a pinned sheet hangs as a catenary, and a tear frays
  tactic 3: strain is computed and then only tints; it should open the yarn gaps
  tactic 6: C is the position pair; exact loads, no new field
ADD:
  1. Shear springs — diagonal Jacobi constraints at half stiffness, and the tear mask measures those diagonals
  2. Catenary tension — gravity also pulls each node back toward its rest column
  3. Open weave and frayed ends — strain separates warp and weft; a torn cell grows loose yarns
FORBID: a new solver, ACES on the stored positions, a spring cursor (the hold already rips)
A PACKING: A = (position.xy, previous.xy) on verlet, constraint, and the render commit. B = (strain, tear, weave phase, debris age). Display ACES is writeTexture only.
```

```
SHADER: digital-glitch-pass1
IDENTITY: the glitch field — block shifts, scan tears, bitwise corruption, a spring hotspot
KEEP VERBATIM: corruption and bit-manipulation roles, byte corruptors, block shift, spring, held intensify, capped ripples, A = (displacedUV.xy, intensity, blockSeed)
MECHANISM INTERROGATION:
  tactic 2: a digital tear latches like a tracking error, it does not re-roll every frame
  tactic 6: C.rg is last frame's displaced UV, so the block can carry that motion
ADD:
  1. Macroblock motion carry — this frame's shift inherits last frame's displacement; Error Propagation sets the carry, Decay Rate lets it go
  2. Schmitt-trigger scan tear — the tear stays while the previous intensity is high and releases below a lower seed
FORBID: thin-film, a second tear system, ACES on the stored field, plasmaBuffer past [0]
A PACKING: raw (displacedUV.xy, intensity, blockSeed). No ACES on A.
```

```
SHADER: digital-glitch-pass2
IDENTITY: the glitch composite — bit flips, neighbor error bleed, bit-depth decay, block invert, scanlines
KEEP VERBATIM: field read from C, neighbor mix, bit-depth decay, symmetric chroma split, invert blocks, scanlines, vignette, ACES, no A write
MECHANISM INTERROGATION:
  tactic 2: composite video smears chroma behind luma; a codec quantizes the block residual
  tactic 5: Bit Manipulation is the codec knob and was unread on this pass
ADD:
  1. Chroma delay line — luma stays, chroma is sampled late along x; Error Propagation is the delay
  2. Block residual quantization — the local mean is kept, the residual is stepped; Bit Manipulation is the step
FORBID: replacing the byte flips, writing A (that would erase pass 1's field), an IQ palette
A PACKING: does not write A. C is pass 1's field. Display ACES is writeTexture.
```

```
SHADER: pyramid-downsample-pass1
IDENTITY: the pyramid's Gaussian base, a shared-memory low pass handed to the next passes as the blur
KEEP VERBATIM: 18×18 tile, 3×3 binomial weights, original image on writeTexture, blur stored in B, slider roles (high / mid / low / ROI radius)
MECHANISM INTERROGATION:
  tactic 1: the box-like binomial bleeds across edges; a range weight is the next approximation of the same low pass
  tactic 6: B is the blur and becomes C; the base can settle against last frame's blur
ADD:
  1. Bilateral range weight — luma agreement multiplies the existing binomial taps; High Freq Amp tightens the range so edges stay out of the base
  2. Low-band settle — the blur eases toward last frame's blur; Low Freq Amp sets how much inertia the base keeps
FORBID: a second pyramid, neon on this pass, writing the processed picture into B
A PACKING: B = (bilateral blur RGB, range agreement). Pass 2 must not write A, or A would replace this blur in C.
```

```
SHADER: pyramid-bandprocess-pass2
IDENTITY: Laplacian bands — neon on the high residual, bass hue on the mid, a slow breath on the low
KEEP VERBATIM: high = original − blur, neon edges, bass hue rotation, low LFO saturation and lightness, reconstruction mix, slider roles
MECHANISM INTERROGATION:
  tactic 1: boosting the residual rings; an anti-halo clamp is the same boost, bounded by the neighborhood
  tactic 2: a Laplacian edge throws a chromatic fringe along its gradient
  tactic 6: C must stay the blur; this pass was writing display into A, and A wins the copy
ADD:
  1. Anti-halo envelope — the residual boost is clamped to the local min and max of the photo
  2. Edge-directed chroma fringe — red and blue split along the photo gradient, scaled by High Freq Amp
FORBID: an ROI (that is pass 3), a spring, writing A
A PACKING: does not write A or B. C is the previous blur. Display is writeTexture.
```

```
SHADER: pyramid-composite-pass3
IDENTITY: the same pyramid inside a mouse magnifying glass, with a bright rim
KEEP VERBATIM: inner loud bands, outer quiet bands, mouse centre, ROI radius, luminous ring, slider roles
MECHANISM INTERROGATION:
  tactic 2: a magnifying glass actually enlarges; this one only turned the filter up
  tactic 5: a glass rim disperses
ADD:
  1. Glass magnification — inside the circle the photo and the blur are sampled closer to the cursor
  2. Rim dispersion — the existing ring splits red and blue along its radius
FORBID: a new palette, click shockwaves, writing A or B
A PACKING: display only. Does not write A or B. C is the blur.
```

```
SHADER: gen-magnetic-dipole-field
IDENTITY: a dipole with gyro particles, an auroral oval, Van Allen belts, and a magnetopause
KEEP VERBATIM: analytic dipole, gyro-helix and loss cone, oval, belts, bow shock, ghost dipole, motion-blur history, planet disc, slider roles
MECHANISM INTERROGATION:
  tactic 2: iron filings clump along a line; two dipoles cancel at a null
  tactic 3: stream_val and the ghost dipole are already computed
ADD:
  1. Iron-filing clumps — the existing field line breaks into beads along its stream coordinate
  2. Magnetic null — a bright X where this dipole and the ghost cancel, drawn after the history smear
FORBID: a new creature, removing the oval or the belts, a second palette family
A PACKING: ACES display RGBA in A (unchanged)
```

```
SHADER: gen-ethereal-chrono-fluid-symbiote
IDENTITY: a raymarched fluid mass sharing a body with a crystal, with a seam film and a chrono smear
KEEP VERBATIM: fluid and crystal SDFs, smin, meniscus, veins, twinning planes, chrono smear from C, slider roles
MECHANISM INTERROGATION:
  tactic 3: the march already counts steps and throws the count away
  tactic 2: Chrono Warp is a clock; the fluid should show age shells, not only a history mix
ADD:
  1. Step-count ambient occlusion — longer marches darken the hit the ray already found
  2. Chrono shells — faint age bands on the fluid, spaced by Chrono Warp
FORBID: a different creature, a liquid solver, a new spring
A PACKING: ACES display RGBA; C is the previous display frame
```

```
SHADER: gen-stable-fluids-jos-stam
IDENTITY: Stam stable fluids — semi-Lagrangian velocity, Jacobi pressure, dye, confinement, buoyancy
KEEP VERBATIM: viscosity / curl / dye / color roles, semi-Lagrangian velocity, diffusion mix, one Jacobi pressure step, projection, confinement, buoyancy, baroclinic jets, enstrophy shimmer, A = (vel.xy, pressure, dye)
MECHANISM INTERROGATION:
  tactic 1: the dye backtrace is first-order; MacCormack is the next correction on that same sample
  tactic 2: the box has no walls; viscosity should stick the fluid to the frame
ADD:
  1. MacCormack dye — forward sample plus a half-step correction, clamped to the neighborhood
  2. No-slip walls — velocity fades at the frame edge, stronger as Viscosity rises
FORBID: replacing the projection, ACES on the stored velocity, a second confinement term
A PACKING: raw (vel.x, vel.y, pressure, dye). ACES on display only.
```

```
SHADER: fire_smoke_volumetric
IDENTITY: a flame column with rising smoke, embers, and a heat spring under the pointer
KEEP VERBATIM: temperature gradient, Worley embers, exact-load smoke advection, ignition rings, Beer slab, depth alpha, spring, A = (smoke RGB, density)
MECHANISM INTERROGATION:
  tactic 2: hot gas rises faster than the cool smoke, and the smoke above the flame is soot
  tactic 3: fireShape already has an edge; that edge is the red fringe of a real flame
ADD:
  1. Buoyancy lift — the existing upward advection is stronger in the hot core, scaled by Fire Intensity
  2. Soot cap — advected density darkens above the flame
  3. Red fringe — the silhouette edge, where fireShape is halfway, tints toward red
FORBID: a new solver, ACES on the stored smoke, a second spring
A PACKING: raw smoke RGB plus density in A. ACES on writeTexture only.
```
