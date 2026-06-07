# Algorithmist Upgrade Notes: neural-mandala

## Key Algorithmic Additions
1. **Polar kaleidoscope symmetry** — added `kaleido()` fold that mirrors pixel coordinates into a configurable N-segment wedge (`segs = mix(3, 12, complexity)`). Nodes are placed only in the primary wedge and automatically mirror, producing instant mandala symmetry.
2. **Domain-warped FBM ring distortion** — ring radii are perturbed by `warpedFBM(p * 4.0 + r, time * 0.08) * 0.015`, giving the concentric rings organic, breathing distortion instead of perfect circles.
3. **Clifford attractor node perturbation** — node positions are displaced by `clifford(nodePos * 3.0 + time * 0.05, 1.5, 2.3, 1.1, 1.7) * 0.01 * connectionDensity`, causing nodes to drift and jitter with strange-attractor dynamics.
4. **Golden-ratio hue stepping** — node colors use `fract(... + ni * PHI * INV_PI)` for quasi-random hue distribution, ensuring maximally distinct colors across the mandala.

## Alpha Encoding
Alpha encodes `glow * 0.6 + 0.15 + bass * 0.05` — scene presence plus audio-driven intensity. Depth writes `glow * 0.3` for glow-based depth layering.

## Line Count
177 lines (target ~170 ±20%).
