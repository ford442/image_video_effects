# Codex (c) Liquid Shader Complexity Batch

## Scope

Upgrade ten named single-pass liquid effects without changing renderer code,
runtime APIs, canonical uniforms, bindings 0–12, 16×16×1 workgroups, saved
`params`, or the engine's B→C then A→C feedback order.

## Cohort contract

- Bass, mids, and treble come from `plasmaBuffer[0].xyz` and drive visibly
  distinct behavior.
- Hover remains active; held input is materially stronger. Pointer and click
  distances are aspect-correct.
- Click loops cap at 50 and reject future and expired timestamps.
- C history/state reads are bounded exact `textureLoad` operations. Only A is
  written; B and `extraBuffer` remain unused.
- Display-history A contains final ACES-mapped RGBA. Stateful A remains bounded
  raw state using the documented packing.
- Output alpha derives from source coverage plus each effect's liquid thickness,
  displacement, Fresnel, melt, vortex, pressure, or trail contribution.

## Effect briefs

- **Liquid Smear:** five-tap anisotropic paint advection, streamline diffusion,
  drag wakes and click eddies; bass widens, mids bends, treble lights ridges.
- **Liquid Tensor Vortex:** source-luma structure tensor, eigenvector/coherence
  advection, moving curl vortices and metallic fold lighting. Remove the generic
  Batch 63 clock-ring overlay and its duplicate declarations.
- **Liquid Rainbow Prismatic:** Cauchy RGB dispersion, animated thin-film
  thickness, six-tap caustics, held lens deformation and prismatic fronts.
- **Liquid Perspective:** perspective-compressed Gerstner sheet, parallax
  Jacobian, silhouette-safe refraction and secondary shear.
- **Liquid RGB:** wavelength-specific vortex advection, Cauchy split,
  Beer–Lambert absorption and chromatic caustic seams.
- **Liquid Viscous:** exact-load semi-Lagrangian reconstruction, viscosity
  diffusion, one-frame Jacobi pressure, confinement and dye roll-up.
- **Liquid Viscous Simple:** laminar streamlines, four-tap cohesion,
  shear-thinning response and spectral surface sheen.
- **Liquid Zoom:** three depth layers, moving refractive surface, zoom-coupled
  vortices, click lenses and bounded trails.
- **Luma Melt Interactive:** luma-thresholded branching rivulets,
  heat-dependent viscosity and aspect-correct melt fronts.
- **Viscous Drag:** diffused four-channel drag state, traveling jets, pressure
  buildup, elastic recovery and illuminated ridges.
