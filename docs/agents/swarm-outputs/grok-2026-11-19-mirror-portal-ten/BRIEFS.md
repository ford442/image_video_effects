# Idea Cards — Grok (mirror / portal ten, 2026-11-19)

Written before the WGSL edits. Ten shaders the user listed by size. Each card adds two or three ideas in the existing main path. Saved `params` stay byte-exact. No shared spring, shockwave, or palette is added. Springs and click paths that are already in a file stay as they are.

Several files already carry an earlier idea pass. This pass deepens that mechanism. Seven files still paste the binding header (`quad-mirror`, `reality-tear`, `stereoscopic-3d`, `mirror-dimension`, `mouse-mandelbrot-zoom-portal`, `split-dimension`, `quantum-tunnel-interactive`). Migrating them to `#include "_prelude.wgsl"` is infrastructure and is not an idea.

Formula rule: a §12.2 row is newly applied on at most one file here.

- Orbit trap (§12.2E) is `mouse-mandelbrot-zoom-portal` only.
- No other §12.2 row is newly applied. The other ideas are the device the shader already imitates (mirror bevel, tear curl, anaglyph leak, char, neon tube, hinged split, tunnel ridge, photon orbit).

```
SHADER: quad-mirror
IDENTITY (one sentence): a four-way mirror of the photo, folded on both axes around the pointer, with seam warp, ribbons, and a rotating copy.
KEEP VERBATIM: hOffset / vOffset / seamWarp / rotation roles; abs() fold; ribbon displacement; click-shell UV kick; FBM seam warp; spectral ribbon grade; exact-C trail mix. The channel-multiply diffraction stays.
MECHANISM INTERROGATION:
  tactic 2: a real quad mirror has a glass thickness at the crease. The abs() fold is a mathematical line.
  tactic 3: the sign of the pre-abs coordinate is thrown away, so the four panes cannot mis-register.
  tactic 7: the crease has a normal. Chromatic fringe belongs along that normal, as a resample, which the existing channel multiply does not do.
ADD:
  1. Glass bevel — inset the sample along the crease and darken it. Width rides seamWarp.
  2. Seam split — resample R and B along the nearer crease normal, stronger on the bevel.
  3. Quadrant registration — a sign-dependent UV bias so the four panes do not lock. Amount rides seamWarp.
FORBID: a new spring, an IQ palette, a second kaleidoscope fold
A PACKING: ACES display RGBA (unchanged; C is the trail)
```

```
SHADER: reality-tear
IDENTITY (one sentence): a jagged circular tear under the pointer, burning rim, inverted static void, click rifts.
KEEP VERBATIM: Tear Size / Jaggedness / Burn Edge / Static Noise; noise-displaced radius; invert+static void; burn rim; sector FFT voices; spring center in extraBuffer[133..137]; click rifts.
MECHANISM INTERROGATION:
  tactic 2: torn paper curls at the lip and pulls fibers just outside the hole.
  tactic 5: a hole in a print shows a differently scaled copy through it, not only hash static.
  tactic 6: C is not read. Do not invent a field. The void stays a resample of the photo.
ADD:
  1. Torn-paper curl — tangent UV offset peaking on the existing rim.
  2. Fiber pull — sparse angle bins just outside the radius yank the photo inward. Amount rides Jaggedness.
  3. Void parallax — the hole samples a slightly enlarged copy, then the existing static. Static Noise still owns the hash mix.
FORBID: a second tear shape, a spring rewrite, an IQ palette
A PACKING: ACES display RGBA (C was unread; still display color)
```

