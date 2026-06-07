# Algorithmist Upgrade Notes: gen-buddhabrot-aura

## Key Additions
1. **Burning Ship Hybrid** — Upgraded the core Mandelbrot iterator to Burning Ship (`abs(z.x)`, `abs(z.y)` before squaring) for sharper, more aggressive orbit trajectories.
2. **Multi-Orbit Trap Accumulation** — Replaced single `orbitTrapColor()` with `multiTrapColor()` combining point, circle, and line traps for richer iridescence.
3. **Halton Quasi-Random Sampling** — Replaced `hash22`-based jitter with base-2/base-3 Halton sequences for lower-discrepancy anti-aliasing.
4. **Domain-Warped FBM Nebula** — Added `warpedFBM()` to the background nebula color, creating living, organic cloud texture behind the fractal.
5. **Smooth Exponential Zoom** — Added `exp(time * 0.03)` slow drift to the zoom scale for cinematic motion.
6. **Semantic Alpha Preserved** — Alpha still encodes `density * escapeVel * depth`.

## Line Count
~162 lines (target ~180, within ±20%).

## Issues / Warnings
- None. No `tan()` calls. `textureSampleLevel` used where applicable.
