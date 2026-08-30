# Changelog — echo-ripple + echo-trace (Batch 60)

## echo-ripple (`public/shaders/echo-ripple.wgsl`)

- Raised click ripple loop from `min(..., 12u)` → `min(u32(u.config.y), 50u)`.
- Stronger held gravity bowl: inverse-square pull amp + Gaussian bowl falloff when `zoom_config.w > 0.5`, plus standing held bowl wave under cursor.
- Deepened thin-film interference (multi-harmonic + per-echo film) and bioluminescent wake tint; optional plasma bins 1–4 shimmer.
- Kept exact `textureLoad` C advection, ACES display, semantic alpha.
- **A packing:** `dataTextureA = [mixedRGB, bassEnvelope]` (history.a feeds `bass_env`).
- Params/`updatedParams` unchanged (freq, speed, decay, strength).

## echo-trace (`public/shaders/echo-trace.wgsl`)

- **CRITICAL:** Moved Kalman state off illegal FFT slots `[0..8]` → `extraBuffer[133..141]`:
  - `[133,134]` pos xy, `[135,136]` vel xy
  - `[137,138]` pPos xy, `[139,140]` pVel xy, `[141]` initialized
  - Writes **only** from `global_id == (0,0)` when `arrayLength > 141`.
- Replaced all `textureSampleLevel(dataTextureC, ...)` with bounded `textureLoad`.
- Held brush intensification (tighter Mahalanobis brush + denser dashes + bio hold glow).
- Capped click spark echoes via `min(u32(u.config.y), 50u)` ring pulses.
- Oil-slick psychedelic trail tint keyed to Mahalanobis/uncertainty; ACES on display path.
- Preserved 4D Kalman predictive identity and covariance A diagnostics.
- **A packing:** `dataTextureA = [pPos.x*300, pPos.y*300, pVel.x*45, pVel.y*45]` (display on `writeTexture`).
- Params/`updatedParams` unchanged (prediction_horizon, velocity_smoothing, trail_deformation, velocity_threshold).

## Shared contract

- Canonical 13 bindings, 16×16×1, unused B.
- Audio via `plasmaBuffer[0].xyz` (+ optional bins).
- Held via `zoom_config.w`. Semantic (unpremultiplied) alpha.
- Structural validation local; real-GPU visual QA external.
