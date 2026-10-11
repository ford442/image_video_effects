# Mid twelve — idea cards (written before WGSL)

Twelve shaders that still paste a binding header and were last upgraded in September, outside the October 10–11 batches.

```
SHADER: gen-acid-lissajous
IDENTITY: nested Lissajous figures with a moving phase
KEEP VERBATIM: strand frequencies, origin beads, 1:1 waist, cusp dwell, 2:1 lobe split, four sliders
ADD:
  1. pen head — a bright point at the current phase, the part of the curve being drawn now
  2. beat envelope — brightness breathes at |freqX−freqY| when the ratio is close
FORBID: epicycle gears, fireworks
A PACKING: ACES display RGBA
```

```
SHADER: gen-apollonian-gasket
IDENTITY: inverted circle packing with seed rims and tangent kisses
KEEP VERBATIM: five seed circles, inversion count, curvature tint, generation stipple, kisses
ADD:
  1. interior wash — a faint fill inside each seed circle, stronger in the larger ones
  2. soddy spark — a bright center in the smallest seed circle
FORBID: a new fractal family
A PACKING: linear RGB + alpha (ACES on display)
```

```
SHADER: gen-barnsley-fern
IDENTITY: Barnsley IFS fern with stem, pinna, and a crozier tip
KEEP VERBATIM: inverse IFS, last-affine tint, stem rib, pinna rachis, crozier
ADD:
  1. rachis scales — dark chevrons along the stem affine
  2. sori — brown spore dots on the pinnae
FORBID: a different plant
A PACKING: ACES display RGBA
```

```
SHADER: gen-bifurcation-diagram
IDENTITY: the logistic-map bifurcation diagram
KEEP VERBATIM: logistic iteration, Lyapunov ridges, transient ghost, cobweb ticks, four sliders
ADD:
  1. period-3 window — a vertical band at the classic r≈3.83 window
  2. superstable points — bright ticks where the orbit sits on x=0.5
FORBID: replacing the logistic map
A PACKING: HDR density RGB + alpha
```

```
SHADER: gen-bio-luminescent-jelly
IDENTITY: a pulsing jellyfish with tentacles, canals, and marine snow
KEEP VERBATIM: bell SDF, jet-lag tentacles, canals, gonad, lappets, snow; raw pulsePhase in A.r
ADD:
  1. oral arms — four short frilled arms under the bell, shorter than the tentacles
  2. bell muscle striations — radial lines on the bell that brighten as it contracts
FORBID: a second creature
A PACKING: raw pulsePhase in A.r; ACES on writeTexture only
```

```
SHADER: gen-coral-reef-colony
IDENTITY: forking coral branches with skeleton memory and polyp mouths
KEEP VERBATIM: fork limbs, C.a skeleton, bleaching, star mouths; A.a is skeleton not display alpha
ADD:
  1. apical pallor — branch tips are paler than the trunk
  2. zooxanthellae speckles — green dots in living tissue, absent where it has bleached
FORBID: a new organism
A PACKING: A.rgb display history; A.a skeleton memory
```

```
SHADER: gen-cycloid-bloom
IDENTITY: hypotrochoid petals with a counter-epicycloid and a stamen
KEEP VERBATIM: hypotrochoid, vein, stamen, epicycloid layer, petal crossings
ADD:
  1. cusp sparks — bright knots where the curve parameter folds
  2. rolling circle — the faint generating circle that traces the bloom
FORBID: Fourier epicycles as the whole picture
A PACKING: ACES display RGBA
```

```
SHADER: gen-fibonacci-spiral-garden
IDENTITY: a phyllotaxis flower of packed disks and parastichy ridges
KEEP VERBATIM: golden-angle disks, 8- and 13-family ridges, four sliders; raw HDR in A
ADD:
  1. floret age — outer disks shift ochre as they leave the meristem
  2. involucre bracts — a ring of pointed bracts outside the head
FORBID: a second spiral family that replaces the golden angle
A PACKING: raw HDR display RGBA (ACES on writeTexture)
```

```
SHADER: gen-fireworks-chrysanthemum
IDENTITY: a spherical chrysanthemum shell with a pistil heart
KEEP VERBATIM: latitude foreshorten, pistil heart, ring layers, four sliders
ADD:
  1. petal barbs — short side ticks on the outer rays
  2. color break — outer sparks change hue partway through the burn
FORBID: palm fronds, crossette forks, willow drip
A PACKING: ACES display RGBA
```

```
SHADER: gen-fireworks-comet-trail
IDENTITY: a comet star with an ion tail, a dust trail, and a coma
KEEP VERBATIM: ion tail, dust sag trail, coma halo, four sliders
ADD:
  1. disconnection kink — the ion tail breaks and shifts along its length
  2. nucleus jets — short spikes on the sunward side of the head
FORBID: a chrysanthemum burst
A PACKING: ACES display RGBA
```

```
SHADER: gen-crystal-caverns
IDENTITY: raymarched crystal habits with a phantom shell and a basal pinacoid
KEEP VERBATIM: octahedron / hex prism / pyramid, pinacoid, phantom shell, four sliders
ADD:
  1. prism striations — fine lines down the prism walls, quiet on the flat cap
  2. fluid inclusions — pale bubbles caught in the crystal
FORBID: a different cave scene
A PACKING: ACES display RGBA
```

```
SHADER: gen-aperiodic-monotile
IDENTITY: a field of reflected hat tiles with brim, kite notch, and metatile edges
KEEP VERBATIM: reflected hats, chevron brim, kite notch, metatile outline, four sliders
ADD:
  1. hat crown — a button at the center of each hat
  2. substitution tint — 2×2 metatile cells share a hue family
FORBID: a periodic tiling that erases the hat
A PACKING: ACES display RGBA
```
