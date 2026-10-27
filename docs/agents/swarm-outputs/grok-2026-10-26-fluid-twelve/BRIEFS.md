# Idea Cards — Grok (`grok/fluid-twelve`, 2026-10-26)

Written before WGSL edits. Twelve fluid / dye / ferrofluid shaders. Each card adds **two** new ideas. Earlier ideas stay. Saved `params` stay byte-exact. No shared spring, ripple stamp, or IQ palette.

Formula rule: a §12.2 row is used on at most one file here.

Seven pasted headers are migrated to `#include "_prelude.wgsl"` as infrastructure (`fluid-grid`, `spec-runge-kutta-advection`, `sim-slime-mold-growth`, `alpha-fluid-simulation-paint`, `ferrofluid-em`, `sim-ink-diffusion`, `sim-smoke-trails`). That swap is not the upgrade.

`navier-stokes-dye` stays in sync with `scripts/sim_models/nsd_rescue.py`: new ideas are display-only and do not change the stored `(vel, dye, hue)` step.

---

## gen-wave-equation

File: `public/shaders/gen_wave_equation.wgsl`.

IDENTITY: a 2D height/velocity ripple solver — 9-point Laplacian, sine-Gordon, click droplets, bass rain — drawn as water over the photo.
KEEP VERBATIM: Intensity / Speed / Scale / Detail roles; isotropic 9-point stencil; biharmonic dispersion; bathymetric speed; rising-edge droplets in `extraBuffer[133]` and bass kick in `[134]`; Klein-Gordon / sine-Gordon mix; crest caustics; whitecaps. A stays `(height, velocity, energy, waveIntensity)`.
MECHANISM:
- tactic 2: a wave that slows in shallow water must grow in amplitude (energy flux). The photo under a crest should bend.
- tactic 3: `bathy` only scales `wave_speed`. Neighbor heights `e,w,n,s` are fetched for the Laplacian and then discarded as a slope.
- tactic 6: both ideas keep the same raw A. Refraction only changes the display sample of `readTexture`.
ADD:
  1. Shoaling — acceleration is scaled by `inverseSqrt(bathy)`, so the same wave grows where bathymetry already slowed it.
  2. Crest refraction — the photo is sampled along `(e−w, n−s)`, so the picture slides under the existing slope.
