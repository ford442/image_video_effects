# Batch 18 Notes — interactive_neural_swarm (Neural Swarm)

**Role:** Interactivist · **Category:** generative · **Target:** 4.8★

## Line delta

- Before: **237** lines (workspace already held a partial Batch-18 pass vs. the brief's stated 221)
- After: **302** lines (**+65** vs. workspace, +81 vs. brief baseline) — inside target 271–311

## Changes per technique

1. **FIX THE FAKE AUDIO (priority 1) — done.**
   - `audioPulse = u.zoom_config.w` (mouse-DOWN) removed as an audio source. `zoom_config.w` is now used only as `clickPulse` (button-held stimulus intensity on the attractor ring), explicitly commented as NOT audio.
   - Bass `plasmaBuffer[0].x` (clamped 0..2) drives global activation energy: attractor ring amplitude, axon pulse brightness, ambient mist level, and per-neuron activation.
   - Per-neuron FFT bin `plasmaBuffer[1u + u32(i) % 8u].x` feeds each neuron's own activation term.
   - **Network Density honesty:** `u.zoom_params.w` now gates the active neuron count via `activeNeurons = i32(mix(20.0, 40.0, density))` (both neuron and connection loops bound by it), in addition to its old brightness-pulse role.

2. **Honest depth — done.** The constant `0.0` depth write is gone. A per-pixel `proximityField` accumulates soma glow, activation halo, axon glow and traveling-signal glow; combined with `maxActivation` and `rippleWave` into `signalField`, then `depth = mix(inDepth, 0.15 + (1.0 - signalField) * 0.55, ...)` — active neurons/signals push toward the camera, quiet regions fall back toward the incoming chain depth (`readDepthTexture` sampled with `non_filtering_sampler`, level 0.0).

3. **Click signal waves — done.** Ripple loop guarded by `min(u32(u.config.y), 50u)`; each ripple `(x, y, startTime, _)` emits an expanding Gaussian wavefront (speed 0.65, 4 s lifetime, exponential decay). Wavefronts light pixels directly AND propagate through the web: `webBoost = 1.0 + rippleWave * 1.5` amplifies the traveling axon pulses, and `rippleWave` adds to per-neuron activation.

4. **Spring-dampered mouse attractor — done.** Thread (0,0) integrates a critically damped spring (`omega = 8.0`, `dt = 0.016`) toward the raw mouse; state persisted in `extraBuffer[133..137]` (pos, vel, init flag) — safe zone only, static const indices. All threads read back the smoothed `mousePos`.

5. **Curl-noise drift — done (and improved vs. partial pass).** The old sin/cos drift is replaced by `curlNoise2` (divergence-free hash gradient). Drift is now sampled per-neuron at the neuron's OWN base position inside `getNeuronPos` (the partial pass sampled one field per-pixel at `uv`, which made all neurons drift identically per pixel).

6. **Extras for rating/depth of craft:** ambient hash-dither neural mist background; activation halo ring around each soma via `smoothFalloff` with activation-breathing radius; expanded header documenting state layout, audio map, and engine uniform truth.

## Preserved verbatim (per CAUTION)

- `getNeuronPos` hash placement: `hash2(vec2<f32>(fi * 1.618, fi * 2.718))` / `hash2(vec2<f32>(fi * 3.142, fi * 1.414))`, `* 0.8 + 0.1` base mapping — untouched (local renamed `hash2v` only to avoid shadowing the `hash2` fn).
- `connectionStrength` O(N²) pairing and its constants (radius 0.15, modulation `sin(time*2 + dist*20)*0.3+0.7`) — untouched.
- Core render algorithm (glow/axon/activation-color structure) — upgraded, not rewritten.

## Slider wiring (saved-preset contract kept: same ids/defaults/min/max/step/order)

| Slider | Field | WGSL read | Drives |
|---|---|---|---|
| param1 Connection Threshold | `zoom_params.x` | `connectionThreshold` | axon visibility gate (`strength > threshold*0.5`) |
| param2 Signal Speed | `zoom_params.y` | `signalSpeed = 0.5 + y*2.0` | attractor ring + axon action-potential rate |
| param3 Glow Radius | `zoom_params.z` | `glowRadius = 0.02 + z*0.03` | soma glow size + halo falloff |
| param4 Network Density | `zoom_params.w` | `networkDensity` | active neuron count 20..40 + global pulse gain |

## Binding compliance

- Canonical 13-binding layout kept (0..12, no renumbering, no binding 13 added).
- `@workgroup_size(16, 16, 1)` — 3 explicit dims.
- `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame (A carries color + `maxActivation` alpha for downstream layers).
- Sampler reads via `textureSampleLevel(..., 0.0)`; storage via `textureLoad`/`textureStore`; `plasmaBuffer` read-only.
- extraBuffer writes only at const indices 133–137 (safe zone [133..255]); ripple guard `min(u32(u.config.y), 50u)` present.
- No WGSL reserved keywords as identifiers.

## Gate / audit results

- `wgsl_precommit_gate.py --files …` → **PASS** (1 passed, 0 failed, 0 warnings; naga unavailable in this VM so naga step skipped — bindgroup compatible, workgroup OK, 0 extraBuffer violations)
- `audit_extrabuffer.py --files …` → **AUDIT PASS** (0 new violations, 0 dynamic, 0 out-of-range)
- `audit_dead_sliders.py --files interactive_neural_swarm` → **AUDIT PASS** (0 dead sliders; all 4 zoom_params fields read)
- `shader_definitions/generative/interactive_neural_swarm.json` — brief's fenced JSON written **verbatim** (diff-clean).

## QA flags

- ⚠️ naga CLI not installed in this environment; syntax validated by gate bindgroup parser + manual review only. Recommend CI naga run.
- ⚠️ No GPU in this VM — visual output not exercised; audio path (`plasmaBuffer`) follows the documented engine FFT-bin contract but was not runtime-verified.
- Note: workspace WGSL was already at 237 lines (partial prior pass, uncommitted) when this run started; the brief's quoted 221-line version is the committed baseline.