```
SHADER: stereoscopic-3d
IDENTITY (one sentence): a red/cyan anaglyph of the photo, separation from a vertical depth ramp, with glitch jitter and lens rotation.
KEEP VERBATIM: Max Separation / Focus Offset / Glitch Jitter / Lens Rotation; red-from-left, cyan-from-right masks; early-out when disparity is ~0; bass envelope; smooth mouse in C.gb; trail in C.a. A stays the state tuple, not display color.
MECHANISM INTERROGATION:
  tactic 2: cardboard anaglyph glasses leak the other eye, and the two lenses slip vertically when the mount is rotated.
  tactic 3: sceneDepth is already the distance to the focal plane and is only used to set the horizontal shift.
  tactic 5: off the convergence plane the photo goes soft. That is the same focus slider.
ADD:
  1. Crosstalk — a fraction of the other eye's luma leaks in, scaled by Glitch Jitter.
  2. Vertical vergence — a Y slip proportional to Lens Rotation × sceneDepth, after the existing rotation.
  3. Focal defocus — one extra tap mixed in where |sceneDepth| is large. Focus Offset still places the plane.
FORBID: writing display color into A, a spring in extraBuffer, a new palette
A PACKING: raw state (envBass, smoothMouse.xy, trailIntensity). ACES on writeTexture only.
```

```
SHADER: fractal-noise-dissolve
IDENTITY (one sentence): fractal-noise erosion of the photo around the pointer, with a burn front, heat shimmer, scorch, and pinholes.
KEEP VERBATIM: Noise Scale / Hole Radius / Edge Softness / Burn Intensity; domain-warped FBM contour; click rings on the mask only; heat-shimmer UV; scorch sepia; fractal pinholes and islands.
MECHANISM INTERROGATION:
  tactic 2: a burn front cracks the char and throws embers up out of the hole.
  tactic 3: the contour noise `n` is already a field. Its ridges are the cracks.
  tactic 6: C is unread display color. Embers are additive, not a new sim.
ADD:
  1. Char cracks — ridges of the existing FBM darken the scorch band.
  2. Ember lift — sparse cells in the burned hole scroll upward. Amount rides Burn Intensity.
FORBID: a new noise motif, a spring, replacing the erosion mask
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: mirror-dimension
IDENTITY (one sentence): a kaleidoscope — N mirrored wedges of the photo spinning around a sprung center.
KEEP VERBATIM: Segments / Spin Speed / Shift / Zoom; triangle fold; spring center; click spin kicks; per-segment FFT shimmer; treble seam glow.
MECHANISM INTERROGATION:
  tactic 2: a kaleidoscope's mirrors have a bevel, and the tube concentrates light on the axis.
  tactic 5: the glass edge fringes. The fringe is an angular offset of the fold the shader already computes.
  tactic 7: `a` after the fold is the distance to the crease. That is the bevel coordinate.
ADD:
  1. Mirror bevel — inset the folded angle and darken the crease.
  2. Tube caustic — brighten toward r = 0, tighter as Zoom increases.
  3. Fold fringe — R and B sampled at a small angle offset, only where the bevel is.
FORBID: a different segment count formula, a new spring, an IQ palette
A PACKING: ACES display RGBA (C was unread; still display color)
```

```
SHADER: neon-pulse-dissolve
IDENTITY (one sentence): Sobel edges drawn as neon tubes over a photo whose interior dissolves into colour noise.
KEEP VERBATIM: Glow Radius / Dissolve Amount / Neon Saturation / Edge Sharpness; Sobel magnitude; tube core + halo; threshold fringe; failing-tube flicker; scan runner and click fronts on the edge.
MECHANISM INTERROGATION:
  tactic 2: a neon tube has gas striations along its length, and the phosphor keeps glowing after the tube drops.
  tactic 3: Sobel already computes gx, gy and throws them away, keeping only the magnitude.
  tactic 6: A is display color, so C is the previous frame. The excess over the photo is leftover tube light.
ADD:
  1. Gas striations — the core Sobel gradient's tangent modulates the existing glow.
  2. Phosphor afterglow — previous-frame excess over the photo, gated off where a tube is currently lit.
FORBID: a new edge detector, a spring, a second palette
A PACKING: ACES display RGBA (now also read back from C as the previous display)
```

