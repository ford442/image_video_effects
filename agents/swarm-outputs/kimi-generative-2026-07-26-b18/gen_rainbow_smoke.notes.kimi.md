# Notes: gen_rainbow_smoke (Batch 18, Algorithmist)

## Line delta
- Before: 220 lines → After: 310 lines (+90, within 270–310 target)

## Changes per technique

### 1. CFL safety (priority 1)
- Added `clampMag(v, maxMag)` helper; applied as `velocity = clampMag(velocity, 0.05)` in the
  sim update AFTER all force accumulation (curl forcing, bass-boosted vorticity confinement,
  mouse stir, buoyancy, click bursts) and BEFORE the density/temperature integrate + store.
- Nothing else about the solver changed; decay constants 0.972/0.994/0.992 and the
  `vec4(velocity, density, temperature)` packing preserved verbatim.

### 2. Spectral emitters
- New `fftRangeAvg(lo, hi)` helper averages energy across per-bin FFT slots `plasmaBuffer[1..8]`.
- Two extra emission centers on slow Lissajous drift paths:
  - `lissLow` (left-of-center) driven by bins 1–4 (`fftLow`)
  - `lissHigh` (right-of-center) driven by bins 5–8 (`fftHigh`)
- `spectralEmission` feeds both density and temperature (heat term scaled by mids), gains
  scaled by the Emission slider. Different frequency ranges now ignite different smoke sources.

### 3. Click smoke bursts
- Loop over `u.ripples[]` guarded by `min(u32(u.config.y), 50u)`.
- Each click within a 3 s age window injects a radial velocity pulse (`burstDir * ring * decay`)
  plus density impulse (0.45) and heat impulse (0.35), both with Gaussian ring falloff and
  `exp(-age * 1.8)` decay. Density impulse scaled by the Emission slider.

### 4. Spring-damped mouse stir
- Persistent state in extraBuffer safe zone ONLY: [133..134] = eased stir position,
  [135..136] = spring velocity.
- Invocation (0,0) integrates a damped spring (k=30, damp=8.5, dt=1/60) toward the raw mouse;
  cold start (time < 0.1) snaps to avoid startup swoop. All pixels read the eased position,
  so stirring is continuous instead of teleporting.

## Slider wiring (saved-preset contract — ids/defaults unchanged)
- `zoom_params.x` Emission (0.55): base emitter gain + spectral FFT emitter gains + click burst density
- `zoom_params.y` Turbulence (0.65): multi-scale curl forcing + vorticity confinement strength
- `zoom_params.z` Scattering (0.6): Mie/Rayleigh gains, body brightness, extinction alpha
- `zoom_params.w` Advection (0.55): semi-Lagrangian backtrace distance via mix(0.45, 1.45, w)
- JSON `updatedParams` index 0–3 added verbatim from brief block.

## Binding compliance
- Canonical 13-binding layout unchanged (0–12), no binding 13 declared.
- `@workgroup_size(16, 16, 1)`; writes to `writeTexture`, `writeDepthTexture`, `dataTextureA`
  (and `dataTextureB` debug) every frame.
- Sampler reads via `textureSampleLevel(..., 0.0)`; storage reads via `textureLoad`.
- No WGSL reserved keywords as identifiers; no added/renumbered bindings.
- extraBuffer writes confined to [133..136] (safe zone [133..255]); FFT bins [0..132] untouched.
- dataTextureA stores raw sim state — never tonemapped.

## QA flags
- `wgsl_precommit_gate.py`: PASS, 0 warnings (naga unavailable in env — skipped by gate itself; bindgroup + workgroup checks green)
- `audit_extrabuffer.py`: AUDIT PASS (0 violations, writes only in [133..255])
- `audit_dead_sliders.py`: AUDIT PASS (0 dead sliders — all 4 params consumed in WGSL)
- Note: file on disk was already partially upgraded from a prior run; this pass verified brief
  compliance, trimmed to 310 lines, confirmed JSON matches the brief block byte-for-byte, and
  re-ran all gates.
