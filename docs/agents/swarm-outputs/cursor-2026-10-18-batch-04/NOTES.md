# Cursor batch-04 — Notes

2026-10-18. Cards were written before the WGSL. Real-GPU visual QA is external.

## aurora-rift-pass1

Kept: curl parallax, foam, 4D noise, interference, Birkeland curtain folds, the three emission lines, diffusion-rate temporal mix, video passthrough on writeTexture.

Added: rayed beads climbing the curtain; a dark gap under the curtain.

A packing: raw volumetric (color, density). Not tone-mapped.

The pasted uniform struct listed `zoom_params` before `zoom_config`, so the sliders were reading the mouse and Scale was reading time. The file now includes `_prelude.wgsl`. Scale, Flow Speed, Diffusion Rate, and FBM Octaves read `zoom_params`. Depth parallax stays tied to Flow Speed at the old default gain (0.5 → 0.4). The emission threshold is fixed at the old default 0.175 so Diffusion Rate is the temporal mix.

## aurora-rift-pass2

Kept: chromatic dispersion, quaternion hue, spectral power, sky haze, grade, vignette, ACES on the display.

Added: airglow limb (Scale = thickness, Flow Speed = drift); Rayleigh reddening (FBM Octaves = fine haze, and it still opens the chromatic spread).

A packing: A echoes the volumetric handoff (aurora color, density). The graded picture is writeTexture only. `dataTextureC` is `textureLoad`. There is no early return, so every pixel updates A. `config.y` is the ripple count, so it is no longer used as a grade intensity.

## aurora-rift-2-pass1

Kept: vortex tubes, substorm flashes, diffusion mix, the same volume family as pass 1.

Added: omega-band tongue; poleward picket fence.

A packing: raw volumetric. Same prelude / slider correction as pass 1. Emission threshold fixed at the old default 0.25. Depth parallax stays on Flow Speed (default 0.5 → 0.4).

## aurora-rift-2-pass2

Kept: dispersion, quaternion hue, purple sky, dual glow, grade, vignette, ACES on the display.

Added: STEVE mauve arc (Scale = width, Flow Speed = drift); nitrogen pink lower border.

A packing: A echoes volumetric (color, density). Exact loads. No early return.

## gray-scott-tank

Kept: feed / kill / diffusion / seed, 5-point Laplacian, hold and click seeding, A = (U, V, age, seed mask) on step, inject, and render. ACES only on the render's writeTexture.

Added, and where:
- step: tangent stretch of V; feed shadow that hollows a dense spot
- inject: paint comet behind the pointer (`extraBuffer[133..137]`, writer at (0,0))
- render: iso-V threads at 0.36 and 0.70

The old spontaneous seeds used `floor(time * 0.7)`. They are now slow pulses in fixed cells, so the tank still gets inoculated without teleporting spots.

Inject and render were migrated onto the prelude. Step already included it.

## liquid-viscous

Kept: the Navier–Stokes path, slider roles (viscosity, confinement under the Turbulence name, injection under Ripple Strength, hue under Color Shift), raw A, diagnostic B.

Added: Ekman veer of velocity with picture depth; Rayleigh–Plateau beads on quiet dye threads, stronger as viscosity drops. Beads are inside the ACES argument.

## gen-superfluid-quantum-foam

Kept: necks, black-film pop, Kelvin line, second sound, reconnection sparks, the existing spring, premultiplied display history.

Added: Abrikosov dimples on the bubble radius; Andreev sheen on the silhouette.

## gen-gravitational-ferrofluid-singularity-engine

Kept: sphere SDF, Rosensweig crests, photon-ring sheen, droplets, click rings, display-history A.

Added: Lense–Thirring frame drag on the inner spikes (viscosity resists); an amber ISCO ring outside the photon ring.

Migrated onto the prelude. The struct order was already canonical.

## hyper-tensor-fluid-coupled

Kept: structure-tensor eigenflow, semi-Lagrangian velocity and density, mouse stir, click bursts, A = (velocity, vorticity, density), pointer stash at pixel (0,0).

Added: Weissenberg pile-up of density on the tensor edge; die swell along the minor axis downstream of an edge.

Floor that was part of making those ideas real:
- `dataTextureC` is exact bilinear `textureLoad` (it was a filtering sample of rgba32float).
- Audio is `plasmaBuffer[0].xyz`. It had been `zoom_config.x`, which is time.
- Edge weight is the structure-tensor trace. It had been `length` of an already-normalized eigenvector, which is 1 everywhere, so the edge mix never saw the photo.
- Display RGB is ACES. A is still the raw field.

## wave-equation-rgba-fluid

Kept: the wave equation, foam on the downhill face, dye stretch, raw (height, velocity, pressure, dye).

Added: Stokes drift of the dye, second order in height; capillary ripples on the uphill face, also added as a small height kick.

## Gates

Naga 12/12 on the touched WGSL. Precommit 12/12. extraBuffer audit pass (1434 files, 0 new violations). Dead sliders: 0 new on the nine definitions that declare params (`gen-superfluid-quantum-foam` has no `params` array). Prelude tracker consistent. Jest 159 suites, 1332 passed, 1 skipped. `SKIP_WASM_BUILD=1 npm run build` succeeded. Ledger `--ids` for the ten catalog ids.

Real-GPU visual QA: external.
