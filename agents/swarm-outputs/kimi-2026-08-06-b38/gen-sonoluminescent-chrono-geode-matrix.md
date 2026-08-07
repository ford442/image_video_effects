# gen-sonoluminescent-chrono-geode-matrix — Algorithmist note (Batch 38, tracker #340)

## Weaknesses found
1. **Uniform truth violation (actually broken):** treated `config` as `[resX, resY, time, aspect]` and `zoom_config` as `[mouseX, mouseY, clicking, audio]`. Against the real engine layout (`config = [time, rippleCount, resW, resH]`) the bounds guard compared pixel ids against *time*, and "time" was really `resW` — the shader could not have animated correctly.
2. **Fake audio:** audio came from `zoom_config.w` (mouseDown slot) — no `plasmaBuffer` use at all.
3. **Slow linear drift:** rotation = `time * p3`, noise scroll linear in time; no speed, no bursts, no event structure.
4. **Contract gaps:** no `dataTextureA` write at all, flat `0.0` depth, hardcoded alpha `1.0`, no tone map, gamma-only output, generic `applyGenerativePrimaryControls` remap double-consuming sliders.

## Techniques applied (fast-motion ones marked ⚡)
- ⚡ **Closed-form high-speed orbital camera + eased time-warp spin:** camera orbits on an analytic circle (radius breathing), geode rotates by `warpTime = animTime + 0.35·sin(0.83·animTime) + 0.09·sin(2.39·animTime)` — fast-in/smooth-out easing, incommensurate frequencies, fully analytic in time ⇒ frame-rate independent, sub-frame stable, zero hash strobing.
- ⚡ **Sonoluminescent flash-burst physics:** closed-form bubble-collapse cycle — `flashPhase = fract(animTime·flashRate)` with `flashRate` pumped by Speed slider + bass; core radius collapses/regrows via exp envelopes (`exp(-7φ)`, `1-exp(-4φ)`); flash brightness spikes at collapse with bounded exp decay; a **ballistic shockwave shell** (`ringR = φ·(5+3·kick)`) races outward and is accumulated during the march.
- ⚡ **Bass-transient kick bursts:** rising-edge detect on `plasmaBuffer[0].x`, dt-integrated exponential decay (`dt` from persisted prev-time ⇒ fps-independent integration), state in `extraBuffer[133..135]` only, single-writer guard + `arrayLength` check, energy clamped ≤ 2.0. Kick boosts flash amplitude, fracture, and shell speed.
- ⚡ **Velocity-advected motion-blur trails:** `dataTextureC` history fetched via `textureLoad` at pixel offset by the analytic screen-space swirl velocity of the spinning geode (clamped ±4 px), decay 0.81–0.86, **HDR history clamped ≤ 5.0** (Batch 36 topology-flow lesson).
- **FBM/value-noise fracture at speed:** original `vnoise3` kept (temporal-coherent), scrolled fast in time with a second high-frequency flutter octave — smooth, never strobes.
- **ACES tone map, semantic alpha** (hit 0.9 / plasma-density based background), **real generated depth** (`1 − t/MAX_DIST` on hit, plasma-scaled faint relief on miss).

## Slider wiring (all LIVE, names/defaults byte-exact)
- **Intensity (p1)** → flash gain + fracture amplitude + iridescence/core-reflection gain.
- **Speed (p2)** → global rate `mix(0.35, 3.2)`, flash rate, camera orbit speed, trail swirl magnitude.
- **Scale (p3)** → SDF-correct geode domain scale `mix(0.85, 1.4)`.
- **Mouse Influence (p4)** → press-to-repel shard force `mix(0.4, 3.0)` (uniform-truth mouse, y-flip fixed) + trail decay lengthening.

## Contract compliance
Canonical 13-binding header verbatim; Uniforms struct exactly `config, zoom_config, zoom_params, ripples`; `@compute @workgroup_size(16, 16, 1)` + `u.config.zw` bounds guard; writes `writeTexture`/`writeDepthTexture`/`dataTextureA` every frame; `textureLoad`-only feedback; `plasmaBuffer[0].xyz` + guarded FFT bins 1–4 audio; extraBuffer only [133..135] single-writer + arrayLength guard; no `textureSample`/`dpdx`/reserved words.

## Gate result
`python3 scripts/wgsl_precommit_gate.py --files …` → **2/2 PASS** (naga OK, bindgroup compatible, extraBuffer violations: 0).
`updatedParams` diff vs `git show HEAD:…json` → **IDENTICAL**. JSON edits additive only (description sentence + truthful `features`).
