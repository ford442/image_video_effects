# Sonnet batch 13 — swarm / flock / field-line ten — Idea Cards (written before any WGSL edit)

Batch: `claude-2026-11-01-sonnet-batch-13` · 2026-11-01 · explicit list from the task (sonnet/batch-13): 
fractal-boids-field, fractal-boids-field-coupled, kimi-flock-symphony-em, particle-swarm, particle_dreams_alpha,
gen-trails (file `gen_trails.wgsl`), gen-magnetic-field-warp, magnetic-field, alpha-em-field-simulation, gravity-well-em.
Theme already in the files: swarms/flocks (boids, particles) and electromagnetic / field-line effects.
Ledger: none of the ten has a ledger event (history `[]`); `gen-trails` is the ledger id of `gen_trails.wgsl`.
Existing `Ideas:`/header text in HEAD is NOT re-added: particle-swarm (cohesion+separation, per-band FFT turbulence, spring attractor),
magnetic-field (FFT pole spectrum, cyclotron drift bands), gen-magnetic-field-warp (Larmor gyration, synchrotron emission, Alfvén waves),
alpha-em-field-simulation (LIC along E, recombination flash), gravity-well-em (photon ring halo, frame-drag hue shear).

All ten still paste the 13 bindings + `struct Uniforms` → `migrate_to_prelude.py` (infrastructure, no `Upgraded:` bump for it).

## Findings that shape the cards

1. **`fractal-boids-field` and `-coupled`: time used as audio.** `audioOverall = u.zoom_config.x` — that is engine time, not audio (§3: never `zoom_config.x` as audio).
   `audioReactivity = 1 + time·0.3` scales the flow-field time term, so the flow churns faster without bound (≈ time²). Repair: audio comes from `plasmaBuffer[0].xyz`.
2. **`gen_trails` re-rolls every boid every frame.** `getBoidPosition/Velocity` hash `time*0.01` / `time*0.02` through `fract(sin(·)·43758)`; a 0.017 s step changes the sin argument by ~0.013 rad ×43758 → fully random each frame. The "flock" is frame-rate noise.
   **Packing lie (§8):** A stores `(velR, velG, density, pherLuma)`, but C is read as colour (`history.rgb * 0.92`), so velocity/density were being blended as colour, and the real pheromone lives in B, which is never read back. No bounds guard (`main` writes for every invocation). Per pixel it runs a 180×180 neighbour loop.
3. **`alpha-em-field-simulation`: E never exists.** Nothing sources `eField` (charge and B are injected, E only diffuses from its own zero state), so `eStrength ≡ 0`, the E-hue display and HEAD's "LIC along E" idea never light. The "wave equation" is first-order diffusion.
4. **`particle_dreams_alpha`** (a naga-translated file): slider z is dead (`· 0.0`, the "dead slider consumed" comment); the saved param *names* (particle count / trail persistence / color shift / chaos) do not match what x, y, z, w actually drive (near/far layer speed, —, fog density) — names are saved params and stay. `extraBuffer[0]` is **bass** (engine layout) and is used raw as a UV offset × depth (bass 1 = a whole-screen shift). No ACES; header claims temporal feedback but nothing reads C.
5. `particle-swarm`, `magnetic-field`, `gen-magnetic-field-warp`, `alpha-em`, `gravity-well-em` are consistent already (raw state stays raw, display RGBA stays display); their second pass is ideas only.

