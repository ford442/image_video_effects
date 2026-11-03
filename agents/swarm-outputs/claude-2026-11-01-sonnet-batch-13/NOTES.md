# Sonnet batch 13 — swarm / flock / field-line ten — NOTES (2026-11-01)

Cards: `BRIEFS.md` (written before any WGSL edit). Review: `COORDINATOR_REVIEW.md`.

**No GPU in this sandbox.** Checks are structural plus a numeric sanity harness on SwiftShader. Nothing here claims an effect
"looks right"; real-GPU visual QA is external and still required.

Comment labels: where HEAD already used `Idea n` comments the new ones are labelled `2026-11 Idea n` (n = card number).
In files with no earlier labelled ideas the label is plain `Idea n`.

## Deviations from the cards (found while implementing; the cards were not rewritten)

1. **alpha-em-field-simulation, idea 2.** The card said Faraday–Ampère curl coupling. A SwiftShader run with the term zeroed vs on changed E by
   under 3 % and B by 1 %: E is `-k·∇ρ`, which is curl-free, so nothing drives B and the coupling is inert. Replaced by **corona discharge**
   (charge leaks off where |E| passes a breakdown field, with a violet-white flash), a solver term this field does support.
2. **fractal-boids-field-coupled, idea 2.** The card said |sep| (the separation force). That only fires on near-collisions (neighbour within
   `separation/boidCount`), so it would flicker. Implemented as a **soft neighbour density** `Σ exp(−dist·N·2)` over the same 8-neighbour loop.
3. **particle_dreams_alpha has three ideas, not two.** While implementing I found `baseColor` (the layered zoom colour) is computed and never
   reaches the output, so the layers only fed depth; my per-layer hue shift would have been invisible. Idea 1 now promotes that dead
   intermediate (with a sin² birth/death window so the zoom wrap does not pop), then the hue shift and the parallax zoom on top.
4. **FFT-band repair in `particle-swarm` and `magnetic-field` (not on the cards).** Both read "per-band FFT" from `plasmaBuffer[k+1].x`, but
   the engine only writes `plasmaBuffer[0]` (`writePlasmaBuffer`); the real FFT bins are `extraBuffer[5..132]`. Every per-band term in HEAD
   (turbulence gain, quadrupole pole moments) was a constant zero. Both now read `extraBuffer[5 + 4k]` (bins 0, 4 … 28) through a guarded
   `fftBand(k)`. My pole beacons in `magnetic-field` depend on it. This changes HEAD's look: the quadrupole poles now move with the music.
5. **`fractal-boids-field` left the naga known-failures list.** HEAD had `__finalRGB` (reserved prefix) and was ratcheted as known-bad; renaming
   it makes the file pass, which `verify-naga-wasm` requires be reflected in `src/contracts/wgsl_validation.json` (id removed, ratchet 22 → 21).

## Pre-existing findings (flagged)

- `particle_dreams_alpha`: saved param **names** (Particle Count / Trail Persistence / Color Shift / Chaos) do not match what the sliders drive
  (x, y = near/far layer speed, z = colour shift — dead until this batch, w = fog density). Names are saved params and stay; a human should rename
  or re-map in a reviewed change. `extraBuffer[10]` (an FFT bin) still drives the click vortex.
- `kimi-flock-symphony-em` runs 2048 loop iterations per pixel (HEAD). Not changed; my idea 2 moved the heading `normalize` inside the cheap reach test.
- `gen_trails`: the 180×180 neighbour loop per pixel is unchanged apart from a distance cull (below); still expensive at high resolution.
- `magnetic-field` / `gen-magnetic-field-warp` / `gravity-well-em` / `alpha-em` pass the A packing audit as is (display stays display, raw stays raw).

## Per shader

