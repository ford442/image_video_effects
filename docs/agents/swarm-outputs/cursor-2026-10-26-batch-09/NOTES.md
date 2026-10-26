# Cursor batch-09 — notes

2026-10-26. Cards in `BRIEFS.md` were written before the WGSL edits.

Saved `params` were not renamed or re-defaulted. Seven pasted headers migrated to `#include "_prelude.wgsl"` (`liquid-warp-interactive`, `ink-bleed-fluid`, `liquid-swirl`, `ferrofluid`, `hyper-tensor-fluid`, `sim-fluid-feedback-coupled`, `mouse-fluid-coupling`). That swap is not the upgrade. `src/contracts/prelude_migration.json` dropped those seven ids from `pending`.

## liquid-tensor-vortex

Kept the 6-wave spectral tensor, Rankine pointer, Q criterion, principal strain, cohesion, metal cosine, and click rings. A stays ACES display RGBA.

Added a pressure-well tilt of the existing normal where Q > 0 (the plate darkens in the eye) and stretch filaments along the principal axis, gated by the shear ridge. No §12.2 row.

## liquid-warp-interactive

Kept 4-wave spectral flow, RK2, pointer stir/suck, Coanda attachment, strain caustics, and the viscosity memory weight. B aux packing unchanged.

Added MacCormack on the display history (§12.2D) and a waterline peaked on the existing depth-boundary mask.

## ink-bleed-fluid

Kept velocity/pressure/ink packing, the Jacobi step, the existing vorticity kick, the brush, paper capillary, and wet-edge darkening.

Added an isotropic 9-point viscosity stencil at the same coefficient (§12.2D) and paper-pit granulation on the display only (§12.2C).

## rain-ripples

Kept the primary cosine click ring, Voronoi drops, FBM micro-ripples, caustics, thin film, wet mask, and the spring in `extraBuffer[133..138]`.

Added a two-front dispersive train behind each click (§12.2D, scaled by Detail) and a Worthington bead on the existing Voronoi center (scaled by Scale). A still stores pre-ACES HDR.

## liquid-swirl

Kept Lamb-Oseen `flowField`, the satellite pair, the spring in `extraBuffer[133..136]`, midpoint transport, and strain caustics.

Added the Oseen eye wall at 1.12091 × core radius and stagnation beads where shear is high and speed is low. No §12.2 row.

## honey-melt

Kept the hex grid, melt radius/softness, gravity sag, honey SSS, and Beer-Lambert alpha. A stays ACES display RGBA.

Comb-wall capillary was named in the previous header and absent from the body. It is now a wick along the hex wall (darker amber, tangent sample offset, extra thickness). Added a melt-front meniscus (§12.2D) widened by edge softness.

## magnetic-ring

Kept three rings, spoke counts, FFT bins, the C.a wake, and pointer texels (0,0) and (1,0).

Added upstream compression of ring radius from `dot(safeDir, vel)` and a 1/r³ dipole haze between the strokes. No §12.2 row (the haze is a dipole, not the soft-inverse-square row).

## ferrofluid

Kept `domainHeight`, runners, click fronts, hue rotate, and the C trail. A stays pre-ACES HDR.

Added labyrinth fingers outside the spike envelope (folded into the normal taps) and tip beads that round the normal and add a cap specular (§12.2D).

## hyper-tensor-fluid

Kept velocity/anisotropy/dye packing, the luma tangent, noise curl, stir, and the ribbon.

Added tangent-weighted viscosity on the existing four taps, and MacCormack on the dye (§12.2D) before the same 0.985 fade. ACES stays on `writeTexture` only.

## sim-fluid-feedback-coupled

Kept the Jacobi pressure step, vorticity confinement, buoyancy, and schlieren. A stays raw velocity/pressure/density.

Added shallow-water continuity on the divergence the pressure step already computes (§12.2D) and a baroclinic torque from the density and pressure gradients, before the existing velocity clamp.

## mouse-fluid-coupling

Kept viscosity as decay, stir radius, absorption tint, the in-radius perpendicular kick, click injection, and edge damping. A stays raw `(vel.xy, vorticity, density)`.

The (0,0) mouse store was overwritten by the fluid write every frame. Previous mouse now lives in `extraBuffer[133..134]` with a seeded flag at `[136]`, single writer `(0,0)`. History reads are four `textureLoad`s, not a filtering sample of `dataTextureC`.

Added speed-thinning density under the drag (§12.2C) and a Kármán street in the wake, scaled by vortex strength.

## gen-abyssal-ferrofluid-singularity

Kept the sphere + gyroid `smin`, the held magnetic warp, the orbiting camera, and the four params. Bass still scales spike density. Treble still scales core glow.

Added five-tap AO along the normal (§12.2E) and SDF curvature wear (§12.2E): positive curvature holds the specular, negative curvature darkens creases. A is ACES display RGBA. Alpha is coverage, not 1.

## Floor

`upgraded-rgba` added to `hyper-tensor-fluid`, `mouse-fluid-coupling`, and `gen-abyssal-ferrofluid-singularity`. `audio-reactive` added to `sim-fluid-feedback-coupled` and `gen-abyssal-ferrofluid-singularity` (both already read `plasmaBuffer[0]`). `mouse-driven` added to the abyssal features list because the held warp was already there.

## Gates

Naga 12/12. Precommit 12/12, extraBuffer violations 0 on these files, pasted headers 0. Full-catalog dead sliders: 0 new. Full-catalog extraBuffer: 0 new violations. Duplicates: 1408 unique ids. Catalog lists regenerated for the four definitions whose features changed. Vitest: 169 files, 1435 passed, 1 skipped. `SKIP_WASM_BUILD=1 npm run build` succeeded. Ledger recorded these 12 ids only.

Real-GPU visual QA is external. This VM has no hardware GPU.
