# Notes: acoustic-string-theory (Interactivist pass)

**Role:** Interactivist
**Date:** 2026-07-22 (batch b11)
**Shader:** `public/shaders/acoustic-string-theory.wgsl`

## Key changes

- **Pluck on click:** mouse-down rising edge detected via `extraBuffer[5]` (previous down level). On the rising edge, thread (0,0) records pluck time/x/y/strength into `extraBuffer[10..13]`. Each string gets a gaussian displacement (`pluckGauss` around pluck x, `struck` gaussian matching nearest string y, sinusoidal `ring`) that decays as `exp(-age * (1.2 + tension * 1.6))` — clicks pluck, they don't just glow.
- **Audio spectrum drive:** new `bandWeight()` weights per-string amplitudes by spectral position — low strings follow bass, middle strings mids, high strings treble (`specAmp` multiplies string/harmonic field accumulation). The instrument visibly tracks the music's spectrum.
- **Spring-damper gravity well:** the well no longer snaps to the mouse; it chases it with a damped spring (stiffness 42, damping 7, dt from `u.config.y`) with state in `extraBuffer[6..9]` (pos.xy, vel.xy). `wellPos` now drives gravity-well bend, shockwave distance, and damp falloff.
- **Feedback clamp:** temporal accumulation is clamped `min(accum, 1.2)` pre-tint (luma-echo-warp lesson); luma/AO tint applied after the clamp.
- **Slider rewiring (same ids/defaults, deeper constants):**
  - `Strings` (zoom_params.x): string count 2–16, also normalizes per-string spectral index.
  - `Tension` (zoom_params.y): wave frequency/falloff + pluck ring-down rate + harmonic rolloff brightness (stiffer string = richer overtones, faster decay).
  - `Harmonics` (zoom_params.z): overtone count 1–8 with tension-driven rolloff `pow(rolloff, fh)`.
  - `Resonance` (zoom_params.w): amplitude scale + feedback sustain (`mix(0.90, 0.965, …)`), so it audibly/visibly controls how long notes ring.
- **Pluck glow:** faint warm flash at the strike point (`pluckEnv * pluckGauss`) and pluck energizes node field on the struck string.
- extraBuffer safety: all state access guarded by `arrayLength(&extraBuffer) > 13u`; indices 0–4 untouched.
- Canonical 13-binding layout and `@workgroup_size(16, 16, 1)` preserved; writes to `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame.

## Line count delta

- Before: 157 lines → After: 239 lines (**+82**, within the brief's +50 to +90 window; target 207–247 ✓)

## Gate / validation

- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/acoustic-string-theory.wgsl` → **exit 0**, naga OK, bindgroup compatible, 0 warnings.
- JSON updated with `updatedParams` (indices 0–3) + `"updated": true` exactly per brief; param ids/defaults/mappings unchanged (saved-preset contract). JSON parses clean.

## QA flags

- All spring constants (42/7), pluck gaussian widths (3.0 x / 4.0 y), ring frequency (6.0 + fs*0.7), band-weight centers (0.12/0.50/0.88) and clamp 1.2 are **eyeballed constants** — no GPU on this VM, so visual QA is **deferred** to a machine with WebGPU.
- Single-writer state pattern means non-(0,0) threads may read one-frame-stale well/pluck state; standard for this codebase and visually imperceptible at 60 fps, but noted.
- `extraBuffer` size is engine-managed; the `arrayLength` guard keeps the shader safe if the buffer is ever < 14 floats (state simply falls back to instant-mouse behavior).
