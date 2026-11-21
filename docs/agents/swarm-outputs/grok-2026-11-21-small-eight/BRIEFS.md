# Idea Cards — Grok (small eight, 2026-11-21)

Written before the WGSL edits. Eight shaders the user listed by size. Each card adds two ideas in the existing main path. Saved `params` stay byte-exact. No shared spring, shockwave, or palette is added. Springs, click paths, and earlier ideas that are already in a file stay as they are.

Four files still paste the binding header (`speed-lines-focus`, `luma-topography`, `dimension-slicer-guided`, `phase-shift`). Migrating them to `#include "_prelude.wgsl"` is infrastructure and is not an idea.

Formula rule: a §12.2 row is newly applied on at most one file here.

- Fold count as material (§12.2E) is `gen-sentient-plasma-silk-nebula-forge` only.
- SDF curvature (§12.2E) is `gen-sentient-plasma-silk-nebula-forge` only.
- No other §12.2 row is newly applied. The guided filter in `dimension-slicer-guided` is already the effect.

```
SHADER: speed-lines-focus
IDENTITY (one sentence): manga speed lines and a radial zoom-blur streak locked to a sprung focus, with click impact bursts.
KEEP VERBATIM: Blur Strength / Line Density / Line Speed / Contrast; 16-tap zoom blur toward the sprung focus; angular noise lines; center hole; spring in extraBuffer[133..137]; angular FFT voices; click burst rings; vignette by dist.
MECHANISM INTERROGATION:
  tactic 2: a pen stroke that flies out of a burst breaks into dashes and thins as the nib leaves the page. The lines here are continuous angular bands.
  tactic 4: Line Speed already scrolls the angle. The spatial version of that same speed is travel along the ray. Line Density already sets how many rays; it can also set how many dashes on a ray.
  tactic 6: C is not read. Do not invent a trail buffer. The spring and the click ripples stay.
ADD:
  1. Radial ink dashes — each ray is gated by a traveling fract of distance and Line Speed, so the band breaks into streaks that run outward. Gaps stay faintly present so the ray does not vanish.
  2. Stroke taper — the noise threshold tightens with distance from the focus, so the stroke is thicker near the burst and hairline at the edge. Contrast stays the ink amount.
FORBID: a second spring, an IQ palette, shockwaves beyond the click bursts already here, replacing the zoom blur
A PACKING: ACES display RGBA (C is not read; A was already display color, previously without ACES)
```

```
SHADER: gen-sentient-plasma-silk-nebula-forge
IDENTITY (one sentence): a raymarched silk-filament forge — four folded cylinders smoothed into a sphere, with braid knots and an ion shell.
KEEP VERBATIM: Silk Density / Spindle Speed / Core Glow / Color Shift; the abs-fold cylinder loop; mouse pull while held; braid-knot displacement; ion-bloom shell; step-count AO; palette and Lambert light.
MECHANISM INTERROGATION:
  tactic 1: the loop already reflects q through abs(). That reflection count is the ply of the silk, and it is thrown away. map() returns the distance twice.
  tactic 2: a thread brightens where it bends. The hit already has a position and a distance; curvature of that same map is the bend.
  tactic 3: map().y is a copy of the distance. It can carry the fold count without a new field.
ADD:
  1. Fold-count ply (§12.2E) — count the abs-folds the loop already performs and cool the existing palette by that ply. Distance stays in .x.
  2. SDF curvature sheen (§12.2E) — six taps of the existing map at the hit, so filament bends take a rim and the broad shell stays quieter.
FORBID: a new primitive, a spring, replacing the palette, another bloom shell
A PACKING: ACES display RGBA (unchanged; C is not read)
```

