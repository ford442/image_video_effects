# Swarm Completion: interactive-zoom-blur (distortion)

**Agent:** kimi b26 · **Role:** Optimizer · **Date:** 2026-08-02

## Summary of changes

Rewrote `public/shaders/interactive-zoom-blur.wgsl` per the brief (upgrade, not rewrite):

1. **Spring-damper epicenter (priority 1):** raw mouse (`u.zoom_config.yz`) is now only the spring *target*. Thread (0,0) integrates a critically-damped spring (omega = 10.0, dt clamped [0.001, 0.05]) into `extraBuffer[133..138]` ([133..134] pos, [135..136] vel, [137] last time, [138] init flag — all inside the allowed [133..255] range; [0..4] reserved and [5..132] engine FFT untouched). All threads read the smoothed center. Spring lag feeds the motion bonus exactly as specified: `strength *= 1.0 + min(springSpeed * 4.0, 0.5)`.
2. **Click zoom shockwaves:** ripple loop guarded with `min(u32(u.config.y), 50u)`; each live ripple (`vec4(x, y, startTime, _)`, verified against `src/renderer/UniformBuffer.ts`) adds a decaying radial blur pulse to `attenuatedStrength`: `exp(-rippleAge * 2.0) * smoothstep(0.3, 0.0, aspectCorrectedDist) * 0.6`, active only for `rippleAge in [0, 1.2]`.
3. **Per-ring FFT voices:** inside the 3-accumulator sample loop, each tap is weighted by `1.0 + plasmaBuffer[(u32(t * 8.0) % 8u) + 1u].x * 0.15`, so blur rings shimmer across the spectrum.
4. **Header fix:** stale `Category: image` → `Category: distortion` (comment-only); feature list extended with spring-damper-epicenter, click-zoom-shockwaves, per-ring-fft-voices; date bumped to 2026-08-02.
5. **Sliders:** all 4 honestly wired with roles kept EXACTLY — `zoom_params.x` = Blur Strength (bass-reactive + spring motion bonus), `.y` = Chromatic Amount (r/g/b spreads), `.z` = Quality (sample-count mapping 5..35), `.w` = Depth Attenuation.

## Contract items preserved VERBATIM

- `bayer()` 4x4 dither matrix and `hash11` helper — unchanged.
- 3-accumulator r/g/b chromatic loop with `rSpread`/`gSpread`/`bSpread` formulas — unchanged (only `* tapWeight` appended per brief).
- Sample-count mapping `i32(sampleCount * 30.0 + 5.0)` — unchanged.
- Depth attenuation `strength * (1.0 - depth * depthAttenuation)` — unchanged expression.
- Temporal trail: `dataTextureC` read via `textureSampleLevel`, `mix(color, prev * 0.88, 0.05 + mids * 0.02)`, then `mix(color, trail, 0.3)` — unchanged.
- `effectBlend = smoothstep(0.0, 1.0, dist * attenuatedStrength)` — unchanged.
- `dataTextureA` written with the same DISPLAY color as `writeTexture`; `writeDepthTexture` passes depth through. All three written every frame.
- Canonical 13-binding layout (0–12, no renumbering, no binding 13), `@workgroup_size(16, 16, 1)`.

## JSON

`shader_definitions/distortion/interactive-zoom-blur.json` replaced with the brief's JSON verbatim (additive `updatedParams` indices 0–3 mirroring existing params + `"updated": true`); nothing else changed.

## Line count

115 → **172** (+57; target 165–205 ✓)

## Naga status

`naga public/shaders/interactive-zoom-blur.wgsl` → **Validation successful**, exit 0, no errors/warnings.
