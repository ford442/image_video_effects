# Upgrade Notes — Grok (`cursor/batch-15`, 2026-10-27)

Twelve polar, fractal, and perspective shaders. Idea cards are in `BRIEFS.md` (written first). Each file keeps its previous mechanism and gains two ideas. Saved `params` are byte-exact.

Ten pasted headers were migrated with `migrate_to_prelude.py` (`log-polar-droste`, `polar-warp-interactive`, `mouse-julia-morph`, `mouse-hyperbolic-navigator`, `perspective-tilt`, `infinite-spiral-zoom`, `parallax-shift`, `swirling-void`, `origami-fold`, `julia-warp`). `ethereal-swirl` and `fractal-image-surf` already included the prelude. That swap is not the upgrade.

`infinite-spiral-zoom` no longer reads `plasmaBuffer[1..8]`. The branch-seam shimmer is a phase of `plasmaBuffer[0].z`. It also loads history with `textureLoad`. Those are fixes, not ideas.

`swirling-void` was storing `(warped x, warped y, photon ring, disk)` in A and mixing that tuple back as RGB. A now holds pre-ACES colour, and ACES is only on the display write. Packing fix, not an idea.

`log-polar-droste` is tagged audio-reactive and did not read `plasmaBuffer`. Bass pushes Zoom Speed; at silence the rate matches the previous slider. That is the claimed audio path, not an idea.

Real-GPU visual QA was not run. This VM has no hardware GPU.

Gates: Naga 12/12, prelude consistent, dead sliders 0 new on these 12, generated lists only these ids. Ledger rows only these ids.

## Per shader

### log-polar-droste
- Kept: log-radius wrap, spiral twist, branch time offset, recursion tint, click ripples, center glow.
- Added: a dark frame where the log-radius wraps; a gutter on each branch cut. One branch grows no extra seam.
- Formula: none. A is ACES display RGBA.

### ethereal-swirl
- Kept: value-noise FBM, billow octaves, upstream trail, depth-folded hue.
- Added: a silver lining where cloud density is neither clear nor solid, lit along the flow; the photo is sampled one step downstream before the blend.
- Formula: none. A stays ACES display RGBA.

### fractal-image-surf
- Kept: Julia, Mandelbrot, and Burning Ship, morph weights, cardioid c, escape lip, crest lift.
- Added: orbit-trap distance inside the existing loops; where the set never escapes, the surf falls back toward the unwarped photo.
- Formula: orbit trap (§12.2E). Only this file. A stays ACES display RGBA.

### polar-warp-interactive
- Kept: power-radius tunnel, spiral, pinch, click twist, chromatic sample. A stays `(smoothed bass, mouse.xy, alpha)`.
- Added: the power map's derivative desaturates the smear; a dark ray on the atan2 branch cut.
- Formula: none. ACES stays on the display write only.

### mouse-julia-morph
- Kept: c from the pointer, auto-morph, ripple-pinned c, orbit-trap filament, bass zoom.
- Added: the same loop's derivative draws an exterior distance rim; the photo palette also follows arg(z) at escape.
- Formula: none. Display is now ACES. Alpha stays normalized escape.

### mouse-hyperbolic-navigator
- Kept: Poincaré Möbius, angular tiles, horocycle rings, angular mortar, edge glow.
- Added: a radial gutter where hyperbolic distance wraps; red and blue take a Cauchy scale from Boundary Glow (zero glow, no split).
- Formula: Cauchy dispersion (§12.2F). Only this file. A stays ACES display RGBA.

### perspective-tilt
- Kept: ray/plane hit, yaw and pitch, vanishing falloff, grazing soften.
- Added: cos⁴ of the ray's angle off the optical axis; a dark bevel at the print's edge.
- Formula: cos⁴ vignetting (§12.2A). Only this file. A stays ACES display RGBA.

### infinite-spiral-zoom
- Kept: spring in `extraBuffer[133..139]`, Möbius, log-polar fract, branch count, chromatic copies.
- Added: a dark frame on the log-radius wrap; history is loaded upstream along the radial zoom.
- Formula: none. A stays the display colour, read back with `textureLoad`.

### parallax-shift
- Kept: the shader's slider mapping (depth scale, layer count, depth weight, focus), occlusion peel, focus smear.
- Added: one relief step from the depth residual; a rejected layer darkens.
- Formula: none. A stays ACES display RGBA.

### swirling-void
- Kept: Kerr frame drag, Doppler, blackbody disk, photon ring at 1.5× the horizon, click waves.
- Added: near the ring the sample radius locks onto the photon sphere; the disk cuts off on a bright orbit at 3× the horizon.
- Formula: none. A is pre-ACES RGB. ACES on the display write only.

### origami-fold
- Kept: one crease, reflect, Kawasaki buckle, print-through, chromatic edge, the existing tone map.
- Added: valley creases sink and mountain creases catch a ridge light; the open half takes a short cast shadow.
- Formula: none. A stays the display colour.

### julia-warp
- Kept: derivative loop, circle and axis traps, distance estimate, click shock, held zoom.
- Added: points that never escape barely displace; the distance estimate draws a dark contour.
- Formula: none. A stays ACES display RGBA.