### fractal-boids-field
- **Kept verbatim:** 4 params; grid pseudo-boids and 8-neighbour rules; domainWarpFBM; head colour from heading; flow tint; HEAD's click-front / clock-ring overlay.
- **A packing:** boid layer (A.rgb = linear boid colour / trail memory, A.a = density), read as exact C `.rgb`. (HEAD wrote no A.)
- **Ideas:** `Idea 1: true trail persistence` (`evaporate`, `layerRgb`, `textureStore(dataTextureA…)`); `Idea 2: flow-bent trails` (`flowBehind`, `trailBend`).
- **Repair/floor:** `audioOverall` was `zoom_config.x` = engine time; now plasma energy on the flow strength (`audioReactivity` fixed 1.0, as at t = 0); ACES on display; reserved identifier renamed.

### fractal-boids-field-coupled
- **Kept verbatim:** 4 params and double roles; fluid sampler; mouse state at A(0,0); boid rules; wake visualisation; ripple flash.
- **A packing:** unchanged (A(0,0).xy = mouse; nothing else written).
- **Ideas:** `Idea 1: alarm scatter` (`alarmDir`, position kick ≤ 0.015 uv, heading `+ alarmDir * 3.0`); `Idea 2: flock-density halo` (`crowd`, `crowdHalo`).
- **Repair/floor:** same time-as-audio repair; ACES on display.

### kimi-flock-symphony-em
- **Kept verbatim:** 4 params; 2048-sample loop; E/B field functions; ripple orbit charges; streamline overlay; Reinhard + pow 0.8 tone curve (kept, it is the look — no ACES added); transmittance alpha.
- **A packing:** unchanged.
- **Ideas:** `Idea 1: charge-sign two-fluid split` (`chargeSign` flips the E-direct term; E × B term common; negatives +0.15 hue); `Idea 2: drift-stretched particles` (`stretch`, `driftHeading`, alpha ÷ √stretch).

### particle-swarm
- **Kept verbatim:** all of HEAD (cohesion, separation, band turbulence, spring pointer in extraBuffer[133..136], click impulses, HG scattering, ACES).
- **A packing:** unchanged — A raw (offset.xy, vel.xy), B diagnostics.
- **Ideas:** `2026-11 Idea 1: Reynolds alignment` (`alignment` from C.zw of the same four taps); `2026-11 Idea 2: velocity-aligned motion-blur taps` (`blurTapA/B`, `base_color` blend).
- **Repair:** FFT bands read from `extraBuffer[5+4k]` (deviation 4).

### particle_dreams_alpha
- **Kept verbatim:** 5-layer loop; layer speed mix(x, y); flow noise; vortex spin; fog (w); volumetric alpha; edge glow; param ids/names.
- **A packing:** none (HEAD writes no A, reads no C).
- **Ideas:** `2026-11 Idea 1` ghost layers + birth/death window (`ghostAcc`, `layerWindow`, `layered`); `2026-11 Idea 2` per-layer hue shift (slider z live: `hueRotate(sampleColor, colorShift·layerDepth·π)`); `2026-11 Idea 3` depth-parallax zoom (`parallaxZoom`).
- **Repair/floor:** `extraBuffer[0]` (bass) used raw as a UV offset → `plasmaBuffer[0].x · 0.05`; ACES on display; JSON: removed false `alpha-trails` / `temporal-feedback`.

### gen-trails (`gen_trails.wgsl`)
- **Kept verbatim:** 4 params and audio mappings; Reynolds rule block; body/wing/trail/streak drawing; treble flashes; ACES; B = pheromone + alpha.
- **A packing: changed on purpose** — A = (pheromone RGB, pheromone luma), read as C `.rgb`. HEAD's A velocity/density tuple was read back as colour (packing lie) and had no other reader.
- **Ideas:** `Idea 1: real pheromone trails` (`pheromoneVis` screen composite; A store); `Idea 2: continuous flight` (`boidBaseVelocity`, `getBoidPosition(id, time, aspect)`; headings keep a slow wander); `Idea 3: wing beat` (`flap`).
- **Floor:** bounds guard; `edgeSafe` distance cull (a boid > 0.6 from the pixel cannot contribute: streak ≤ 0.4 + one step ≤ 0.08; boids within 0.1 of the wrap edge are never culled).

