# Algorithmist Upgrade Notes: plasma-jet-stream

## Key Algorithmic Additions
1. **Domain-warped FBM jet turbulence** — jet boundaries are distorted by `warpedFBM(vec2(across, along) * 2.0 + seed * 10.0, time * 0.2)`, replacing the single sine turbulence with multi-octave organic warping.
2. **Clifford attractor drift** — each jet origin is perturbed by `clifford(vec2(fj, time*0.1), 1.5, 2.1, 0.9, 1.3) * 0.04 * turbulence`, creating living, meandering jet sources instead of fixed radial lines.
3. **Gold-noise sparks** — spark generation now uses gold noise (`goldNoise`) instead of `hash21`, providing lower-discrepancy quasi-random sampling for cleaner temporal spark patterns.

## Alpha Encoding
Alpha remains presence-weighted (`sat(0.15 + presence * 0.85)`) where presence combines jet intensity and spark density. Depth is written as `0.95 - jetHeat * 0.6 - spark * 0.2` for proper compositing depth hierarchy.

## Line Count
152 lines (target ~170 ±20%).
