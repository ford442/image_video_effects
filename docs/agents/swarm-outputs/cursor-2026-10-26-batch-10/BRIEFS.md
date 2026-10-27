# Idea Cards — cursor/batch-10 liquid, ink, magnetic (2026-10-26)

Written before WGSL edits. Twelve shaders. Each card adds **two** new ideas. Earlier ideas stay. Saved `params` stay byte-exact. No shared spring, ripple stamp, or IQ palette.

Formula cap: surface tension on `luma-melt-interactive` and `slime-drip` only. Every other §12.2 row is on one file. No MacCormack this batch.

`ink-diffusion` and `rgb-fluid` still paste the 13 bindings. Those headers are migrated to `#include "_prelude.wgsl"` as infrastructure, not the upgrade.

---

## magnetic-pixels

IDENTITY: a movable dipole whose flux-function isolines and N/S lobes warp the photo like iron filings, with a hold that freezes and flips the moment.

KEEP VERBATIM: `dipole_field`, `vector_potential`, `flux_lines`; phase in A texel (0,0); hold freezes phase and flips polarity; lobe tints; pole glow; params dipole strength / field radius / metallic / chroma.

MECHANISM INTERROGATION:
- tactic 2: a dipole has a magnetic equator between the poles, not only two colored lobes.
- tactic 3: `cosTheta` is computed for the lobe weight and is zero on that equator. `parallel` along the moment is the filing coordinate and is thrown away.
- tactic 6: C is display except texel (0,0). No new field.

ADD:
  1. Magnetic equator — a dark seam where `m·r` crosses zero, between the existing lobes.
  2. Filing grains — short gaps along the moment, so the warp reads as filings rather than a continuous smear. Metallic still owns sheen and now also the grain pitch.

FORBID: a new solver, a spring, ferrofluid spikes, moving the phase texel.
A PACKING: ACES display RGBA; texel (0,0) phase state unchanged.

---

## liquid-fast

IDENTITY: a fast Hamiltonian liquid warp — divergence-free stream, convective shear, a spring pointer with a drag vortex, and click wave packets.

KEEP VERBATIM: `streamVelocity`; convective shear; spring `extraBuffer[133..138]`; drag vortex and inertial jet; ripple packets; fresnel from the height taps; params response / turbulence / ripple strength / highlight shift.

MECHANISM INTERROGATION:
- tactic 1: the stream returns velocity and throws away its shear.
- tactic 2: a fast drag leaves a thin jet behind the pointer, not only a blob inside the core.
- tactic 3: `pointerVelocity` is the jet direction and is only added inside `dragCore`.
- tactic 6: C is display history. The feedback mix stays.

ADD:
  1. Stream shear caustic — finite differences of the existing `streamVelocity` light a glint where the Hamiltonian field is shearing. Response still scales the clock.
  2. Fast-jet tail — a narrow wake behind `pointerVelocity`, in the same space as the existing inertial jet, quiet when the pointer is still.

FORBID: a new spring, replacing the stream with noise, an IQ palette.
A PACKING: ACES display RGBA (unchanged).

---

## luma-magnetism

IDENTITY: iron filings traced as bidirectional RK2 streamlines of the luma gradient plus a pointer swirl, clumping in strong field, with a held luma-signed pole.

KEEP VERBATIM: `magneticField` / `rk2Step` / bidirectional `fieldLineDensity`; clump and bare caps; held pole from luma under the cursor; params field strength / radius / filament density / depth layer. A stays display RGBA.

MECHANISM INTERROGATION:
- tactic 2: filings pile on the contrast edges that source the field, and cancel where the image gradient opposes the pointer.
- tactic 3: the luma gradient inside `magneticField` is added into the field and never shown as a pile. The pointer term and the gradient are only returned as a sum.
- tactic 6: C is not read. Do not invent history.

ADD:
  1. Contrast pile — extra filament weight from `|∇luma|` at the pixel, inside the existing radius disc.
  2. Cancellation seam — where that gradient opposes the pointer term, the filament breaks and a thin neutral line shows.

FORBID: a dipole rewrite, a spring, changing the RK2 step cap.
A PACKING: ACES display RGBA (unchanged).

---

## luma-melt-interactive

IDENTITY: bright luma melts and drips, with a stored temperature that re-solidifies and a ledge where dark pixels stall the flow.

KEEP VERBATIM: melt mask, branch noise, runners, `curl2D`, gravity, temperature in A.a, ledge stall and lip highlight; params melt speed / trails / heat radius / heat intensity. A stays linear melt RGB + temperature.

