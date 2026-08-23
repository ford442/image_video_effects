# Reaction / flow / sand shader notes

- Both RGBA reaction-diffusion effects keep raw chemical concentrations out of
  ACES; only their presentation colors are tone-mapped.
- RD on Video stores state only in A and now emits a valid semantic-alpha
  preview even before later linear passes run.
- Luma Flow and Optical Flow Dream use exact integer history advection. Optical
  Flow Dream no longer declares binding 13, reads `extraBuffer[4]`, or consumes
  graph-runner passes.
- Sand Dunes owns a physical height/loose/velocity/moisture tuple. Sand Dunes
  RGBA owns four grain fractions. Pixel Sand intentionally migrates the legacy
  B-state into raw A density/velocity/energy state.
- Cymatic Sand persists density, radial transport, resonant energy, and click
  memory; Photonic Caustics persists HDR irradiance and coverage.
- No cohort shader writes `dataTextureB` or `extraBuffer`. Pointer position,
  held state, and click wavefronts come from canonical uniforms/ripple events.