```
SHADER: luma-topography
IDENTITY (one sentence): the photo as a luminance relief, lit by a sprung pointer light and click fill flashes.
KEEP VERBATIM: Relief Height / Light Intensity / Shininess / Ambient Light; one-sided luma gradient as the normal; Blinn-Phong from the sprung light; click fill lights; depth added into the height; spring in extraBuffer[133..138].
MECHANISM INTERROGATION:
  tactic 3: luma is the elevation and is then thrown away except as a normal. A topo map draws the level sets of that elevation.
  tactic 2: a valley in a relief is a local minimum of height. The same luma taps that build the normal can form a Laplacian; positive curvature is a pocket and should sit in shade.
  tactic 6: C is not read. Do not store a height history. The spring stays the light, and only thread (0,0) writes it.
ADD:
  1. Elevation contours — ink where luma crosses bands whose count follows Relief Height, drawn on the lit color.
  2. Valley shade — four-neighbor Laplacian of luma darkens concave pockets, scaled by Relief Height, after the existing light.
FORBID: a second light spring, an IQ palette, replacing the Blinn-Phong normal, click ripples beyond the fill lights already here
A PACKING: ACES display RGBA (C is not read; A was already display color, previously without ACES)
```

```
SHADER: dimension-slicer-guided
IDENTITY (one sentence): a mouse-centered dimensional cut whose interior is a depth-guided filter, with warp, chromatic split, and an edge glow.
KEEP VERBATIM: Slice Width / Distortion / Angle / Aberration, including the dual use of those four sliders as guided-filter radius, epsilon, depth influence, and mouse influence; the rotated slab test; the guided-filter sums; ripple depth added to the guide; the edge glow and the outside darkening.
MECHANISM INTERROGATION:
  tactic 2: the cut is described as respecting object boundaries, but the slab is a straight rotated band. The depth the guide already trusts has a gradient; the lip can step out onto that gradient.
  tactic 7: Aberration is a horizontal UV shift no matter which way the slab is turned. The rift normal is the axis the Angle slider already builds.
  tactic 6: C is not read. Do not pack filter coefficients into A.
ADD:
  1. Depth-snapped rift edge — subtract a depth-gradient snap from the slab distance before the inside test, the glow, and the outside shadow, so the lip bulges onto silhouettes. The interior zoom uses that same cut distance; where the gradient is flat the snap is zero.
  2. Aberration along the rift normal — the existing R/B offset follows the rotated slab axis instead of screen X. Aberration stays the length.
FORBID: a spring, a second filter, audio bolted on, replacing the guided sum
A PACKING: ACES display RGBA (C is not read; A was not written — display RGBA is new and matches the color the shader samples)
```

```
SHADER: phase-shift
IDENTITY (one sentence): five zoom layers of the photo around the pointer, each at its own speed, with per-channel angular phase, an edge glow, and fog.
KEEP VERBATIM: Layer Speed Low / Layer Speed High / Edge Glow / Fog Density; five-layer zoom stack; ping-pong wrap; per-channel angular sample; distance phase; depth-gradient glow; fog mix; volumetric alpha.
MECHANISM INTERROGATION:
  tactic 4: the zoom clock is fract(time * layerSpeed) everywhere. Distance phase is already computed for the angular split. A phase shift that belongs on a zoom stack is that clock leading with radius, and only on the deeper layers so the front layer stays put.
  tactic 2: layers that differ in speed should show the flow at different times. The noise flow is sampled at one time and only scaled per layer.
  tactic 6: C is not read. Do not add a feedback trail.
ADD:
  1. Radial zoom-cycle lead — deeper layers add distance phase into the zoom fract, so the zoom wavefront runs outward from the pointer. Layer 0 keeps the original clock.
  2. Flow group delay — the displacement noise is sampled at time minus layer depth times (Layer Speed High − Layer Speed Low). Equal speeds share one flow.
FORBID: a spring, an IQ palette, a new angular model that replaces the per-channel rotation, click shockwaves
A PACKING: ACES display RGBA (unchanged; C is not read)
```

