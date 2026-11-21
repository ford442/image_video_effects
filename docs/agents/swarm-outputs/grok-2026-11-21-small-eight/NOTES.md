# Notes — small eight (2026-11-21)

Idea Cards were written first in `BRIEFS.md`. Saved `params` were not renamed or re-defaulted. ACES stays on the display path. Where A was already a raw ghost, that write stayed raw.

Formulae, each new on one file: fold-count ply (§12.2E) and SDF curvature (§12.2E) on `gen-sentient-plasma-silk-nebula-forge` only. No other §12.2 row is new. The guided filter in `dimension-slicer-guided` was already the effect. No shared spring, shockwave, or palette was added. Springs and click paths that were already in a file were left in place.

Four shaders had a pasted binding header (`speed-lines-focus`, `luma-topography`, `dimension-slicer-guided`, `phase-shift`). They now `#include "_prelude.wgsl"`. That migration is not the upgrade.

`origin/main` already contains the later upgrades of `cyber-focus`, `pixel-focus`, `tone-histogram`, `tone-histogram-apply`, and `vortex-distortion`. Those files are not in this diff.

`gen-zeta-function-landscape` had slider roles only under `x-meta`, which the app does not read. Top-level `params` were added with those same names, ranges, and defaults (Sigma Offset 0.5, T Range 0.5, Height Scale 0.3, Term Precision 0.5) so the four sliders load. No existing param was edited. `dimension-slicer-guided` gained `"upgraded-rgba"` and an `x-meta.upgrade.params` block aligned to the saved params. Its four sliders still drive both the slab and the guided filter.

`luma-topography` wrote the light spring from every thread. The same integrator now runs on thread (0,0) only. Stiffness and critical damping are unchanged.

## speed-lines-focus

- Kept: Blur Strength, Line Density, Line Speed, Contrast, the 16-tap zoom blur, the sprung focus, angular FFT voices, click burst rings, the center hole, the distance vignette.
- Added: radial ink dashes — a traveling fract of distance and Line Speed breaks each ray, with a faint gap so the ray remains; stroke taper — the noise threshold tightens with distance from the focus. Contrast stays the ink amount.
- A packing: ACES display RGBA. C is not read. A was already display color; ACES is new on that color.

## gen-sentient-plasma-silk-nebula-forge

- Kept: Silk Density, Spindle Speed, Core Glow, Color Shift, the four-fold cylinder loop, the held mouse pull, braid knots, the ion shell, step-count AO, the palette and Lambert light.
- Added: fold-count ply (§12.2E) — abs-folds already in the loop cool the palette, packed in `map().y`, distance stays in `.x`; SDF curvature sheen (§12.2E) — six taps of the same map at a hit, so filament bends take a rim.
- A packing: ACES display RGBA. Unchanged. C is not read.

## luma-topography

- Kept: Relief Height, Light Intensity, Shininess, Ambient Light, the one-sided luma normal, Blinn-Phong from the sprung light, click fill lights, depth in the height.
- Added: elevation contours — ink on luma level sets, band count from Relief Height; valley shade — four-neighbor Laplacian of luma darkens pockets, scaled by Relief Height, after the light.
- A packing: ACES display RGBA. C is not read. A was already display color; ACES is new on that color.

## dimension-slicer-guided

- Kept: Slice Width, Distortion, Angle, Aberration, and the dual use of those sliders as guided-filter radius, epsilon, depth influence, and mouse influence. The rotated slab, the guided sums, ripple depth on the guide, the edge glow, and the outside darkening stay.
- Added: depth-snapped rift edge — a depth-gradient snap pulls the lip onto silhouettes; where the gradient is flat the snap is zero. Aberration along the rift normal — the same Aberration length follows the slab axis instead of screen X.
- A packing: ACES display RGBA. C is not read. A was not written; it now stores that display color.

## phase-shift

- Kept: Layer Speed Low, Layer Speed High, Edge Glow, Fog Density, the five-layer zoom stack, ping-pong wrap, per-channel angular samples, distance phase, the depth-gradient glow, fog, volumetric alpha.
- Added: radial zoom-cycle lead — deeper layers add distance phase into the zoom fract; layer 0 keeps the original clock. Flow group delay — displacement noise is sampled earlier by layer depth times (Layer Speed High − Layer Speed Low). Equal speeds share one flow.
- A packing: ACES display RGBA. Unchanged. C is not read.

## pixel-tornado

- Kept: Strength, Funnel Width, Turbulence, Inward Pull, the aspect-correct eye, the Gaussian profile, the gusting twist, the calm eye, the five-tap tangential blur, the debris annulus, click shockwaves, the cyan/magenta tint.
- Added: hook echo — one log-spiral arm of the existing debris, masked by the same wall; updraft shear — a screen-up shift inside the existing blur taps, scaled by profile, Inward Pull, and Strength, and zero in the calm eye.
- A packing: ACES display RGBA. Unchanged. C is not read.

## gen-zeta-function-landscape

- Kept: Sigma Offset, T Range, Height Scale, Term Precision, the Dirichlet eta loop and the 2^(1-s) division, the four ordinate rails, |ζ|=1 contours, critical sheen, argument ticks, Re/Im walls, the prime beat, the 0.08 mix with C, click refraction of the plane.
- Added: analytic slope light — ∂η/∂t accumulated in the existing term loop, carried through the same quotient, shading log|ζ|; omitted-term grain — the first term past `terms` ripples height and color, quieter as Term Precision rises. It is not added back into zeta.
- A packing: ACES display RGBA. Unchanged. C is the previous display color.

## quantum-ghost

- Kept: Ghost Offset, Fringe Frequency, Ghost Decay, Chromatic Shift, packet re-emission on the 4 s clock, fringe visibility, click collapse, the entanglement line. A stays the raw chromatic ghost.
- Added: packet chirp — the existing phase gains (1 + local time), so fringes tighten as the packet spreads; which-path erasure — a held pointer scales fringe visibility down. The visibility formula and the click collapse stay.
- A packing: raw chromatic ghost history in A (r, g trail, b, alpha). C reads it back. ACES on `writeTexture` only. Unchanged.
