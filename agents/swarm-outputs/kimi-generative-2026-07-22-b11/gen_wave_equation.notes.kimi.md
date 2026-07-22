# gen_wave_equation — Algorithmist Notes (swarm b11)

**Role:** Algorithmist
**Shader:** Fluid Ripples (`gen-wave-equation`, generative)
**Date:** 2026-07-22

## Key changes

- **FIXED the feedback-state bug (Priority 1):** the solver read `(height, velocity)` from
  `dataTextureC.rg` but wrote `finalColor` into `dataTextureA`, so the A->C engine copy fed
  tone-mapped color back as "state" and the wave equation never actually iterated. Now the
  sim state is written to `dataTextureA` with layout `r=height, g=velocity, b=energy,
  a=waveIntensity`; rendered color stays in `writeTexture` only. Klein-Gordon/Sine-Gordon
  nonlinear term preserved and now operates on real state.
- **State sanitizer:** NaN kill (`select(x, 0.0, x != x)`) + clamp to ±8 so stale color values
  (0..1 garbage) sitting in dataTextureC from pre-fix frames can't blow up the solver on
  first frames after the upgrade.
- **9-point Laplacian:** added the 4 diagonal neighbors (weights 1.0 ortho / 0.5 diagonal,
  renormalized by total weight 6.0) via an edge-safe `sampleHeight` helper — more isotropic,
  less grid-aligned propagation. Relief shading (`laplacian * 4.0`) now also modulates the
  water color for crest/trough depth.
- **Click droplets:** replaced continuous `mouse_impact` forcing-while-held with a gaussian
  height pulse on the mouse-down rising edge (`exp(-d²/σ²)`), tracked via `extraBuffer[5]`
  (single writer at thread (0,0); indices 0..4 untouched). Drops radiate clean rings.
  Also seed droplets from the engine `ripples[]` ring buffer (age-gated 0.2 s window).
- **Audio rain:** strong bass transients (`bass > 1.0`) seed small ambient droplets at
  hashed positions (canonical `hash21`/`hash22`), keeping the audio-reactive soul.
- **Slider wiring (same ids/defaults/mapping — contract kept):**
  - Intensity → droplet amplitude (0.6–3.0) + render opacity
  - Speed → wave propagation rate (0.1–1.0)
  - Scale → surface tension / KG mass (0.001–0.05) + droplet radius σ (0.025–0.060)
  - Detail → damping (0.96–0.999) + KG↔SG nonlinear blend
- Workgroup size updated to canonical `@workgroup_size(16, 16, 1)` (was 8,8,1).
  13-binding layout unchanged; writes to `writeTexture`, `dataTextureA`, `writeDepthTexture`
  every frame.

## Line count delta

- Before: 149 lines → After: 215 lines (**+66**, within the +50…+90 target; 199–239 range ✓)

## Gate result

- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen_wave_equation.wgsl`
  → **exit 0**, naga OK, bindgroup compatible, 0 warnings.

## QA flags

- **No GPU in this VM** — naga/bindgroup validation only; visual QA deferred to on-GPU run.
- **State-layout change needs on-GPU verification:** dataTextureA now carries sim state
  (height/velocity) instead of color. Anything downstream that consumed dataTextureA/B as a
  *color* trail for this shader will see raw state values (can be negative / >1). Verify the
  engine's A->C copy timing and that no layer-chain consumer reads this shader's dataTextureA
  as color.
- **Eyeballed constants** (not tuned on hardware): droplet σ range (0.025–0.060), droplet
  amplitude (0.6–3.0), bass-rain threshold (`bass > 1.0`) and force (×0.6), ripple age window
  (0.2 s), relief shading gain (4.0), state clamp (±8). All are reasonable starting points but
  deserve a tuning pass on GPU.
- **First-frame transient:** pre-fix frames left color in dataTextureC; the sanitizer clamps
  it, but one brief settle transient is expected after deploying the new shader.
- **extraBuffer[5] race:** read-all/write-one pattern matches existing codebase convention
  (e.g. gen-cybernetic-mycelium-neural-web); worst case is one dropped/duplicated click edge.
