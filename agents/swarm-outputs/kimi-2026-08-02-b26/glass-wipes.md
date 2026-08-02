# Swarm Completion: glass-wipes (Rainy Window)

**Agent:** kimi b26 | **Role:** Interactivist | **Date:** 2026-08-02

## Line count
- WGSL: 115 → 173 (target 165–205 ✓, +58)
- JSON: replaced with the brief's verbatim JSON (additive `updatedParams` mirror + `updated: true`; param ids/names/defaults/min/max/step untouched)

## Changes implemented
1. **Spring-damper wiper (priority 1):** critically-damped spring (omega=12, stiffness=omega², damping=2*omega, dt=0.016) integrated by thread (0,0) into `extraBuffer[133..137]` (sprung pos xy + vel xy + explicit init flag). All threads read the sprung position; raw mouse stays the spring target. First touch seeds at cursor without confusing top-left with uninitialized state. Aspect-corrected wiper distance preserved.
2. **Click splashes:** ripple loop guarded by `min(u32(u.config.y), 50u)`; each young ripple (age < 0.3s) stamps a wetness splash (`wetness += 0.5 * smoothstep(0.15, 0, rDist)`, aspect-corrected, clamped to 1.0).
3. **Dead audio wired:** `bass = plasmaBuffer[0].x` drives rain bursts (`rainIntensity *= 1.0 + bass * 0.8`); 8 horizontal bands each sparkle their specular via `plasmaBuffer[(band % 8u) + 1u].x * 0.3`. Definition metadata now truthfully includes `audio-reactive`.
4. **Stale header comment fixed:** 'Category: distortion' → 'liquid-effects' (comment-only).

## Contract items preserved VERBATIM
- Wetness state contract: `dataTextureA` write is exactly `vec4<f32>(wetness, 0.0, 0.0, wetness)` — raw state, never tonemapped; prev wetness read from `dataTextureC`.
- Beer-Lambert absorption `exp(-(1.0 - waterColor) * thickness * glassDensity)`, Fresnel R0=0.02, thickness = wetness*0.05, transmission mix, droplet distortion noise hashes, specular `pow(light, 20.0) * wetness * 0.5` — all verbatim.
- `zoom_params.w` double duty kept (evaporation AND glassDensity).
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, writes to writeTexture + writeDepthTexture + dataTextureA every frame.
- extraBuffer usage confined to [133..137]; [0..4] reserved / [5..132] engine FFT untouched.
- All 4 slider ids/names/defaults/min/max/step EXACTLY as before; updatedParams indices 0–3 match zoom_params x/y/z/w mapping order.

## Validation
- `naga public/shaders/glass-wipes.wgsl` → **Validation successful**, exit 0, no errors/warnings.
- JSON parses cleanly.
