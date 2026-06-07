# gen-hyperbolic-tree — Kimi Notes

## Changes
- Temporal growth depth modulation: `bass` dynamically varies recursion depth (5–12) over time.
- Chromatic branch tips vs trunk separation: trunk warm amber, leaf tips cool cyan/blue.
- Audio-reactive sway amplitude: `mids` increase branch oscillation, `treble` adds leaf flutter.
- Temporal branch glow persistence via `dataTextureC` for organic afterimages.
- `dataTextureA` written for downstream access.

## Wow-Factor
- Tree grows and shrinks with bass drops — a fractal organism breathing to music.
- Chromatic trunk-to-tip gradient gives the tree a bioluminescent quality.

## Risks
- Recursive branching with `hash12` per node can diverge on GPUs without robust `dot` precision.
- Depth modulation causes pop-in when bass threshold crosses integer boundaries; `smoothstep` eases transitions.
