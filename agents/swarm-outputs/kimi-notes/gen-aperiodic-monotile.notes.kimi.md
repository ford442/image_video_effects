# gen-aperiodic-monotile — Kimi Notes

## Changes
- Temporal tile mutation: slow phase shift in distance field driven by `time`.
- Chromatic edge refraction: outer edges glow red, inner edges blue for 3D relief effect.
- Mouse-scale interaction refinement: mouse X drives rotation, Y drives scale offset.
- Bass-driven scale pulse: tile density breathes with low frequencies.
- Temporal color persistence via `dataTextureC` blend.

## Wow-Factor
- Aperiodic hat tiling with prismatic edge glow feels like a living Penrose floor.
- Bass-driven scale pulse makes tiles “breathe” in time with music.

## Risks
- Distance field approximation is coarse; edges may show stepping artifacts at high magnification.
- `hash12` per tile is cheap but tile ID generation has floating-point precision limits at extreme scales.