MECHANISM INTERROGATION:
- tactic 2: a falling drip has a surface-tension bead on its leading edge, and a cooling spot grows a dull crust.
- tactic 3: the drip phase `sin(uv.y * 62 - time)` is only a packet mask. `hereTemp - temp` is the cooling the memory already implies.
- tactic 6: C.a is temperature. Do not store a new field.

ADD:
  1. Drip-head bead (§12.2D) — a warm highlight on the leading side of the existing drip packet.
  2. Cooling crust — where this pixel's previous temperature is above the advected temperature, pull the color toward luma.

FORBID: a new solver, a spring, repacking A.a.
A PACKING: linear pre-ACES melt RGB; A.a = molten temperature (unchanged).

---

## neon-fluid-warp

IDENTITY: a neon lens under the pointer — curl jet, edge runners, caustics — with a viscous wake, a meniscus specular, and a held clock that slows with liquidity.

KEEP VERBATIM: state texels (0,0) and (1,0) with sentinel -7; wake relaxation; viscous clock; meniscus; palette; params warp / radius / glow / liquidity.

MECHANISM INTERROGATION:
- tactic 2: a fast lens leaves a thinner rim. The wake speed is already computed and only offsets the sample.
- tactic 3: `jetPhase` lights a sine and is not peaked into a crest.
- tactic 6: C history mix stays 14%. Do not move the sentinel texels.

ADD:
  1. Speed-thinned rim (§12.2C) — the existing edge width is `w0 / (1 + k·|wake|)`.
  2. Jet crest — a bright thread where the curl jet's sine peaks, scaled by glow and liquidity.

FORBID: a new palette, a spring, a second wake model.
A PACKING: linear pre-ACES RGBA; sentinel texels unchanged.

---

## slime-drip

IDENTITY: green slime that stretches downward, hangs from the previous drip field, and wipes away under the pointer.

KEEP VERBATIM: anisotropic noise stretch; `drip = max(fresh, prev.r * 0.84)`; wipe; mucus SSS and alpha; params speed / viscosity / amount / tint. A stays raw drip, thickness, tint mask, alpha.

MECHANISM INTERROGATION:
- tactic 2: a real drip swells into a bead at the toe and pinches into a neck.
- tactic 3: neighbors of the stored drip are not read. The vertical drop is the toe; the horizontal ridge is the neck.
- tactic 6: C.r is the drip. Neighbors are the same field.

ADD:
  1. Toe bead (§12.2D) — where this drip exceeds the drip below, a pale green cap and a little extra thickness.
  2. Neck pinch — viscosity narrows the tint where the stored drip is a horizontal ridge.

FORBID: a fluid solver, a spring, packing display into A.
A PACKING: raw drip, thickness, tint mask, alpha (unchanged).

---

## liquid-rgb

IDENTITY: four complex-potential vortices advect the photo on separate R/G/B paths, with Beer-Lambert thickness and a viscous history.

KEEP VERBATIM: `complexVortexField` and its four centers; per-channel rFlow/gFlow/bFlow offsets; Beer-Lambert `absorption`; viscosity as the history mix; params viscosity / turbulence / ripple strength / RGB separation.

MECHANISM INTERROGATION:
- tactic 1: tangential speed of `r / (r² + 0.04)` peaks at r = 0.2. Nothing marks that eye.
- tactic 6: history is one load at the green UV. Red and blue already travel different paths, so their memory should too.
- tactic 2: short wavelengths linger. Separation already splits the paths; it can split the memory the same way.

ADD:
  1. Vortex eye wall — a thin ring at r = 0.2 around each existing center.
  2. Wavelength memory — red history mixes less and blue more, by the separation slider. At separation 0 all three use the same mix.

FORBID: replacing the vortex set, a spring, a new palette as the look.
A PACKING: ACES display RGBA (unchanged).

---

## liquid-rainbow

IDENTITY: three trochoidal Gerstner waves plus a braid, with thin-film color on the crests and a viscous pointer spring.

KEEP VERBATIM: `trochoidalWave` for the three authored directions and amplitudes; braid; spring `extraBuffer[133..138]`; spectral film; chromatic split from the dispersion slider; params viscosity / turbulence / ripple strength / dispersion.

MECHANISM INTERROGATION:
- tactic 1: the three waves use independent speeds, so short waves outrun long ones. Deep water is the other way.
- tactic 2: a Gerstner crest is peaked and the trough is flat and dark. `wave*.z` is the height and is only a film thickness.
- tactic 6: C is display. The feedback mix stays. The dispersion slider keeps the chromatic split.