### gen-magnetic-field-warp
- **Kept verbatim:** 4 params; field construction; Larmor gyration; synchrotron colour/polariser; Alfvén rings; A = ACES display RGBA; alpha.
- **A packing:** unchanged (no reader).
- **Ideas:** `2026-11 Idea 1: Doppler beaming` (`beamD`, `beaming` multiplies `emissivity`); `2026-11 Idea 2: field-aligned comb` (`combA/B`, `color`).

### magnetic-field
- **Kept verbatim:** 4 params; four modes' formulas; ridge lines; Lorentz displacement + dispersion; cyclotron tracers; history blend; ACES; A = display RGBA, B = field diagnostics.
- **A packing:** unchanged.
- **Ideas:** `2026-11 Idea 1: pole beacons` (`pole_glow`, polarity colours, FFT-band pulse); `2026-11 Idea 2: continuous mode` (`mode_s1..3` one-sided cross-fade; at and above each threshold the field equals HEAD's).
- **Repair:** FFT bands via `fftBand()` (deviation 4).

### alpha-em-field-simulation
- **Kept verbatim:** 4 params and roles; raw state (Ex, Ey, B, charge); clamps; diffusion; charge injection; display chain; LIC; recombination flash; alpha.
- **A packing:** unchanged raw.
- **Ideas:** `2026-11 Idea 1: Gauss source` (`gradRho`, `eField += −gradRho·0.35`; §12.2D one extra solver term); `2026-11 Idea 2: corona discharge` (`breakdown`, charge ×(1 − 0.04·breakdown), flash). See deviation 1.
- **Heads-up for GPU review:** HEAD's E was exactly zero (measured: max|Ex| = max|Ey| = 0 over 200 frames); the E-hue display and LIC are now lit, a large change in the picture.

### gravity-well-em
- **Kept verbatim:** 4 params; lens shift + dispersion; EM fields and ripple orbit charges; photon ring; frame drag; glow; dark core; A = ACES display RGBA; mouse state in extraBuffer[133..134].
- **A packing:** unchanged.
- **Ideas:** `2026-11 Idea 1: counter-image` (`thetaE`, `counterUV`, `counterWeight`; §12.2F lens image position); `2026-11 Idea 2: gravitational redshift` (`redshiftZ`, per-channel `pow`).

## Formula rows (batch)

| row / mechanism | files |
|---|---|
| D extra solver terms (Gauss source, corona discharge) | alpha-em-field-simulation |
| F lens image position / redshift | gravity-well-em |
| Reynolds alignment | particle-swarm |
| Reynolds flee | fractal-boids-field-coupled |
| field-direction taps | gen-magnetic-field-warp |
| history in C (tactic 6) | fractal-boids-field, gen-trails |
| none | kimi-flock-symphony-em, particle_dreams_alpha, magnetic-field |

## Gates

- naga-wasm (30.0): 10/10 valid.
- `wgsl_precommit_gate.py --skip-naga --files …`: 10/10, 0 pasted headers, 0 extraBuffer violations.
- `audit:extrabuffer`: 0 new. `audit:dead-sliders -- --files …`: 0 new dead sliders.
- **SwiftShader execution harness** (throwaway, not committed): all 13 bindings bound with an explicit layout, A→C ping-pong, moving mouse, held press, click ripples, 128² synthetic image + depth,
  non-zero FFT bins. 10/10 pipelines built, **0 NaN/Inf in display or A, no GPU validation errors**, state bounded: `alpha-em` 600 frames (|A| ≤ 1.3 and decaying),
  `particle-swarm` 400 frames (|offset,vel| ≤ 0.007), `gen_trails` 24 frames at 64², `kimi` 20 frames at 96², the rest 90 frames. Numeric sanity only; it says nothing about how the effects look.
- Saved `params` byte-identical to HEAD in all ten JSONs; `x-meta` untouched.
- `node scripts/generate_shader_lists.js`, `npm run test:ci`, `npm run build`: see PR.