Tone-map policy: where HEAD has a tone curve that *is* the look (kimi's Reinhard + pow 0.8) it is kept and recorded; where there is none (fractal-boids ×2, particle_dreams) ACES is added on the display RGB as plumbing.

---

## SHADER: fractal-boids-field
IDENTITY: stateless grid "boids" riding a domain-warped fractal flow field, each drawn as a coloured head with a short straight trail over the source image.
KEEP VERBATIM: 4 params (boid count, flow strength, trail persistence, separation); grid-cell pseudo-boids and their 8-neighbour rules; domainWarpFBM flow; head colour from heading; flow visualisation tint; HEAD click-front/clock-ring spectral overlay (already in the file).
MECHANISM INTERROGATION: tactic 6 — the "Trail Persistence" slider has no history behind it (it only scales a blend); tactic 7 — a boid in a flow leaves a *curved* wake, but the 9 trail dots lie on a straight line along −velocity.
ADD:
1. True trail persistence — boid layer (RGB + density) is stored in A and read back as exact C; the slider now sets the evaporation rate (0.78 … 0.96), so moving boids leave lingering trails across cell boundaries.
2. Flow-bent trails — one extra flow-field sample behind the head gives the local turning of the field; the 9 trail dots follow a quadratic arc instead of a straight line.
REPAIR: `audioOverall` (engine time) → `plasmaBuffer` energy; ACES on display (plumbing).
FORBID: springs, ripples (HEAD already carries the overlay), IQ palette, a real N-body solver.
A PACKING: boid layer in A (linear RGB = boid colour/trail memory, A.a = boid density), read as C `.rgb`; display ACES on `writeTexture`.

## SHADER: fractal-boids-field-coupled
IDENTITY: the same stateless boid field, with a viscous mouse fluid (wake + vortex) entraining the boids and click ripples.
KEEP VERBATIM: 4 params with their double roles; fluid sampler; mouse-velocity state at A/C pixel (0,0) (`xy`); boid rules; wake visualisation; ripple flash; alpha.
MECHANISM INTERROGATION: the description says "click ripples spawn shockwaves through the flock", but the ripple loop only adds a colour flash; the boids themselves never move. Tactic 3 — `sep` (crowding force) and `cohesion` are computed only to steer the heading.
ADD:
1. Alarm scatter — boids near a ripple front get a radial position and heading impulse from that front (Reynolds flee), so the flock actually parts around a click.
2. Crowd-pressure halo — |sep| (how hard neighbours are pushing this boid apart) lights a warm halo around dense knots of the flock.
REPAIR: `audioOverall` (time) → plasma energy; ACES on display (plumbing).
FORBID: copying the sibling's trail history/curved trails (different ideas on purpose), new springs.
A PACKING: unchanged — A(0,0).xy = mouse state, all other pixels unwritten.

## SHADER: kimi-flock-symphony-em
IDENTITY: 2048 hash-placed glowing pseudo-particles bent by an electric/magnetic field launched from the mouse, additive HDR glow, streamline overlay.
KEEP VERBATIM: 4 params; 2048-sample loop; E/B field functions; ripple orbiting secondary charges; EM displacement + hue rotation; streamline overlay; mouse core glow; Reinhard + pow 0.8 tone curve (kept, it is the look); exponential-transmittance alpha; mouse state at A(0,0).
MECHANISM INTERROGATION: tactic 2 — in a plasma the E-parallel push flips with charge sign while E×B drift does not; every particle here is pushed the same way. Tactic 7 — particles are round dots though they have a drift direction.
ADD:
1. Charge-sign two-fluid split — each particle is ±1 from its hash: the E-direct displacement flips with sign (E×B drift stays common), and negatives shift toward cool hue.
2. Drift-stretched particles — each dot is elongated along its own EM drift direction (stretch 1 … 3 with speed), so the swarm streaks along the field instead of dotting.
FORBID: springs, Larmor gyration (gen-magnetic-field-warp's), IQ palette.
A PACKING: unchanged — mouse state at A(0,0), nothing else.

## SHADER: particle-swarm
IDENTITY: boid-cohesion swarm of image offsets (raw sim state: offset+velocity), spring-damped pointer attractor, FFT-band turbulence, HG scattering.
KEEP VERBATIM: everything in HEAD (cohesion, separation, band turbulence, spring pointer in extraBuffer[133..136], click impulses, HG scattering, A raw state = offset+vel, B diagnostics, ACES on display).
MECHANISM INTERROGATION: tactic 1 — Reynolds' three rules are separation, cohesion, **alignment**; HEAD has two. The four neighbour taps already fetch C.zw (velocity) and discard it. Tactic 7 — `motion_blur` is computed from velocity and only scales alpha/depth; the plate is sampled at one point.
ADD:
1. Alignment — steer toward the mean neighbour velocity (C.zw of the same four taps), so flocks move coherently, not just clump.
2. Velocity-aligned motion-blur taps — two extra plate taps along ∓vel, weighted by `motion_blur`, so fast particles actually smear along their travel.
FORBID: new spring, new overlay, changing A/B packing.
A PACKING: unchanged — A raw (offset.xy, vel.xy), B diagnostics; display RGBA on writeTexture.

## SHADER: particle_dreams_alpha
IDENTITY: five layered zoom copies of the image with depth-weighted parallax speeds, click-driven vortex spin, flow-noise wobble, depth-based chroma split, edge glow and fog.
KEEP VERBATIM: 5-layer loop; layer speed mix(x,y); flow noise; vortex spin from the FFT bin read; fog (w); volumetric alpha; edge glow; ping-pong sampling; param ids/names as saved.
MECHANISM INTERROGATION: tactic 4 — slider z is saved as "Color Shift" but is multiplied by zero; per-layer colour is the natural place for it. Tactic 3 — `sampleDepth` is read only as a weight; zoom is the same for near and far content.
ADD:
1. Per-layer colour shift (makes slider z live in its saved role) — each layer's colour is hue-rotated by z·layerDepth·π, so the tunnel's depth reads as a spectrum.
2. Depth-parallax zoom — each layer's zoom is scaled by (1 + 0.25·depth at the layer's pre-zoom sample), so near content zooms faster than far.
REPAIR: `extraBuffer[0]` (bass, used raw as a UV offset) → `plasmaBuffer[0].x · 0.05`; ACES on display (plumbing).
FORBID: new particles, springs, a temporal feedback the file never had.
A PACKING: none written (HEAD writes no A); unchanged.

## SHADER: gen-trails (public/shaders/gen_trails.wgsl)
IDENTITY: 180 audio-reactive Reynolds pseudo-boids in 6 hue-coded flocks drawn as body/wings/trail/streak over the input, with pheromone trails.
KEEP VERBATIM: 4 params (separation, alignment, cohesion, max speed) and audio mappings; Reynolds rule block; body/wing/trail/streak drawing; treble flashes; ACES; B = pheromone + alpha.
MECHANISM INTERROGATION: tactic 6 — the pheromone is written and decays but never displayed or read correctly (see finding 2). Tactic 5 — wings are drawn but never beat.
ADD:
1. Real pheromone trails — A now carries the pheromone colour (fixing the packing lie: A used to hold velocity/density and be read back as colour); it is read through exact C and composited (screen) under the live boids, so deposits evaporate at 0.92/frame.
2. Continuous flight — boid positions follow wrapped straight-line paths from a *fixed* per-boid hash instead of a hash of continuous time (re-rolled every frame), so flocks fly and the pheromone has something to trace. Headings still come from the Reynolds rules.
3. Wing beat — wing width flaps at a rate that rises with speed.
REPAIR / floor: bounds guard; conservative distance cull of the 180-neighbour loop (a boid more than 0.6 from the pixel cannot contribute: streak ≤ 0.4 + one step ≤ 0.08; boids near the wrap edge are never culled).
FORBID: new params, springs, a different flock model.
A PACKING: **changed on purpose, stated here:** A = (pheromone RGB, pheromone luma), read as C `.rgb`. HEAD's A velocity/density tuple had no reader. B unchanged.

## SHADER: gen-magnetic-field-warp
IDENTITY: the image sampled through a warped magnetic field (dipole + curl noise + Clifford attractor), Larmor gyration, synchrotron tint, Alfvén kinks.
KEEP VERBATIM: 4 params; field construction; Larmor gyration; synchrotron colour/polariser; Alfvén rings; A = ACES display RGBA; alpha = radiated energy.
MECHANISM INTERROGATION: tactic 2 — synchrotron emission from gyrating electrons is relativistically beamed: brightness depends on where in the gyration the electron's velocity points toward the observer; HEAD's emission is the same at every gyration phase. Tactic 7 — field direction `field` is known per pixel but the image is only sampled at one point.
ADD:
1. Doppler beaming of the synchrotron term — emissivity × D^2.5, D = 1/(1 − β·cos(gyroPhase + π/2 − viewAngle)), β from bass; the emission shimmers around the gyration phase.
2. Field-aligned comb — two extra image taps along ±field direction (iron-filings smear), length ∝ normalised |B|; flat where the field is weak.
FORBID: afterglow/history (not read today), springs, a different field.
A PACKING: unchanged — ACES display RGBA in A (no reader).

## SHADER: magnetic-field
IDENTITY: mouse-centred multipole magnetic field (monopole / dipole / quadrupole / solenoid) displacing the image along field lines with caustic ridge lines, cyclotron tracer bands, click flux pulses.
KEEP VERBATIM: 4 params; 4 modes and their field formulas; FFT pole spectrum; ridge lines; Lorentz displacement + dispersion; cyclotron tracers; history blend; ACES; A = display RGBA, B = field diagnostics.
MECHANISM INTERROGATION: tactic 3 — the dipole/quadrupole branches compute pole positions and per-pole FFT bands and then discard them; the poles are invisible. Tactic 1 — `mode` is a hard 4-way switch: the slider hops between four fields.
ADD:
1. Pole beacons — each pole in the dipole/quadrupole modes gets a small polarity-coloured glow (N warm / S cool) that pulses with that pole's own FFT bin.
2. Continuous mode — one-sided cross-fade (0.1 wide, just below each threshold) between adjacent field modes, so at and above a threshold the field is exactly HEAD's.
FORBID: springs, extra shockwaves, LIC (gen-magnetic-field-warp has the field-direction taps).
A PACKING: unchanged — A display RGBA, B (b.x, b.y, line, |B|).

## SHADER: alpha-em-field-simulation
IDENTITY: RGBA32F electromagnetic field solver (Ex, Ey, Bz, charge) with mouse/click charge injection, E-hue display, LIC streaks, recombination flash.
KEEP VERBATIM: 4 params and roles; state layout raw (Ex, Ey, B, charge); clamps; diffusion terms; charge injection; display chain (hue, LIC, recombination, B brightness); alpha.
MECHANISM INTERROGATION: finding 3 — E has no source and the "wave" is diffusion. Tactic 1/6 — the solver already stores E *and* B and charge; the two Maxwell couplings that tie them are absent.
ADD:
1. Gauss source — charge sources E: `E += −k·∇ρ` (central difference of C.a, k = 0.35), so the E-hue display and LIC streaks have a field to show around every charge (§12.2D one extra term in the existing solver).
2. Faraday–Ampère coupling — `∂B/∂t = −k·curl E`, `∂E/∂t = k·(∂B/∂y, −∂B/∂x)` with k = 0.6·c·dt, so E and B exchange energy and disturbances propagate instead of only diffusing.
FORBID: replacing the solver, promoting raw A to display history, new params.
A PACKING: unchanged raw (Ex, Ey, B, charge).
NOTE for review: this makes E visible where HEAD never showed it — a big change in the picture, flagged for GPU review.

## SHADER: gravity-well-em
IDENTITY: a mouse-held gravitational well: lensing shift and RGB dispersion outside a dark core, EM displacement, photon ring, frame-drag hue shear, EM streamlines.
KEEP VERBATIM: 4 params; lens shift/aberration; EM fields and ripple orbit charges; photon ring; frame drag; glow; dark core; A = ACES display RGBA; mouse state in extraBuffer[133..134].
MECHANISM INTERROGATION: tactic 2 — a lens has a counter-image inside the Einstein ring (r' = θ_E²/r, inverted through the lens) and light climbing out of a well is redshifted and dimmed; neither is present.
ADD:
1. Counter-image — a second, dimmer, point-reflected image of the background sampled at r' = θ_E²/r just outside the core (§12.2F Snell/lens: true image position for a lens already computed).
2. Gravitational redshift — brightness and blue content fall off toward the well: z = 1/sqrt(1 − rs/r) − 1 with rs from the existing radius/strength; applied as a red tilt + dimming outside the core.
FORBID: springs, extra ripples, IQ palette.
A PACKING: unchanged — ACES display RGBA.

---

## Formula / mechanism ledger (≤ 2 files per §12.2 row)

| row / mechanism | files |
|---|---|
| D extra solver terms (Gauss source, Faraday–Ampère) | alpha-em-field-simulation |
| F lens image position / redshift | gravity-well-em |
| Reynolds alignment (boid rule) | particle-swarm |
| Reynolds flee (alarm) | fractal-boids-field-coupled |
| field-direction taps | gen-magnetic-field-warp |
| history in C (tactic 6) | fractal-boids-field (boid layer), gen-trails (pheromone) |
| none (tactic-derived) | kimi-flock-symphony-em, particle_dreams_alpha, magnetic-field |
