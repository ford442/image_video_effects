# Idea Cards — cursor/batch-15 (polar, fractal, perspective)

Written before the WGSL edits. Each file keeps its mechanism and gains two ideas.

```
SHADER: log-polar-droste
IDENTITY: infinite log-polar spiral zoom of the photo, twisted, with recursive copies
KEEP VERBATIM: log-radius wrap between r1 and r2, spiral twist, branch time offset, recursion tint, click ripples, center glow
ADD:
  1. Droste frame — a dark border where the log-radius wraps, so each copy sits in a picture frame
  2. sector gutter — a crease on each branch cut; a single branch grows no extra seam
FORBID: a new fractal, IQ palette as the picture, a spring
A PACKING: ACES display RGBA
```

```
SHADER: ethereal-swirl
IDENTITY: billow clouds advected over the photo, with hue folded by depth
KEEP VERBATIM: value-noise FBM, billow octaves, upstream trail, depth-folded hue, four slider roles
ADD:
  1. silver lining — the cloud edge (density that is neither clear nor solid) lights along the flow
  2. wind smear — the photo is sampled one step downstream of the existing flow before the blend
FORBID: a new solver, a spring
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: fractal-image-surf
IDENTITY: the photo displaced by a morph of Julia, Mandelbrot, and Burning Ship
KEEP VERBATIM: three iterators, morph weights, cardioid c, escape lip, crest lift, FBM warp
ADD:
  1. orbit-trap veins — closest approach inside the loops already running, as a bright filament
  2. calm lake — where the set did not escape, the surf displacement falls back toward the photo
FORBID: a fourth fractal, replacing the surf with a full-screen palette
A PACKING: ACES display RGBA (unchanged)
FORMULA: orbit trap (§12.2E). Only this file.
```

```
SHADER: polar-warp-interactive
IDENTITY: a polar tunnel around the pointer, with spiral, pinch, and click twist
KEEP VERBATIM: power-radius map, spiral angle, mirrored tunnel UV, bass envelope and mouse in A, chromatic sample
ADD:
  1. radial stretch bleach — the power map's derivative desaturates where the photo is smeared
  2. branch cut — a dark ray where atan2 flips, the seam a polar unwrap has to cut
FORBID: a Droste log-zoom (that is log-polar-droste), a new mandala
A PACKING: raw (smoothed bass, mouse.xy, alpha). Display write stays ACES.
```

```
SHADER: mouse-julia-morph
IDENTITY: Julia set whose c follows the pointer, coloured by the photo as a palette
KEEP VERBATIM: c from the mouse, auto-morph mix, ripple-pinned c, orbit-trap filament, bass zoom
ADD:
  1. exterior distance rim — the derivative of the same loop draws a bright edge on the boundary
  2. spiral palette — the photo lookup also follows the argument of z at escape, so arms pick different colours
FORBID: replacing the photo palette with an IQ cosine as the whole picture
A PACKING: ACES display RGBA. Alpha stays normalized escape.
```

```
SHADER: mouse-hyperbolic-navigator
IDENTITY: the photo on a Poincaré disk, scrolled by a mouse Möbius transform
KEEP VERBATIM: disk Möbius, angular tile wrap, horocycle rings, angular mortar, edge glow, click waves
ADD:
  1. horocycle gutter — a radial seam where hyperbolic distance wraps, distinct from the angular mortar
  2. Cauchy split — red and blue sample a slightly different conformal scale, driven by Boundary Glow
FORBID: a Euclidean kaleidoscope that drops the disk
A PACKING: ACES display RGBA (unchanged)
FORMULA: Cauchy dispersion (§12.2F). Only this file.
```

```
SHADER: perspective-tilt
IDENTITY: the photo on a plane yawed and pitched by the pointer
KEEP VERBATIM: ray/plane hit, yaw and pitch from the mouse, vanishing falloff, grazing soften, plane scale
ADD:
  1. cos⁴ field falloff — brightness follows the ray's angle off the optical axis
  2. card edge — a dark bevel where the hit UV meets the border of the print
FORBID: a second plane, a lens-flare chain
A PACKING: ACES display RGBA (unchanged)
FORMULA: cos⁴ vignetting (§12.2A). Only this file.
```

```
SHADER: infinite-spiral-zoom
IDENTITY: Möbius drift into a log-polar Droste zoom, with chromatic branches
KEEP VERBATIM: spring in extraBuffer[133..139], Möbius, log-polar fract, branch count, chromatic Möbius copies
ADD:
  1. Droste frame — a dark ring where the log-radius fractional part wraps
  2. zoom trail — history is loaded upstream along the radial zoom, not from the same texel
FORBID: reading plasmaBuffer[1..]; a filtering sample of dataTextureC
A PACKING: soft-ceiling display RGBA in A (exact load)
```

```
SHADER: parallax-shift
IDENTITY: several depth layers of the photo shifted away from the focus plane
KEEP VERBATIM: layer count from the second slider, occlusion peel, focus-plane smear, slider order as the shader already maps it
ADD:
  1. relief step — one correction of the layer UV by the depth residual at the first hit
  2. disocclusion gap — a layer the nearer surface rejected darkens instead of showing a clean average
FORBID: a new raymarcher, rewiring the JSON labels onto different shader slots
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: swirling-void
IDENTITY: a Kerr swirl of the photo around a dark horizon, with a hot disk and a photon ring
KEEP VERBATIM: frame-drag angle, Doppler, blackbody disk, photon ring at 1.5× horizon, click waves
ADD:
  1. photon caustic — near the ring, the sample radius is pulled onto the photon sphere
  2. ISCO lip — the disk cuts off near 3× the horizon and brightens on that orbit
FORBID: storing coordinates in A and reading them back as colour
A PACKING: pre-ACES RGB in A (the trail). ACES on the display write only.
```

```
SHADER: origami-fold
IDENTITY: one crease through the pointer, mountain or valley, with paper on the folded half
KEEP VERBATIM: reflect across the crease, Kawasaki buckle, print-through, chromatic edge, paper fibre
ADD:
  1. valley sink / mountain ridge — the crease darkens or catches light with the existing mountain/valley flag
  2. cast shadow — the open half darkens in a short band beside the crease
FORBID: a multi-fold tessellation, a new paper shader
A PACKING: ACES display RGBA (existing tone map kept)
```

```
SHADER: julia-warp
IDENTITY: the photo refracted along a Julia orbit's derivative, with trap light
KEEP VERBATIM: derivative loop, circle and axis traps, distance estimate, click shock, held zoom
ADD:
  1. calm interior — points that never escape displace much less, so the lake shows the photo
  2. distance contour — the estimate already computed draws a dark line on the boundary
FORBID: a second Julia iterator, dropping the refraction
A PACKING: ACES display RGBA (unchanged)
```