```
SHADER: pixel-tornado
IDENTITY (one sentence): a pixel vortex whose eye follows the pointer, with tangential blur, a debris wall, and a calm core.
KEEP VERBATIM: Strength / Funnel Width / Turbulence / Inward Pull; aspect-correct eye; Gaussian profile; gusting twist; calm eye; five-tap tangential blur; debris annulus; click shockwaves; cyan/magenta tint.
MECHANISM INTERROGATION:
  tactic 2: a tornado on radar is a hook, one spiral arm, not a closed ring. The wall is already an annulus of chunks. The arm should ride that annulus.
  tactic 2 again: inflow that is only radial misses the updraft. Inward Pull is the storm's intake; lift is the vertical part of that same intake, and it dies in the calm eye.
  tactic 6: C is not read. Do not store a velocity field.
ADD:
  1. Hook echo — a single log-spiral arm of the existing debris, masked by the same funnel wall, so the ring grows one dense hook. The chunk hash stays on the rest of the wall.
  2. Updraft shear — a screen-up UV shift scaled by profile, Inward Pull, and Strength, added in the existing blur taps, and zero inside the calm eye.
FORBID: a spring, a new palette, a second vortex, replacing the tangential blur
A PACKING: ACES display RGBA (unchanged; C is not read)
```

```
SHADER: gen-zeta-function-landscape
IDENTITY (one sentence): a colored height plot of ζ(s) along a window of the critical strip, with zero rails, nodal walls, and contour ticks.
KEEP VERBATIM: Sigma Offset / T Range / Height Scale / Term Precision; Dirichlet eta and the 2^(1-s) division; the four ordinate rails; |ζ|=1 contours; critical sheen; argument ticks; Re/Im walls; prime beat; the 0.08 C mix; click refraction of the plane.
MECHANISM INTERROGATION:
  tactic 1: the series is summed and only |ζ| is kept. The t-derivative of that same sum is the slope of the landscape.
  tactic 4: Term Precision is a global term count. The first omitted term is the truncation the slider is choosing, and it should be visible as grain that settles as the count rises.
  tactic 6: C is the previous display color, mixed at 0.08. Keep that mix. Do not pack the derivative into A.
ADD:
  1. Analytic slope light — accumulate ∂η/∂t inside the existing term loop, convert with the quotient rule, and shade log|ζ| by that slope.
  2. Omitted-term grain — the first term past `terms` ripples the height and the color, quieter as Term Precision rises.
FORBID: a different special function, a spring, an IQ palette, extra rails
A PACKING: ACES display RGBA (unchanged; C is that previous display color)
```

```
SHADER: quantum-ghost
IDENTITY (one sentence): a chromatic ghost of the photo offset from the pointer, with re-emitted wave packets, visibility-weighted fringes, and a click collapse.
KEEP VERBATIM: Ghost Offset / Fringe Frequency / Ghost Decay / Chromatic Shift; packet re-emission on a 4 s clock; fringe visibility V; click collapse; entanglement line; chromatic ghost stored in A and read from C; ACES on display only.
MECHANISM INTERROGATION:
  tactic 2: a free packet disperses. The phase is linear in the packet's own clock; a chirp tightens the fringes as that clock advances and the envelope spreads.
  tactic 5: a which-path measurement washes double-slit fringes out. The shader already treats mouse-down as a measurement (certainty jumps to 1) and only uses that to dim the entanglement line.
  tactic 6: A is the raw chromatic ghost, not display. The chirp and the visibility multiply the display path. Do not ACES A.
ADD:
  1. Packet chirp — the existing phase gains a factor (1 + local time), so fringes tighten as the packet spreads. The envelope and the re-emission clock stay.
  2. Which-path erasure — while the pointer is held, fringe visibility is scaled down. The click collapse and the visibility formula stay; this only gates them by the measurement the file already computes.
FORBID: a spring, a new particle system, packing display color into A, replacing the ghost offset
A PACKING: raw chromatic ghost history in A (r, g trail, b, alpha), C reads it back; ACES on writeTexture only. Unchanged.
```
