# gen-ifs-fractal-flame — Kimi Notes

## Shader Summary
Iterated Function System (IFS) fractal flame generating organic flame-like attractors via deterministic affine transforms with probabilistic non-linear variations (sinusoidal, spherical, swirl). Features flame palette (deep red → orange → yellow → white hot core), HDR bloom on dense regions, ACES tone mapping, and chromatic aberration on transform boundaries.

## Key Features
- 4 affine contraction transforms selected deterministically per pixel
- Non-linear variations mixed by hash-based selection
- Flame palette with 5-color gradient interpolation
- Audio: bass morphs transform intensity and iteration count
- Mouse: attracts IFS center offset
- Depth: controls overall heat/density scaling
- Temporal feedback: dataTextureC seeds subtle drift

## Parameters
- `zoom_params.x` — Iterations (24-56 steps)
- `zoom_params.y` — Spread (0.8-2.2 zoom)
- `zoom_params.z` — Heat (0.5-2.0 HDR intensity)
- `zoom_params.w` — Chromatic aberration amount

## Alpha Semantics
`alpha = density * flame_temperature * depthFactor`
Represents attractor density multiplied by flame temperature and depth awareness.

## Naga Status
PASS — naga validation successful.
