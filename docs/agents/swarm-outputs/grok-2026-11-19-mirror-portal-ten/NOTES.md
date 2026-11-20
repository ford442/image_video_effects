# Notes — mirror / portal ten (2026-11-19)

Idea Cards were written first in `BRIEFS.md`. Saved `params` were not renamed or re-defaulted. ACES is on the display path. Where A is a raw tuple or a smear history, that write was left alone.

Formulae: orbit trap (§12.2E) is new only on `mouse-mandelbrot-zoom-portal`. No other §12.2 row is new in this batch. No shared spring, shockwave, or palette was added. Springs and click paths that were already in a file were left in place.

Seven shaders had a pasted binding header. They now `#include "_prelude.wgsl"`. That migration is not the upgrade. Their ids were removed from `src/contracts/prelude_migration.json` `pending`.

## quad-mirror

- Kept: H/V mirror offset, seam warp, rotation, the abs() fold, ribbons, click-shell kick, FBM seam warp, spectral grade, channel-multiply diffraction, exact-C trail.
- Added: glass bevel (inset + darken on the crease); seam split (R/B resampled along the nearer crease normal); quadrant registration (sign-dependent UV bias). Both the bevel and the registration ride Seam Warp.
- A packing: ACES display RGBA. Unchanged.

## reality-tear

- Kept: Tear Size, Jaggedness, Burn Edge, Static Noise, noise-displaced radius, invert+static void, burn rim, sector FFT voices, spring in extraBuffer[133..137], click rifts.
- Added: tangent curl on the rim; sparse fiber pull just outside the hole (Jaggedness owns the pull); void parallax (the hole samples a 1.12× copy, then the existing static).
- A packing: ACES display RGBA. C was unread; it is still display color.

## stereoscopic-3d

- Kept: Max Separation, Focus Offset, Glitch Jitter, Lens Rotation, red/cyan masks, early-out, bass envelope, smooth mouse in C.gb, trail in C.a.
- Added: crosstalk of the other eye's luma, scaled by Glitch Jitter; vertical vergence from Lens Rotation × sceneDepth (0 at the saved default); one extra defocus tap where |sceneDepth| is large.
- A packing: raw state (envBass, smoothMouse.xy, trailIntensity). ACES is on `writeTexture` only.

## fractal-noise-dissolve

- Kept: Noise Scale, Hole Radius, Edge Softness, Burn Intensity, domain-warped FBM contour, click rings on the mask, heat shimmer, scorch, pinholes and islands.
- Added: char cracks from ridges of the existing FBM, gated by the scorch; ember cells that scroll up inside the burned hole, scaled by Burn Intensity.
- A packing: ACES display RGBA. Unchanged.

## mirror-dimension

- Kept: Segments, Spin Speed, Shift, Zoom, triangle fold, spring center, click spin, per-segment FFT shimmer, treble seam glow.
- Added: mirror bevel (inset angle + darkened crease); tube caustic toward r = 0, tightened by Zoom; fold fringe (R/B at a small angle, only on the bevel).
- A packing: ACES display RGBA. C was unread; it is still display color. JSON features now include `audio-reactive` and `upgraded-rgba`, which the shader already did (audio) or now does (ACES).

## neon-pulse-dissolve

- Kept: Glow Radius, Dissolve Amount, Neon Saturation, Edge Sharpness, Sobel magnitude, tube core + halo, threshold fringe, failing-tube flicker, scan runner, click fronts.
- Added: gas striations along the core Sobel tangent; phosphor afterglow from the previous display in C, held back where a tube is currently lit.
- A packing: ACES display RGBA. C is now read as the previous display.

## mouse-mandelbrot-zoom-portal

- Kept: Zoom Level, Iteration Depth, Palette Speed, Portal Blend, z = z² + c, smooth iteration, inside-set dark, click-portal loop, spring, the existing palette, the 0.28 photo mix, exact-C trail.
- Added: orbit trap (§12.2E) inside the existing loop, multiplied into the existing palette and into click portals; interior windows onto the photo, Portal Blend × exp(−trap). At Portal Blend 0 the bulbs stay dark.
- A packing: ACES display RGBA. Unchanged.

## split-dimension

- Kept: Glitch Intensity, Color Shift, Negative Str, Split Angle, the dot-product cut, scanline hash offset, per-channel shift, negative mix, click crack, spring on the seam.
- Added: registration jump along the split normal; hinged shear that grows with distance from the seam; a dark-core / bright-shoulder lip in place of the flat gray band.
- A packing: ACES display RGBA. C was unread; it is still display color.

## quantum-tunnel-interactive

- Kept: Tunnel Strength, Aberration, Pulse Speed, Twist, log-z pulse, wavelength twist, RGB radius split, spring, click twist, blue core glow.
- Added: the pulse sine also occludes (ridges); one extra sample at a shorter radius, mixed by Pulse Speed; a dark pupil before the blue glow.
- A packing: ACES display RGBA. Unchanged.

## cyber-physical-portal

- Kept: Portal Radius, Swirl Amount, Grid Density, Glow, fp128 spin, four accretion bands, rim runner, throat smear, click EMP, cyan/magenta rim.
- Added: a thin photon ring between the horizon and the outer rim; Doppler beaming, 1 + k·cos(angle), k from Swirl Amount. Zero swirl leaves the disk flat.
- A packing: throat-smear RGB + alpha. C is smear history. ACES stays on `writeTexture`. The smear write was not replaced with the composited frame.
