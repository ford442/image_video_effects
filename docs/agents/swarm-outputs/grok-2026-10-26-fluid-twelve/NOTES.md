# Upgrade Notes — Grok (`grok/fluid-twelve`, 2026-10-26)

Twelve fluid, dye, smoke, and ferrofluid shaders. Idea cards are in `BRIEFS.md` (written first). Each file keeps its previous mechanism and gains two ideas. Saved `params` are byte-exact.

Seven pasted headers were migrated with `migrate_to_prelude.py` (`fluid-grid`, `spec-runge-kutta-advection`, `sim-slime-mold-growth`, `alpha-fluid-simulation-paint`, `ferrofluid-em`, `sim-ink-diffusion`, `sim-smoke-trails`). That swap is not the upgrade.

`navier-stokes-dye` display ideas do not change the stored `(vel, dye, hue)` step, so `scripts/sim_models/nsd_rescue.py` still matches the solver.

Real-GPU visual QA was not run. This VM has no hardware GPU.

Gates: Naga 12/12, extraBuffer clean, dead sliders clean, `generate_shader_lists.js`. Vitest 169 files / 1435 passed, 1 skipped. `SKIP_WASM_BUILD=1 npm run build` succeeded. Ledger recorded with `upgrades:record`.

## Per shader

### gen-wave-equation
File: `public/shaders/gen_wave_equation.wgsl`.
- Kept: 9-point Laplacian, biharmonic dispersion, bathymetry, sine-Gordon, click droplets, crest caustics, whitecaps. A stays `(height, velocity, energy, waveIntensity)`.
- Added: shoaling (`inverseSqrt(bathy)` on the acceleration); crest refraction of the photo along `(e−w, n−s)`.
- Formula: none. ACES on the display mix only.

### fluid-grid
- Kept: curl flow, sprung cursor in `extraBuffer[133..138]`, depth obstacles, click eddies, major/minor rails, history drift.
- Added: minor rails spin with the curl heading; minor rails thicken where the cursor push cancels the offset. The silent `plasmaBuffer[cell+1]` read is now a per-cell phase of treble (`plasmaBuffer[0].z`).
- Formula: none. A is pre-ACES display RGBA.

### spec-runge-kutta-advection
- Kept: RK4 backtrace, mouse vortex pair, strain filaments, second-step LIC. A stays HDR dye + `|vel|`.
- Added: Okubo-Weiss cores (filaments suppressed where `|curl|` beats strain); the unused Euler step drawn as a residual seam, scaled by the dt slider.
- Formula: none.

### sim-slime-mold-growth
- Kept: sensor steering, 3×3 diffuse, photo food, anastomosis. A stays `(trail, diffused, activity, deposit)`.
- Added: photo food gated by the existing trail so only the margin eats; isolated specks use a faster decay than veins.
- Formula: none. The 3×3 box was not replaced.

### particle-disperse
- Kept: wind, return spring, damping, radius, velocity Laplacian, motion-blur streaks, dust breakup. A stays raw `(offset, vel)`.
- Added: the return spring weakens with speed (ballistic coast); a grain darkens when the neighbor along `sign(offset)` is also displaced.
- Formula: none. No audio added.

### alpha-fluid-simulation-paint
- Kept: semi-Lagrangian step, Jacobi pressure, confinement, dye-front tension, impasto spec. A stays `(vel, pressure, density)`.
- Added: wet-edge bead written back into density; pressure tints the display (squeeze bright, suction dark).
- Formula: wet-edge accumulation (§12.2C). Only this file.

### liquid-metal
- Kept: height/velocity/foam/wetness solver, hex Rosensweig equilibrium, cursor pole, Ward lobe, chromatic refraction.
- Added: foam added where `poleMoat` is negative; extra key specular on hex peaks that have reached equilibrium.
- Formula: none.

### ferrofluid-em
- Kept: multipoles, sprung charge, coalescence, Earnshaw wobble, Hall drift, display persistence.
- Added: directional frequency rises with `|B|` (coalescence uses the same packed frequency); conductivity holds ridge height from the previous frame's brightness above the undisplaced photo.
- Formula: none.

### sim-ink-diffusion
- Kept: three-channel Gray-Scott, anisotropic Laplacian, coffee ring. A stays `U.rgb + V`.
- Added: thin ink multiplied by the paper hash; display G/B sampled along the fibre, scaled by Color Mixing. Stored U is not shifted.
- Formula: paper granulation (§12.2C). Only this file.

### gen-ferrofluid-monolith
- Kept: obelisk, cone lattice, pointer magnet, core-beam reflection, filing lines. Lattice weights moved into `spikeField` with the same expressions.
- Added: five-tap crevice AO along the hit normal; warm glint from `spikeField` at the hit, scaled by Spike Strength. The core material is unchanged.
- Formula: step-count AO (§12.2E). Only this file.

### sim-smoke-trails
- Kept: temperature buoyancy, curl noise, vorticity confinement, altitude cooling, sources. A stays `(density, temp, vel)`.
- Added: cool dense smoke sinks on the Rise slider; velocity steps toward the denser neighbor, scaled by Turbulence.
- Formula: Boussinesq density half (§12.2D). Only this file.

### navier-stokes-dye
- Kept: the velocity, dye, and hue update, confinement, divergence damping, filament runner, palette. A stays `(vel, dye, hue)`.
- Added: display streak of the photo upstream along `vel`; a cool eye where curl is high and speed is low. ACES on `writeTexture` only.
- Formula: none.