ADD:
  1. Deep-water dispersion (§12.2D) — phase speed scales as `1/sqrt(k)`, normalized so the middle wave keeps its authored speed.
  2. Crest cusp — a bright peak where the Gerstner heights sum high, and a dark trough where they sum low.

FORBID: a second palette, retuning the dispersion slider into wave speed, removing the film.
A PACKING: ACES display RGBA (unchanged).

---

## ink-diffusion

IDENTITY: sumi ink on paper — advected by curl and paper fiber, with a wet-edge nijimi bloom and a mouse pellet.

KEEP VERBATIM: A = ink, vel.xy, alpha; fiber steer; vorticity kick; brush and pellet; nijimi on the wet edge; params spread / decay / turbulence / density.

MECHANISM INTERROGATION:
- tactic 1: the Laplacian is 5-point, so the bloom prefers the axes.
- tactic 2: when the brush lifts, water runs back and leaves a pale body with a darker rim.
- tactic 3: `wetEdge` and the brush-up state are both known.
- tactic 6: C.r is ink. Corners are the same field.

ADD:
  1. Isotropic 9-point diffusion (§12.2D) — same spread coefficient, corners at 5% so nijimi is not axis-locked.
  2. Sumi backrun — while the pointer is up, the body pales and the wet edge darkens.

FORBID: a new pigment, a spring, packing display into A.
A PACKING: raw ink + vel.xy + alpha (unchanged).

---

## liquid-displacement

IDENTITY: a persistent velocity and height field that refracts the photo, with vorticity confinement and streaks along the flow.

KEEP VERBATIM: A = velocity.xy, height, activity; one pressure gradient step; confinement; spring `extraBuffer[133..138]`; flow-line streaks; params viscosity / pressure / flow speed / turbulence.

MECHANISM INTERROGATION:
- tactic 1: divergence changes height by a constant. Shallow-water continuity weights that by the height already stored.
- tactic 2: flow running into a steep height slope breaks as a bore.
- tactic 3: `heightGrad` and `velocity` are both computed. Their opposition is the bore.
- tactic 6: C stays the sim. Streaks stay a display integral.

ADD:
  1. Shallow-water continuity (§12.2D) — the divergence term is multiplied by height. Flow speed still scales the step.
  2. Bore lip — a bright line where velocity points into a steep height slope.

FORBID: removing confinement or the streaks, a second solver, display RGBA in A.
A PACKING: raw velocity.xy, height, activity (unchanged).

---

## rgb-fluid

IDENTITY: a sine flow field advects the photo, the mouse pushes it, and thickness sets a wavelength-dependent transmission.

KEEP VERBATIM: sine velocity; mouse push; persistence from the viscosity slider; the color-shift rotation; `calculateChannelAlpha` at 650/550/450 nm; params flow speed / viscosity / mouse force / color shift.

MECHANISM INTERROGATION:
- tactic 1: all three channels advect on one UV. The header's dispersion is only an alpha weight.
- tactic 2: Beer-Lambert is claimed and then multiplied into the stored pigment, so it compounds every frame.
- tactic 6: C is read as the advected color. A filtering sample of `rgba32float` is illegal. Four `textureLoad`s replace it. That swap is the floor.

ADD:
  1. Wavelength advection — red lags and blue leads, scaled by the color-shift slider. At shift 0 all three share one path.
  2. Display-only Beer-Lambert — the channel alphas tint the picture. A stores the pre-absorption pigment so the law does not compound.

FORBID: a new flow field, a spring, an IQ palette.
A PACKING: A = linear advected pigment RGB + transmission alpha. ACES on `writeTexture` only.

---

## ink-marbling

IDENTITY: a pigment bath stirred by a spring pointer, combed by a tine rake, and pushed outward by Jaffer drops.

KEEP VERBATIM: spring `extraBuffer[133..138]`; comb rake; Jaffer map; neighbor diffusion; params intensity / speed / scale / detail. A stays pigment.rgb + thickness.

MECHANISM INTERROGATION:
- tactic 1: diffusion is the same on a flat pool and on a vein.
- tactic 2: a drop's ring concentrates pigment into a stone outline. `ring` is computed and only added into `drop`.
- tactic 3: `previous.rgb - neighborState.rgb` is the vein the diffusion already blurs.
- tactic 6: C is pigment. The gall term only changes the mix weight.

ADD:
  1. Gall — diffusion falls where the pigment gradient is steep, so veins stay narrow. Detail still sets the base rate.
  2. Stone outline — the existing drop ring adds thickness and darkens the pigment at the front.

FORBID: replacing Jaffer or the rake, a new palette as the look, packing display into A.
A PACKING: raw pigment.rgb + thickness (unchanged).
