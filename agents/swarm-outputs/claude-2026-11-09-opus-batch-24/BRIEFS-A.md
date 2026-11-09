# Fork A briefs (written before WGSL)

SHADER: pixel-depth-sort (2nd pass)
IDENTITY: depth-keyed 9-tap sorting network along the mouse-angle axis, spans bounded by depth interval.
KEEP VERBATIM: 25-comparator network, interval-bounded spans, drip overrun, rank ramp, seam CA, 4 sliders.
ADD: 4. sorted-tap contact occlusion — count sorted taps nearer than centre by 0.02–0.4 → AO darkening (uses the sort's own depths).
     5. far-end aerial haze — high-rank picks lose contrast toward the span's depth-weighted average.
FORBID: luma keys, springs, palettes. A PACKING: linear pre-ACES RGB, .a = depth (unchanged).

SHADER: mouse-pixel-sort (2nd pass)
IDENTITY: pointer-local Asendorf luma-interval sort along V/H with FBM/voronoi threshold.
KEEP VERBATIM: interval loop, offsets layers, curl warp, trail tint, C ghost, params.
ADD: 3. held-pointer radial comb — mouse-down bends the sort axis radially from the cursor.
     4. span-head glint — pixel whose next tap leaves the threshold band = leading edge, lit with its sorted colour (treble).
FORBID: AO/haze (fork-mate), new springs. A PACKING: ACES display RGBA (unchanged).

SHADER: luma-pixel-sort
IDENTITY: 9-tap golden-angle neighbourhood sorted by luma, median→brightest pick, cosine span tint.
KEEP VERBATIM: 25-comparator network, threshold/zero-radius early exits, bass threshold drop, palette tint, params.
ADD: 1. anisotropic span axis — squash disk across the axis so Sort Angle (dead at HEAD) steers streaks.
     2. sticky spans — C.a sorted coverage latches a −0.08 threshold so spans persist.
FORBID: radial comb, interval walking. A PACKING: ACES display RGBA, .a = sorted coverage.
