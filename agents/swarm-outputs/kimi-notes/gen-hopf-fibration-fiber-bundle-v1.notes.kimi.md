# gen-hopf-fibration-fiber-bundle v1 Notes

## Concept
Hopf fibration S³ → S² visualization. Each point on S² has a fiber that is a circle in S³.
Stereographic projection from S³ to R³, then to 2D screen, renders linked circles.

## Algorithm
- 40 fibers sampled on S² base space
- Each fiber is a circle in S³ parameterized by t ∈ [0, 2π]
- For each t step, compute S³ coordinates, rotate in 4D, stereographically project to 2D
- Per-pixel distance to line segments between consecutive projected points
- Accumulate glow with depth ordering via w-coordinate

## Visual Design
- Each fiber colored by its S² coordinate (HSV mapping)
- Linked circles shown with depth fade
- HDR bloom at crossing points where depth changes rapidly
- Chromatic aberration on bright 4D-depth regions
- ACES tone mapping

## Audio Reactivity
- Bass: rotates 4D projection angle
- Mids: controls fiber thickness
- Treble: adds particle drift specks and crossing bloom

## Interactivity
- Mouse rotates the S² base space (when clicked)
- Zoom params control 4D rotation and fiber thickness

## Alpha Semantics
Alpha = fiber_density × crossing_intensity × depth
Dense regions with more crossings and closer depth are more opaque.

## Params
1. rotation (p1): 4D rotation angle offset
2. thickness (p2): Fiber thickness
3. bloom (p3): Crossing bloom strength (not currently wired — future)
4. drift (p4): Particle drift intensity (not currently wired — future)

## Performance
40 fibers × 32 segments ≈ 1280 line segments per pixel. Acceptable on modern GPU.

## Validation
- naga: PASS
