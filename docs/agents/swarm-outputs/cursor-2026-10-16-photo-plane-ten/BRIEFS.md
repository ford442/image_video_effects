# Photo-plane ten — idea cards (written before WGSL)

Ten shaders where the photograph stays the subject. None are in the 2026-10-10 or 2026-10-11 batches. Numpy-gated sims (Lenia, multiscale Turing, Navier–Stokes dye, Physarum) are left alone. `tone-histogram-apply` is skipped: it still reads `extraBuffer[1..258]` as a histogram the partner pass no longer writes.

```
SHADER: bismuth-crystallizer
IDENTITY (one sentence): hopper-crystal stairs refract the photo with oxide iridescence
KEEP VERBATIM: iterative box steps, hopper offset cycle, thin-film iridescence, metallic Fresnel, four sliders (steps, offset, color freq, metallic mix)
ADD:
  1. terrace rims — a bright lip on the current stair edge, the part of a hopper that catches light
  2. tarnish wells — darker oxide pooled in the middle of that stair, away from the rim
FORBID on this file: a different crystal family, springs, click shockwaves
A PACKING: ACES display RGBA (this shader does not read C)
```

```
SHADER: molten-glass
IDENTITY (one sentence): heat advected up the glass warps and tints the photo
KEEP VERBATIM: heat in A.r, upward advection from C, cooling, held injection, click fronts, Fresnel, Beer-Lambert; four sliders
ADD:
  1. cooling crust — a dull skin where this frame's heat fell below the advected heat
  2. drip thread — the existing convection packet drawn as a hot highlight, not only a 4% heat bump
FORBID on this file: ACES on the stored heat, a second fluid solver
A PACKING: raw heat in A.r (C.r is heat). ACES on writeTexture only
```

```
SHADER: circular-pixelate
IDENTITY (one sentence): a hexagonal compound eye of round lenslets over the photo
KEEP VERBATIM: hex cells, dome refraction, chromatic aperture, glint, click dilation, density / radius / hardness / bg mix
ADD:
  1. hex diaphragm — the stop is six blades, so the hole is a hex iris on the round dome
  2. grout seam — a dark line where two hex cells meet, outside the aperture
FORBID on this file: a square pixelate, a new palette overlay
A PACKING: ACES display RGBA
```

```
SHADER: spectral-mesh
IDENTITY (one sentence): a spectral wire grid that densifies on image edges and drifts toward the pointer
KEEP VERBATIM: gradient-adaptive density, ortho grid plus triangle wires, spectral wavelength mix, four sliders
ADD:
  1. junction beads — a bright node where a horizontal wire crosses a vertical one
  2. grating fringe — R and B sampled off the wire normal, so each wire splits the photo
FORBID on this file: replacing the grid with a particle mesh
A PACKING: A stores (line, triLine, pull, alpha); C is not read as color
```

```
SHADER: cross-conv-mouse-bilateral
IDENTITY (one sentence): a pointer brush that bilateral-smooths the photo and leaves the rest alone
KEEP VERBATIM: 7×7 bilateral, spatial Gaussian, luma range weight, brush falloff, three sliders
ADD:
  1. range coring — tiny luma gaps count as noise and smooth; real edges still reject
  2. wet edge — a darker ring where the brush coverage falls off
FORBID on this file: a spring, a new kernel family
A PACKING: ACES display RGBA
```

```
SHADER: selective-color
IDENTITY (one sentence): spatial masks keep color islands in a desaturated photo
KEEP VERBATIM: voronoi, fbm, polar sectors, hex/star SDF, ripple masks, radius / softness / desat / feather
ADD:
  1. hue window — inside an island, only colors near the pointer's sample stay saturated
  2. mask contour — the existing boundary darkens into a seam around each island
FORBID on this file: replacing the masks with a grade-only slider
A PACKING: ACES display RGBA (this shader does not read C)
```

```
SHADER: plasma
IDENTITY (one sentence): eight orbiting plasma orbs with trails and shadows on the photo
KEEP VERBATIM: eight orbs, orbit radius and speed, metaball field, velocity trails, shadow offset, four sliders
ADD:
  1. arc filaments — a strand between each orb and the next
  2. luma corona — the glow prefers the bright parts of the photo under the field
FORBID on this file: a different orb count, Gray-Scott, IQ palette as the whole look
A PACKING: ACES display RGBA (this shader does not read C)
```

```
SHADER: poincare-tile
IDENTITY (one sentence): the photo mapped through a Poincaré disk of p-gon sectors
KEEP VERBATIM: disk clip, Möbius translate toward the pointer, sector fold, curvature / symmetry / speed / tile scale
ADD:
  1. geodesic ink — a thin dark stroke on the existing sector boundary
  2. vertex cusps — bright pearls where the q-fold rays meet the disk rim
FORBID on this file: a Euclidean tiling, springs
A PACKING: ACES display RGBA (this shader does not read C)
```

```
SHADER: quantum-fractal
IDENTITY (one sentence): two iterated complex wavefunctions interfere over the photo
KEEP VERBATIM: Schrödinger-style z² step, dual constants c1/c2, scale / iterations / entanglement / edge-glow roles
ADD:
  1. phase fringes — rings from the argument of the first wavefunction
  2. phase-pulled photo — the source sample shifts along the second wavefunction's phase
FORBID on this file: a Mandelbrot rewrite, click shockwaves
A PACKING: ACES display RGBA (this shader does not read C)
```

```
SHADER: liquid-chrome-ripple
IDENTITY (one sentence): a capillary chrome sheet refracts the photo along ripple normals
KEEP VERBATIM: multi-sine height, Fresnel metal, RGB dispersion, caustics, thin film, C afterimage, flow / distort / metal / freq
ADD:
  1. crest beads — white highlights where the sheet is locally higher than its neighbors
  2. trough meniscus — a cool darkening in the local valleys
FORBID on this file: a height-field solver, ACES on a stored height (A stays display history)
A PACKING: HDR display history in A; ACES on writeTexture only
```
