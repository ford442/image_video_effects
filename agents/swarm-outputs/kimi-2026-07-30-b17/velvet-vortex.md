# Agent Notes — velvet-vortex (Batch 17, Visualist)

**Date:** 2026-07-30
**Files touched:**
- `public/shaders/velvet-vortex.wgsl` (rewritten/expanded)
- `shader_definitions/interactive-mouse/velvet-vortex.json` (added `updatedParams` + `"updated": true` only)

## Lines

- Before: 88
- After: 141 (+53, inside the +50..+90 target and the 138–178 band)

## Techniques implemented

1. **Click swirl shockwaves (priority 1):** the previously-unused `ripples[]` uniform is
   now looped in `ripple_twist()` with the guard `min(u32(u.config.y), 50u)`. Each live
   ripple (`age = time - ripple.z`, active for ~2s) spawns an expanding ring
   (`ringRadius = age * 0.45`); a Gaussian band around the ring adds a decaying extra
   twist (`band * fade^2 * 2.5`) into `angle`, scaled by `softFactor` so clicks visibly
   whip the velvet. A faint cool `shockSheen` also rides the ring in the final color.
2. **Spring-damper vortex center:** critically-damped spring
   (`stiffness = 42.0`, `damping = 2*sqrt(stiffness)`, fixed `dt = 0.016`) integrated
   toward the raw mouse target. State lives in `extraBuffer[133..136]` (pos.xy, vel.xy)
   — [0..4] reserved and [5..132] engine FFT bins untouched. All invocations integrate
   identical values from the previous frame's state, so the write-back race is benign.
   First frame (all-zero state) snaps to the cursor. The spring position feeds
   `centerCorrected`, so the existing `(depth - 0.5) * 0.04` parallax offset is layered
   on top of the glide exactly as before.
3. **Per-arm spectrum:** polar angle `theta = atan2(dir.y, dir.x)` is mapped to an arm
   sector; the sector index picks `plasmaBuffer[(bin % 8) + 1].x` and that per-bin energy
   is rotated into the swirl phase (`armEnergy * softFactor * (2.0 + softness * 2.0)`),
   so different arms shimmer on different FFT bins. `armCount = 3 + floor(mids*6)` kept
   verbatim. Treble still drives the velvet tint exactly as before.

## Slider mapping (u.zoom_params, index 0–3, ids/defaults unchanged)

- **0 — Vortex Radius (0.4):** base swirl radius `radiusParam`, pulsed by bass/mids envelope.
- **1 — Swirl Force (0.5):** twist strength, scaled by `bass_env(bass, mids)`; multiplies `(8 + armCount) * softFactor`.
- **2 — Edge Softness (0.6):** falloff exponent `1/(softness+0.1)` AND now also widens the per-arm spectral shimmer gain (`2.0 + softness*2.0`).
- **3 — Pulse Speed (0.2):** tempo of the radius pulse (`sin(time * pulseSpeed * bass_env * 5.0)`).

## Contract compliance / CAUTION

- 13-binding layout preserved verbatim; `@workgroup_size(16, 16, 1)`.
- `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame;
  `dataTextureA` stays DISPLAY color.
- All sampler reads use `textureSampleLevel(..., 0.0)`; no storage `textureLoad` needed.
- VERBATIM preserved: 2×2 rotation-matrix swirl math, `1.0 - smoothstep(...)` falloff,
  `(depth - 0.5) * 0.04` parallax, velvet tint / alpha / depthOut formulas.
- Stale header comment fixed: `Category: distortion` → `Category: interactive-mouse`
  (comment-only).
- extraBuffer used ONLY in [133..136] (within [133..255]).
- No reserved WGSL keywords as identifiers.

## Gate result

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/velvet-vortex.wgsl
✅ public/shaders/velvet-vortex.wgsl — naga OK, bindgroup compatible
Passed: 1 | Failed: 0 | extraBuffer violations: 0
```

## Deviations

- None from the brief. Note: the fixed `dt = 0.016` for the spring is a deliberate
  simplification (frame-rate-assuming) to keep integration deterministic across
  invocations; no per-frame timestamp is stored in extraBuffer.