```
SHADER: mouse-mandelbrot-zoom-portal
IDENTITY (one sentence): an escape-time Mandelbrot under the pointer, palette-coloured, with click portals into deeper copies and a mix of the photo.
KEEP VERBATIM: Zoom Level / Iteration Depth / Palette Speed / Portal Blend; z = z² + c; smooth iteration; inside-set dark; click-portal loop; spring; the existing palette; 0.28 photo mix; exact-C trail.
MECHANISM INTERROGATION:
  tactic 1: the iteration already runs. An orbit trap is a min taken inside that loop.
  tactic 3: the interior is a flat colour. The trap distance says which bulbs passed near the origin.
  tactic 6: the photo sample already exists for the global mix. The bulbs can open onto it.
ADD:
  1. Orbit-trap veins (§12.2E) — min |z| inside the existing loop, multiplied into the existing palette. Same trap on click portals.
  2. Interior windows — inside the set, mix the photo by Portal Blend × exp(−trap). At Portal Blend 0 the bulbs stay dark.
FORBID: a different fractal, a new palette, changing the iteration
A PACKING: ACES display RGBA (unchanged; C is the display trail)
```

```
SHADER: split-dimension
IDENTITY (one sentence): a line through the pointer; one half is the photo, the other is glitched, channel-shifted, and optionally negative.
KEEP VERBATIM: Glitch Intensity / Color Shift / Negative Str / Split Angle; split by dot(p, normal); scanline hash offset; per-channel shift; negative mix; click crack of the line; spring on the seam.
MECHANISM INTERROGATION:
  tactic 2: two dimensions that share a cut still don't share pixels — one plane is offset, and they are hinged so the shear grows away from the seam.
  tactic 5: the existing highlight is a flat gray band on one side of a mathematical line. A split lip is bright at the shoulders and dark in the gap.
  tactic 7: `d` is already the signed distance to the cut. The hinge uses it as a lever arm.
ADD:
  1. Registration jump — the glitch half is offset along the split normal by Glitch Intensity.
  2. Hinged shear — tangential offset proportional to distance from the seam, same slider.
  3. Split lip — dark core and bright shoulders replace the flat gray band. The cut stays the same line.
FORBID: a second split axis, a Schmitt field packed into A, an IQ palette
A PACKING: ACES display RGBA (C was unread; still display color)
```

```
SHADER: quantum-tunnel-interactive
IDENTITY (one sentence): a polar tunnel of the photo around a sprung center, with log-z pulse rings, per-channel twist, and a blue core glow.
KEEP VERBATIM: Tunnel Strength / Aberration / Pulse Speed / Twist; log-z pulse; wavelength twist; RGB radius split; spring; click twist; blue core glow.
MECHANISM INTERROGATION:
  tactic 2: rings that only nudge the radius should also occlude, and travel down a tunnel streaks the wall toward the vanishing point.
  tactic 3: the pulse sine is computed and then used only as a radius delta.
  tactic 5: the end of the tunnel is a dark pupil, not only a blue disk.
ADD:
  1. Pulse ridges — the same sine darkens the wall where the ring stands proud.
  2. Vanishing streak — one extra sample at a shorter radius, mixed by Pulse Speed, stronger near the center.
  3. Dark pupil — the innermost disk dims before the existing blue glow is added.
FORBID: a new tunnel mapping, a spring rewrite, a palette swap
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: cyber-physical-portal
IDENTITY (one sentence): a Kerr-like portal — frame-dragged grid, accretion bands, racing rim, throat smear from C, chromatic lensing.
KEEP VERBATIM: Portal Radius / Swirl Amount / Grid Density / Glow; fp128 spin; four accretion bands; rim runner; throat smear written to A; click EMP; the cyan/magenta rim. A stays the pre-composite smear, not the ACES frame.
MECHANISM INTERROGATION:
  tactic 2: a spinning hole has a thin photon ring outside the horizon, and the approaching limb is brighter (Doppler).
  tactic 3: eventHorizon and angle are already computed. The ring and the cosine of azimuth ride them.
  tactic 6: C is the smear. Do not repack A as the composited frame.
ADD:
  1. Photon ring — a tight ring between the horizon and the outer rim, warmer than the accretion bands.
  2. Doppler beaming — multiply the disk by 1 + k·cos(angle), k from Swirl Amount. Zero swirl leaves it flat.
FORBID: a different lensing model, storing the ACES frame in A, a new palette
A PACKING: throat-smear RGB + alpha (C is smear history). ACES on writeTexture only.
```
