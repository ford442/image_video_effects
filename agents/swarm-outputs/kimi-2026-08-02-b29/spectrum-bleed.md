# spectrum-bleed — Swarm b29 Completion Note

**Shader:** `spectrum-bleed` (retro-glitch) — Agent: Kimi (Algorithmist)
**Date:** 2026-08-02

## Lines

- Before: **118** → After: **170** (+52, within the 168–208 target)

## Changes

1. **FIXED THE CATASTROPHIC UNIFORM BUG (priority 1):** the shader read `u.zoom_config.x/y/z` (time + mouse position) as diffusion/hueDrift/satBoost while all 4 real `zoom_params` sliders were dead. All parameter reads now come from `u.zoom_params`:
   - `x` (Intensity, 0.5) → `blendFactor = x * 0.6` (default 0.3 = prior mid-bleed look)
   - `y` (Speed, 0.5) → hue drift rate: `newHue = fract(hsv.x + y * time * 0.1 + bandPhase)`
   - `z` (Scale, 0.5) → blur radius: `sampleBlur(..., radius)` with `texel = radius / u.config.zw`, radius = `mix(1.0, 4.0, z)` — the spread is real now
   - `w` (Detail, 0.5) → `satBoost = w * 0.5` (default 0.25, legal bleed)
   - `zoom_config.yz` restored to its true role: the mouse.
2. **DELETED the idempotent blur-passes loop** (passes 2+ re-sampled the source into the same variable, changing nothing). `sampleBlur` is parameterized by radius instead; the 4-tap kernel itself is preserved verbatim.
3. **Honest sprung mouse lens:** critically-damped spring (stiffness 90, zeta=1) chases the raw cursor; state in `extraBuffer[133..136]` (pos.xy, vel.xy), `[137]` lastTime, `[138]` initialized — [0..4] reserved and [5..132] engine FFT untouched. Aspect-corrected `lensMask = smoothstep(0.35, 0.0, dist)` raises `blendFactor += lensMask * 0.3` so colour bleeds outward from the pointer.
4. **Click ink splatters:** ripple loop guarded with `min(u32(u.config.y), 50u)`; each live ripple stamps `hsv.y += 0.4 * falloff * exp(-age * 2.0)` (~1.5s lifetime, clamped ≤ 1.0).
5. **Per-band FFT hue shimmer:** 8 vertical bands; each band shifts its hue drift phase by `plasmaBuffer[(band % 8u) + 1u].x * 0.2`.
6. Removed the dead `drifted` variable (was computed and never used).

## Contracts preserved

- Canonical 13-binding layout unchanged; no bindings added/renumbered; no binding 13.
- `@workgroup_size(16, 16, 1)`; writes `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- `rgb2hsv` / `hsv2rgb` helpers verbatim (branchy hsv2rgb tier style kept — file character).
- 4-tap `sampleBlur` kernel verbatim (only the radius multiplier added).
- Temporal feedback verbatim: `A = (persist, 1.0)` write, `dataTextureC` read, `0.93` decay, `persist = max(prev * 0.93, outCol)`.
- Depth passthrough verbatim: `textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0))`.
- `textureSampleLevel(..., 0.0)` for sampler reads; no reserved-keyword identifiers.
- extraBuffer usage confined to [133..138] (within [133..255] only).
- All 4 slider ids/names/defaults/ranges EXACT (param1–4, Intensity/Speed/Scale/Detail, 0.5, 0–1, 0.01) — JSON `params` untouched; additive `updatedParams` (index 0–3) + `updated: true` applied verbatim from the brief; nothing else in the JSON changed.

## Naga validation

`naga public/shaders/spectrum-bleed.wgsl` → **Validation successful** (clean, zero errors/warnings).

## Coordinator closeout

- Final lines: **118 → 171 (+53)**. Added the missing invocation bounds guard, clamped all radius-blur taps, and made every invocation derive the same current spring step before the sole `(0,0)` persistence write.
- All four saved-preset controls now map to `zoom_params`; raw max/persist A feedback and depth pass-through remain unchanged.
- Final focused gate, dead-slider/strict-buffer audit, JSON/list parity, Jest, and production build: pass.
