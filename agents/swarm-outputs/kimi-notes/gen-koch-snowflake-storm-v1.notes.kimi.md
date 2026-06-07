# gen-koch-snowflake-storm — New Shader Notes

## Overview
Recursive Koch snowflake fractals distorted by domain-warped fBm turbulence, creating an animated ice-crystal storm with HDR bloom and chromatic edge dispersion.

## Algorithm
- Koch snowflake approximated via polar-coordinate fractal boundary:
  r(θ) = size + Σ sin(θ * 3^(i+1)) * size * 0.18 / 3^i
- Multiple snowflakes (2–5) orbit around center with different phases
- 4-octave fBm domain warping distorts space before SDF evaluation
- Mouse attracts snowflake centers
- Distance-to-boundary used for inside/outside coloring
- HDR glow on edges via exp(-edge * 4)
- Ice palette: pale blue exterior, deep navy interior
- ACES tone mapping

## Interactivity
- Bass drives turbulence intensity
- Mouse attracts snowflake vertices/centers
- Param1 controls turbulence strength
- Param2 controls recursion depth (2–5 harmonic layers)
- Param3 controls snowflake count (2–5 instances)
- Param4 controls chromatic dispersion amount

## Alpha Semantics
alpha = snowflake_density × turbulence_strength × depth
- Stronger during turbulent storms, weaker in calm regions

## Wow Factor
- Beautiful ice-crystal snowflakes that swirl and distort like a frozen storm
- Domain warping creates organic, ever-changing fractal edges
- Multiple orbiting snowflakes create layered depth

## Risks
- Generative — no image input
- SDF approximation is not mathematically exact Koch curve
- Multiple snowflake SDF evaluations increase per-pixel cost
