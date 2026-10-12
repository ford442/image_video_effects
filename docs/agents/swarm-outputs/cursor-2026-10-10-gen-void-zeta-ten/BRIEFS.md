# Idea Cards — void → zeta ten

Written 2026-10-10 before WGSL edits. Second pass on the September upgrades.
September ideas stay. Saved `params` stay byte-exact. No shared spring / ripple / IQ stamp.

```
SHADER: gen-void-harmonic-cymatic-resonator
IDENTITY: a spherical standing-wave resonator with Chladni sheets and splitting-mode seams
KEEP VERBATIM: standingWave, splitModes, sphere shell, nodal march, slider roles (frequency, amplitude, glow, complexity)
ADD:
  1. antinode bellies — bright lobes where the same pressure field peaks, the complement of the nodal zeros
  2. Helmholtz throat — a bass-flared ring at the shell, the resonator mouth
FORBID: a new spring, replacing the march with a 2D plate
A PACKING: ACES display RGBA
```

```
SHADER: gen-volcanic-ink
IDENTITY: ink-black fissures with flowing lava, soot, and embers
KEEP VERBATIM: fissure fbm, lava field, capillary margin, cooling rind, A = linear trail, B = (lava, cracks, ember, smoke), slider roles (fissure, flow, soot, ember)
ADD:
  1. pahoehoe ropes — folded ridges on the lava body, advected by the same magma flow
  2. vesicles — round gas holes punched in the cooling rind
FORBID: ACES on A, dropping the B write, a new spring
A PACKING: linear ink trail in A; ACES on display; B stores (lava, cracks, ember, smoke)
```

```
SHADER: gen-von-karman-vortex
IDENTITY: an analytic vortex street behind a mouse obstacle, with a dark wake and alternating cores
KEEP VERBATIM: point-vortex streamfunction, curl warp, wake deficit, core_pulse, bass slot 133, slider roles (speed, separation, spacing, hue)
ADD:
  1. boundary-layer skin — a thin bright coat on the cylinder the street already sheds from
  2. recirculation bubble — a short closed eddy just downstream, before the far wake channel
FORBID: replacing the analytic street with curl noise only, a new spring
A PACKING: display RGBA (trail blend)
```

```
SHADER: gen-vortex-cathedral
IDENTITY: a spinning vault of arches, stained glass, a second counter-rotating ring, and god rays
KEEP VERBATIM: arch sector, stainedGlass piers, second vault, god rays, slider roles (arch count, spin, haze, sanctum)
ADD:
  1. rib groins — stone lines where adjacent arch sectors meet
  2. rose window — a radial rosette scaled by the sanctum radius
FORBID: a new spring, replacing the vault with a particle galaxy
A PACKING: ACES display RGBA
```

```
SHADER: gen-wasm-hls-physarum-swarm
IDENTITY: Eulerian slime with heading-coded mass, peristaltic veins, and a foraging front
KEEP VERBATIM: sense/deposit, A = (trail, mx, my, hue), peristalsis, tube shade, front colour, slider roles (angle, distance, decay, deposit)
ADD:
  1. fusion knots — bright nodes where trails are thick but headings cancel
  2. spent sheath — older trail behind the front reads duller
FORBID: writing display color into A, extraBuffer agent state (the rescue forbids it)
A PACKING: raw sim (trail, mx, my, hue); ACES on writeTexture only
```

```
SHADER: gen-wave-equation
IDENTITY: a height/velocity wave solver with short-wave dispersion and depth-dependent speed
KEEP VERBATIM: 9-point Laplacian, biharmonic term, bathymetry speed, droplet rising edge, A = (height, velocity, energy, waveIntensity), slider roles (intensity, speed, scale, detail)
ADD:
  1. crest caustics — bright focus lines under steep crests, display only
  2. whitecaps — foam where height and velocity are both large
FORBID: ACES or colour in A, changing the stored height/velocity meaning
A PACKING: raw sim (height, velocity, energy, waveIntensity); ACES on the display mix only
```

```
SHADER: gen-worley-cellular-noise
IDENTITY: Worley tissue with membrane fringes, turgor domes, and triple junctions
KEEP VERBATIM: F1/F2/F3 field, membrane aberration, turgor, triple nodes, A = (f1+drift, boundary, scatter, alpha), slider roles (scale, speed, aberration, organic)
ADD:
  1. nucleus — a dark disk at the feature point, inside the turgor dome
  2. plasmodesmata — organic noise punches thin bright pores through the wall
FORBID: writing display RGB into A, a new spring
A PACKING: (f1+drift, F2−F1 boundary, wall scatter, alpha); C.g feeds drift
```

```
SHADER: gen-xeno-botanical-synth-flora
IDENTITY: branching synth plants with veined leaves, conductive filaments, and click spores
KEEP VERBATIM: branch density, leaf SDF, midrib/laterals, filaments, phototropism, spore spray, slider roles (density, bloom, circuit glow, glow spread)
ADD:
  1. stomata — scattered pores on the blade, off the vein mask
  2. prickles — short spines on the branch ridge, separate from the conductive filament
FORBID: a new creature, a new spring
A PACKING: ACES display RGBA
```

```
SHADER: gen-xeno-mycelial-resonance-web
IDENTITY: a folded hyphal web with septal rings, anastomosis blends, and click thickening
KEEP VERBATIM: KIFS fold, septal constrictions, anastomosis smin, click thicken, slider roles (repetition, branch size, hue, pulse)
ADD:
  1. medulla — a darker core down the tube, where the view looks through the middle
  2. spitzenkörper — a bright tip where the surface faces outward along the fold
FORBID: replacing the march, a new spring
A PACKING: ACES display RGBA
```

```
SHADER: gen-zeta-function-landscape
IDENTITY: a Dirichlet-eta landscape of |ζ| with zero rails, |ζ|=1 contours, critical sheen, and argument ticks
KEEP VERBATIM: zetaEta, known-zero rails, iso-contours, critical sheen, arg ticks, slider roles (sigma, t range, height, terms)
ADD:
  1. real and imaginary nodal walls — Re(ζ)=0 and Im(ζ)=0 sheets, crossing on the zeros
  2. prime beat — a slow cos(t ln 2) brightness from the first Euler factor
FORBID: a different special function, a new spring
A PACKING: ACES display RGBA
```
