# gen-holographic-lens-flare-matrix — Kimi Notes

## Changes
- Chromatic dispersion per flare: RGB star shapes offset by angular phase, creating prismatic halos around each cell.
- Temporal flare persistence: `dataTextureC` density burns in at 8–11% per frame for afterglow trails.
- Bass-driven flare birth/death: low frequencies modulate core size and brightness.
- Depth-aware compositing: `readDepthTexture` dims flares behind scene depth.

## Wow-Factor
- Grid of lens flares with per-star chromatic aberration looks like a field of tiny prisms.
- Persistent afterglow makes the matrix feel like phosphor on a vintage display.

## Risks
- Grid density can reach 15×15 = 225 flares; each with 3 channel evaluations = moderate ALU cost.
- Depth read adds one more fetch; total still within budget for most GPUs.
