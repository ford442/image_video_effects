```
SHADER: gen-4d-projection-dream-weavers
IDENTITY: a flat 2D slice of a rotating 4D quaternion Julia set with a cosine palette, a grid overlay and
  peak-hold trails (not raymarched).
KEEP VERBATIM: 4D rotations (rot4XW/YZ/ZW/XY + the four angle lines), julia4D palette semantics (escape r>4,
  iteration count, r returned at escape or after maxIter), hypercube box/sphere fold loop (fold 1.2+bass*.3,
  minR2 .4+mids*.2, scale 1.5+bass*.3, 6 iters, input p4*(0.5+treble*.2)), click phase kick, mouse W/V navigation,
  transport, Julia constant path, smoothIter + cosine palette, "deep dark" interior + inner glow, W fog,
  velocity-lag lattice trail (4 lags, colour), peak-hold history max(color, prev*0.9) clamp 5,
  4 slider roles (zoom / rotation speed / hue shift / detail maxIter 4..12), saved params.
  Do NOT touch the separate legacy public/shaders/4d-projection-dream-weavers.wgsl.
ADD (native ideas):
  1. Julia DE filaments — julia4D keeps iterating the same orbit past the palette budget (to 20 iters, bail 64)
     with the Julia derivative dz' = 2|z|dz (HEAD had the Mandelbrot "+1"), and DE = 0.5·r·log r/dz draws a
     thin bright filament on the exterior side of the TRUE set boundary. Replaces the L240-242 "edge" term whose
     boundarySharp == 1 for every interior pixel (painted the "deep dark" interior flat cream).
     numpy port (480x270, default sliders, audio 0): filament>0.5 covers 1.3-3.5% of pixels at t=0/17/133,
     traced inside the maxIter=7 blob; plain DE at the 7-iter boundary is 7-16 px wide (needs the extra iters).
  2. Hypercube fold lattice — hypercubeFractal carries two screen tangents through box fold (-1 per clamped
     component), sphere fold (k, or the inversion Jacobian (I-2zz^T/r2)/r2) and scale (+dq), so its lines are
     true screen-space distances: the box-fold crease hyperplanes |z_c| = fold of iterations 1-2 plus HEAD's
     |z.xyz| = 1 shell, coloured by fold count, with no treble gate (HEAD: treble*0.5 -> invisible at audio 0;
     numpy: HEAD's shell contour exists on ~0.1% of pixels). numpy: crease lines (>0.5) cover 2.5-3.4% of pixels;
     tangent distance / finite-difference distance = 1.000 (p5..p95) at t=0/17/41/90. The scalar-dr estimate
     |f|/dr was only 0.4-0.75x and smeared where a crease hyperplane goes edge-on to the slice.
  3. 4D-space weave — the lattice (L222-234, screen-space grid today) becomes sin(k·p4.x), sin(k·p4.y) of the
     rotated 4D point with analytic screen gradient (ex4, ey4), so XW/YZ rotations skew the two families off
     perpendicular and spread them as an axis turns edge-on; the lag trail offsets p4 along the same tangents.
     k = 34 × default zoom 1.3 = 44.2 so the unrotated grid matches HEAD spacing/width at the default zoom.
FLOOR: ACES on display only (A stays raw HDR history); semantic alpha (set/filament/crease coverage + escape
  slowness; hardcoded 1.0 at L247/L250); exact textureLoad(dataTextureC, coord, 0) (HEAD used a filtering
  textureSampleLevel on rgba32float, half-texel drift compounded by the max); depth near=1 on the set.
FORBID: W-slice ghost frame, W-cell hive lattice, face-crossing caustics, temporal birefringence, springs, ripples.
A PACKING: raw HDR peak-hold history RGB (unchanged); .a = semantic coverage (C.a is never read).
```

STATUS: final
