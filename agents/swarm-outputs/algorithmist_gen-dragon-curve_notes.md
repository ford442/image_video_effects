# Algorithmist Upgrade Notes: gen-dragon-curve

## Key Additions
1. **Branchless HSV→RGB** — Replaced the 6-branch if-else HSV chain with a single `hsv2rgb()` using `fract()` and `clamp()`, fully branchless and shimmer-free.
2. **Polar Kaleidoscope Fold** — Added `kaleido()` with animated segment count (1–6 segments over time) for symmetric dragon-curve reflections.
3. **Clifford Strange Attractor Warp** — Added `clifford()` offset to the curve evaluation point, causing the dragon to breathe and distort organically.
4. **Domain-Warped FBM Background Field** — Added `warpedFBM()` that modulates glow intensity, giving the neon lines a living aura that pulses with noise.
5. **FBM Hue Perturbation** — Subtle warped-FBM offset added to hue calculation for temporal color variation.
6. **Semantic Alpha Preserved** — Alpha encodes `curveDensity * turnIntensity * depth`.

## Line Count
~156 lines (target ~180, within ±20%).

## Issues / Warnings
- None. `textureSampleLevel` used for all texture reads. No `tan()`.