FORBID: a new horizontal velocity channel, a Gray-Scott field, an IQ palette, a spring.
A PACKING: raw sim `(height, velocity, energy, waveIntensity)`. ACES on the display mix only.
FORMULA: no §12.2 row (the biharmonic is already the dispersion; Green's-law shoaling is not that row).

## fluid-grid

IDENTITY: a major/minor lattice drawn in a curl-advected domain, shoved by a sprung cursor, with depth obstacles and click eddies.
KEEP VERBATIM: Grid Size / Flow Speed / Distortion / Turbulence roles; `curl2D` + fbm; spring in `extraBuffer[133..138]`; depth-tangent obstacles; alternating click eddies; major/minor rails and junctions; history drift along `uvOffset`. A stays pre-ACES display RGBA.
MECHANISM:
- tactic 2: a cell in a spinning flow should twist its own rails. A cell the cursor is shoving, but that is not spinning, should pile up.
- tactic 3: `curlRaw` is a direction. It is added as a UV offset and never used to rotate the cell. `push` is a scalar mask.
- tactic 6: C is the display history. Neither idea repacks A. The dead `plasmaBuffer[cell+1]` read (runtime never writes those bins) becomes a per-cell phase of `plasmaBuffer[0].z`.
ADD:
  1. Cell spin — minor rails rotate by the local curl heading, scaled by Turbulence, so the lattice twists with the flow. Major rails stay put.
  2. Stagnation bead — where `push` is high and `|curlRaw|` is low, minor rails thicken. The cursor piles the grid where the noise is not spinning.
FORBID: a grid Navier-Stokes solve, vorticity confinement (smoke and the dye solver already own it), an IQ palette.
A PACKING: pre-ACES display RGBA in A (C is that history). ACES on `writeTexture` only.
FORMULA: no §12.2 row.

## spec-runge-kutta-advection

IDENTITY: dye carried by an analytic velocity through an RK4 backtrace, with a counter-rotating mouse pair, strain filaments, and a second-step history LIC.
KEEP VERBATIM: dt / diffusion / vortex strength / feedback roles; `sampleVelocity`; RK4 step; mouse vortex pair; strain filaments; history LIC; click rings. A stays HDR dye RGB + `|vel|`.
MECHANISM:
- tactic 2: elliptic cores (rotation beats strain) should pool, and the filaments should not paint across them. The whole point of RK4 is that Euler lands somewhere else.
- tactic 3: `advectEuler` is in the file and unused. `strain` and `curl` are both computed and then only summed into brightness.
- tactic 6: C is the dye. The residual reads it. Cores are a display tint of the same dye.
ADD:
  1. Okubo-Weiss cores — where `|curl|` exceeds strain, tint the dye cooler and keep the existing filament boost out of that core.
  2. Euler residual — `advectEuler` versus the RK4 landing, as a cool seam. The dt slider (step size) scales it, which is that slider's existing job.
FORBID: replacing RK4 with semi-Lagrangian MacCormack (that belongs on the dye solver), a new palette family, a spring.
A PACKING: HDR dye RGB + `|vel|` in A. ACES on `writeTexture` only.
FORMULA: no §12.2 row.

## sim-slime-mold-growth

IDENTITY: hashed Physarum agents depositing a decaying, diffused trail on the photo, with photo-luma food and vein anastomosis.
KEEP VERBATIM: sensor angle / decay / particle count / randomness; 3×3 diffuse; 20-step sensor steering; mouse and click deposits; photo food; anastomosis. A stays `(trail, diffused, activity, deposit)`.
MECHANISM:
- tactic 2: a real mold eats the substrate, so food stops under a vein, and specks that never joined a vein dry up.
- tactic 3: `diffused` is the neighborhood mean. `trail - diffused` is isolation and is thrown away. Photo food ignores how much trail is already here.
- tactic 6: both ideas write the same trail channel. No new field.
ADD:
  1. Substrate depletion — the existing dark-luma food is gated by `(1 − trail)`, so only the growth margin keeps eating the photo.
  2. Speck evaporation — where this pixel's trail sits above the 3×3 mean, the saved decay rate bites harder. Veins, where trail matches the mean, keep the slider's decay.
FORBID: swapping the sensor loop for a real agent buffer, a Gray-Scott replacement, an IQ palette.
A PACKING: raw `(trail, diffused, activity, deposit)`. ACES on display only.
FORMULA: no §12.2 row (the 3×3 box stays; do not swap in the isotropic 9-point weights).

## particle-disperse

IDENTITY: each pixel is a grain blown off the photo by the cursor, sprung home, with velocity coupling, motion-blur streaks, and dust breakup.
KEEP VERBATIM: Wind Force / Spring Force / Damping / Wind Radius; offset+velocity state; mouse push; 4-tap velocity Laplacian; motion-blur kernel streaks; transmittance dust. A stays raw `(offset.xy, vel.xy)`, never tone-mapped.
MECHANISM:
- tactic 2: a fast grain should coast past home. A grain whose neighbor along the displacement is also displaced is inside a clump and should darken.
- tactic 3: `returnSpeed` is a constant spring. Neighbor offsets are not read; only neighbor velocities are.
- tactic 6: clump shadow reads the same `(offset, vel)` packing one pixel along `sign(offset)`.
ADD:
  1. Ballistic coast — the return spring is divided by speed, so a fast grain keeps its velocity and a slow one still settles. Damping and the spring slider keep their roles.
  2. Clump shadow — darken the grain when the neighbor in the direction of `offset` is also away from home.
FORBID: a fluid solver, audio (the JSON does not claim it), a new palette, a spring in extraBuffer (the return spring is the offset term this file already has).
A PACKING: raw `(offset.xy, vel.xy)`. ACES on display only.
FORMULA: no §12.2 row.

## alpha-fluid-simulation-paint

IDENTITY: a semi-Lagrangian paint blob — velocity, a Jacobi pressure step, vorticity, mouse and click dye — lit as impasto.
KEEP VERBATIM: viscosity / color-value / vorticity / decay roles; semi-Lagrangian backtrace; audio viscosity; pressure Jacobi; the existing confinement term; mouse and ripple injection; dye-front tension; impasto spec. A stays `(vel.xy, pressure, density)`.
MECHANISM:
- tactic 2: wet paint darkens on the rim and thickens there. Pressure is the squeeze of the blob and should read as relief.
- tactic 3: `pressure` is stored and projected, then ignored by the HSV display. `left/right/up/down.a` are the density neighborhood.
- tactic 6: the wet rim writes a little density back into A.a, which the next frame already advects. Pressure is display-only.
ADD:
  1. Wet-edge bead — `max(−∇² density, 0)` times the density gradient darkens the rim and adds a little density, scaled so decay still wins.
  2. Pressure relief — positive pressure lifts the paint color, suction darkens it, before ACES.
FORBID: a second confinement formula, MacCormack (the dye solver's family this batch), an IQ palette.
A PACKING: raw `(vel.xy, pressure, density)`. ACES on display only.
FORMULA: wet-edge accumulation (§12.2C). Only this file.

## liquid-metal

IDENTITY: a mercury sheet whose raw state is height, vertical velocity, foam, and wetness, relaxed toward a Rosensweig hex lattice, with a cursor magnetic pole, chromatic refraction, and a Ward lobe.
KEEP VERBATIM: viscosity / reflectivity / chromatic spread / flow speed; height solver and equilibrium; hex spike mode; pole core and moat; depth basin; click impulses; Fresnel and Ward anisotropy. A stays `(height, velocity, foam, wetness)`.
MECHANISM:
- tactic 2: the moat around a ferrofluid spike traps scum. The spike tips are where the key light catches.
- tactic 3: `poleMoat` goes negative in the ring and is only added as acceleration. `spikeMode` and `specKey` are both computed.
- tactic 6: foam is already A.b. The trap writes that channel. The catchlight is display-only.
ADD:
  1. Moat foam trap — where `poleMoat` is negative, add foam into the existing foam field so the ring around the cursor spike holds bubbles.
  2. Spike-tip catchlight — extra key specular where the hex mode is a peak and height has reached the equilibrium there.
FORBID: a horizontal velocity channel, the monolith's raymarch, the EM shader's multipole palette, thin-film as the look.
A PACKING: raw `(height, velocity, foam, wetness)`. ACES on display only.
FORMULA: no §12.2 row.

## ferrofluid-em

IDENTITY: multipole electromagnetic ferrofluid — equipotential ridges, directional spikes, Poynting runners, coalescence bridges, Earnshaw wobble, Hall drift — displacing the photo.
KEEP VERBATIM: spike frequency / field gain / conductivity / color phase; charge multipoles; sprung mouse charge in `extraBuffer[133..138]`; coalescence snap; Earnshaw wobble; Hall displacement; display persistence along the drift. A stays HDR display RGBA.
MECHANISM:
- tactic 2: ridges pack tighter where `|B|` is stronger. A conductive fluid remembers a spike for a moment after the field leaves.
- tactic 3: `magnitude` scales height but not the angular frequency. Previous-frame luma is only used after the ridge is built.
- tactic 6: remanence reads C at this pixel (display color) and adds it into the ridge the height already uses.
ADD:
  1. Local ridge packing — the directional cosine frequency rises with `|B|`, and the coalescence neighbor uses that same packed frequency.
  2. Remanent spikes — previous-frame luma, scaled by conductivity, holds ridge height so a spike fades instead of vanishing in one frame.
FORBID: a height-field solver (that is liquid-metal), an SDF obelisk, an IQ palette swap.
A PACKING: HDR display RGBA (ACES on `writeTexture` only). Unchanged.
FORMULA: no §12.2 row.

## sim-ink-diffusion

IDENTITY: three-channel Gray-Scott ink on paper, fibres stretching the Laplacian, a coffee ring where the ink gradient is steep.
KEEP VERBATIM: wetness / viscosity / feed / color mixing; per-channel feed/kill patterns; anisotropic 9-point Laplacian along `fiber`; mouse drop; coffee-ring pile-up into V. A stays `U.rgb + V`.
MECHANISM:
- tactic 2: thin ink granulates in the paper pits; pigments of different solubility travel different distances along the fibre.
- tactic 3: `paper` scales diffusion and the paper color, then the mixed ink is flat. `fiber` is a direction used only by the Laplacian.
- tactic 6: granulation and the split are display-only. Stored U/V stay the reaction state.
ADD:
  1. Paper granulation — thin ink (low `|U|`) is multiplied by the existing paper hash. Thick ink stays smooth.
  2. Chromatographic split — display G and B are loaded a few pixels along `fiber`, scaled by Color Mixing. Stored U is not shifted, so the solver is the same.
FORBID: replacing Gray-Scott, a nib spring, an IQ palette.
A PACKING: raw `U.rgb + V` in A.a. ACES on display only.
FORMULA: paper granulation (§12.2C). Only this file.

## gen-ferrofluid-monolith

IDENTITY: a raymarched twisted obelisk with a Rosensweig cone lattice, a pointer magnet, chrome that reflects the core beam, and iron-filing dipole lines.
KEEP VERBATIM: Monolith Height / Spike Strength / Field Speed / Core Glow; box + spike shell + core; counter-helix cones; pointer magnet pull; core-beam reflection; filing lines; click rings; 6% history mix. A stays raw HDR display RGBA.
MECHANISM:
- tactic 2: grooves between cones should darken. Cone tips should run hotter than the shaft.
- tactic 3: the march already has a hit normal and a travel distance. The lattice weight is computed inside the SDF and discarded at the hit.
- tactic 6: C is the HDR history. AO and tip heat are display terms mixed into that same color before the history blend.
ADD:
  1. Crevice AO — five taps along the hit normal through the existing map, darkening the grooves between cones.
  2. Cone-tip heat — the same lattice weight, evaluated at the hit, adds a warm glint on the peaks, scaled by Spike Strength. The core material stays the core color.
FORBID: a second SDF primitive, a height-field sheet, filing logic copied onto the EM shader.
A PACKING: raw HDR display RGBA history. ACES on `writeTexture` only.
FORMULA: step-count AO (§12.2E). Only this file.

## sim-smoke-trails

IDENTITY: a buoyant smoke plume — density, temperature, velocity — with curl noise, vorticity confinement, and cooling as it climbs.
KEEP VERBATIM: density / turbulence / rise / dissipation; buoyancy from temperature; curl noise; vorticity confinement; altitude cooling; bottom, mouse, and click sources. A stays `(density, temp, vel.xy)`.
MECHANISM:
- tactic 2: cold dense smoke should stop climbing and settle. A plume entrains, pulling sideways toward the column.
- tactic 3: `smokeDensity` only tints and advects. Neighbor densities are loaded for confinement and then ignored as a horizontal force.
- tactic 6: both terms write the existing velocity channels before the same advection.
ADD:
  1. Dense settling — cool smoke (`density * (1 − temp)`) sinks, scaled by the Rise slider so that slider still owns the vertical rate.
  2. Lateral entrainment — velocity steps toward the denser neighbor, scaled by Turbulence.
FORBID: a second confinement term, a dye hue field, an IQ palette.
A PACKING: raw `(density, temp, vel.xy)`. ACES on display only.
FORMULA: Boussinesq density half (§12.2D). Only this file. Temperature buoyancy is already in the file and stays.

## navier-stokes-dye

IDENTITY: semi-Lagrangian Navier-Stokes dye — meandering jet, held radial push, vorticity confinement, divergence damping, filament runner — tinting the photo.
KEEP VERBATIM: viscosity / turbulence / ripple strength / color shift; the velocity, dye, and hue update (numpy model in `scripts/sim_models/nsd_rescue.py`); confinement; divergence step; filament runner and vortex ribbon; analytic palette. A stays `(vel.xy px/frame, dye, hue)`.
MECHANISM:
- tactic 2: dye smears along its velocity. A vortex core is slower than its rim and should read as an eye.
- tactic 3: `vel` and `curl` are computed for the step and then only scale saturation and the palette.
- tactic 6: neither idea writes A. The stored step matches the numpy gate.
ADD:
  1. Velocity streaks — the display samples the photo a few pixels upstream along `vel` and tints that sample with the dye color.
  2. Vortex eye — where `|curl|` is high and speed is low, the display cools, so the core of a plume is an eye. Turbulence scales it.
FORBID: changing the velocity or dye update, MacCormack on the stored field, a new palette family.
A PACKING: raw `(vel.x, vel.y px/frame, dye, hue)`. ACES on `writeTexture` only. The stored step is unchanged, so `nsd_rescue.py` stays the model.
FORMULA: no §12.2 row.
