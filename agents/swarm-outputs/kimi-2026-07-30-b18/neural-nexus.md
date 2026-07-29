# Agent Notes — neural-nexus (Batch 18, Interactivist)

**Date:** 2026-07-30
**Lines:** 97 → 167 (+70, within the +50..+90 target)
**Gate:** ✅ green — `naga OK, bindgroup compatible`, 0 workgroup errors/warnings, 0 extraBuffer violations

## Techniques implemented

1. **Click synapse bursts (priority 1).** The previously-unused `ripples[]` uniform is now
   looped with the guard `min(u32(u.config.y), 50u)`. Each live ripple
   (`age = time - ripple.z`, active window 0–2 s) acts as a temporary extra neuron at its
   click point: an expanding sinusoidal ring (`sin((clickDist - waveFront) * 40.0)` with a
   sharp wavefront envelope) decays via `exp(-age * (2.0 + decayRate))` (~2 s fade) and is
   injected into `activity`, plus a local spark burst into `sparks`. `ripple.w` scales burst
   strength. A cyan `clickGlow` term rides the burst in the final color so clicks visibly
   fire the network.
2. **Spring-damper signal origin.** Raw clamped mouse stays the spring target; a
   critically-damped spring (omega = 12, c = 2·omega, semi-implicit Euler, fixed dt =
   1/60) eases the cursor. State lives in `extraBuffer[133..136]` ONLY (pos.xy, vel.xy);
   [0..4] reserved and [5..132] engine FFT bins untouched. Writeback is gated to
   thread (0,0); zero-init snap guard avoids a corner sweep on first frame. All signal
   phases, dendrite connections, and the mouse pulse now propagate from the gliding cursor.
3. **Per-neuron FFT voices.** Each neuron derives its own bin
   (`u32(hash(vec2(seed, 4.17)) * 8.0) % 8u + 1u`) and `plasmaBuffer[bin].x` modulates that
   neuron's pulse amplitude (`0.55 + 0.9 * voice`), so neurons dance to different
   frequencies instead of all following global bass.

## What each slider now drives

- **Density (index 0, u.zoom_params.x):** neuron count (`5 + u32(density*2)`), aura
  falloff denominator, and mouse-pulse radial falloff (unchanged, already shader-specific).
- **Signal Speed (index 1, u.zoom_params.y):** phase speed of neuron-to-cursor signal
  waves **and** the expansion speed of click shockwave wavefronts.
- **Decay (index 2, u.zoom_params.z):** exponential decay of neuron pulses with cursor
  distance **and** the fade tail length of click bursts.
- **Branches (index 3, u.zoom_params.w):** dendrite arm count in the cos() structure
  (unchanged, already shader-specific).

Sliders 1 and 2 were rewired to also drive the new click-burst constants; the mapping was
already shader-specific, so no full rewire was needed.

## Preserved VERBATIM (per CAUTION)

- Neuron hash placement (`seed = f32(i) * 17.23`, hash seeds 0.13 / 9.71)
- Dendrite `cos(angle * branches + time * (1.2 + treble * 3.0) + seed)` structure
- `sampleUV` displacement expression
- `dataTextureA` packing `(totalActivity, sparks, mousePulse, alpha)` — mask data, not color
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, all three stores every frame,
  `textureSampleLevel(..., 0.0)` for sampler reads

## JSON

`shader_definitions/interactive-mouse/neural-nexus.json`: added ONLY the `updatedParams`
array (indices 0–3, names/defaults/min/max/step exactly as in the brief) and
`"updated": true`. Existing `params` untouched (ids, names, defaults, order preserved).

## Deviations

- One naga fix during verification: `springState == vec4<f32>(0.0)` returns `vec4<bool>`,
  so the snap guard uses `all(...)` before `&&`. Pure compile fix, no behavior change.
- Fixed-timestep spring (dt = 1/60) instead of a wall-clock dt to avoid needing a
  last-time state slot beyond the sanctioned [133..136] range.
