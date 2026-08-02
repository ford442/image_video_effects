# Batch 23: `gen-bioluminescent-reaction-diffusion`

- Clamped all nine reaction-diffusion stencil loads to valid image coordinates.
- Removed the invalid 256-entry `plasmaBuffer` palette assumption. Color is now
  derived from raw A/B species state, with bounded FFT shimmer from bins 1–8.
- Wired the existing controls directly to display intensity, simulation speed,
  spatial diffusion scale, and mouse seed radius/strength.
- Kept raw `(A, B, 0, 1)` simulation state in `dataTextureA`; tone mapping is
  display-only and source depth remains pass-through.
- Parameter indices/defaults/ranges and the 13-binding layout are unchanged.

