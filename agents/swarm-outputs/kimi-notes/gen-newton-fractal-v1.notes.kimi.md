# gen-newton-fractal — New Shader Notes

## Overview
Newton's method basins of attraction for complex polynomials z^n - 1, rendered with root-based coloring, smooth iteration shading, HDR boundary bloom, and ACES tone mapping.

## Algorithm
- For each pixel, map to complex plane and apply Newton iteration z → z - (z^n - 1) / (n*z^(n-1))
- Complex power via polar form (length^N * e^(i*N*theta))
- Convergence detected when |dz| < 1e-4
- Root identification via phase angle quantization into N bins
- Five root colors (red, green, blue, gold, magenta) with iteration-darkening
- Smooth boundary bloom using exp(-iterRatio * 10)
- Chromatic aberration on high-iteration regions (R boost, B attenuation)
- ACES filmic tone mapping for HDR control

## Interactivity
- Mouse zooms into boundary regions (zoom center + scale)
- Bass morphs polynomial degree between 3 and 5
- Param1 controls zoom level
- Param2 sets base polynomial degree
- Param3 controls iteration depth (20–90 iterations)
- Param4 controls HDR boundary bloom intensity

## Alpha Semantics
alpha = convergence_confidence × (1 - boundary_darken) × radial_falloff
- High near converged roots, low at boundaries and screen edges

## Wow Factor
- Classic Newton fractal with three-to-five basin coloring
- Glowing electric boundaries between attraction basins
- Smooth audio-driven morphing between polynomial degrees

## Risks
- Generative — no image input
- Division by near-zero in cdiv guarded by 1e-8 epsilon
- High iteration counts (90) may be heavy on low-end GPUs
