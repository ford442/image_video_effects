# gen-lorenz-attractor — Kimi Notes

## Changes
- Chromatic lobe separation: right lobe (positive x) warm gold/amber, left lobe cool cyan/blue.
- Audio decay modulation: `bass` subtly increases temporal decay for beat-driven flicker.
- Depth output from accumulated density for downstream depth-aware effects.
- Monte Carlo contribution split into R and B channels for chromatic density mapping.

## Wow-Factor
- The butterfly now has colored wings — each lobe glows with its own spectral identity.
- Bass-driven decay makes the attractor shimmer in time with music.

## Risks
- Separate R/B Monte Carlo accumulation doubles the per-pixel loop body; still 52 iterations total but more ALU.
- Lobe color mixing at center can desaturate; `smoothstep` transition width is tuned to preserve contrast.
