# Swarm Completion: melting-oil (kimi, b27)

**Status:** ✅ Complete — naga clean, zero errors/warnings.

## Line count
- Before: 116 → After: **195** (+79, within target 166–206)

## Changes
1. **Rewired 3 mislabeled sliders** (ids/names/defaults untouched — saved-preset contract):
   - `zoom_params.y` (Turbulence, 0.4) now drives a time-varying sinusoidal turbulence perturbation added to `flow_dir` (`turb * (turbK * 0.35)`); old mouseForce role moved to fixed `MOUSE_FORCE = 0.4` so the mouse gate is bit-exact at default.
   - `zoom_params.z` (Ripple Strength, 0.5) now scales click-stir amplitude: `stir *= mix(0.0, 2.0, rippleStrength)` → 1.0 bit-exact at default 0.5.
   - `zoom_params.w` (Color Shift, 0.3) now drives `hueShiftK` directly; old audio role fixed as `AUDIO_K = 1.0` multiplier on the bass boost.
2. **Legacy 8-iteration ripple loop → standard guarded form:** `let rippleCount = min(u32(u.config.y), 50u); for (var i = 0u; i < rippleCount; i++)` — stir math (exp(-dR2*60) swirl pulse, 3s alive window) preserved verbatim.
3. **Critically-damped mouse spring** in `extraBuffer[133..137]` (pos + velocity + explicit init flag, omega=12, dt=1/60; single-thread write at global_id (0,0)). Raw mouse stays the spring target; `mouseGate` gaussian formula keeps the fixed 0.4 force constant.
4. **Per-region FFT shimmer:** 8 vertical bands (`u32(clamp(uv.y,0,0.9999)*8.0)`) modulate hue phase via `plasmaBuffer[(band % 8u) + 1u].x * 0.3`, added as a separate `hue_phase` term — the `hue_shift` PHI math line itself is verbatim.
5. **Comment-only fixes:** header Category `simulation` → `artistic`; struct comments corrected (`config.y = RippleCount`, `zoom_config.w = MouseDown`, `zoom_params` roles honest); added slider-contract + uniform-truth + extraBuffer-map header docs.

## Contracts preserved (CAUTION block)
- 9-tap Sobel structure and gx/gy/grad/flow construction preserved; every neighbor load is now clamped at image borders and zero-length directions are guarded.
- Advection sampling (`last_pos`/`dimF`, `textureSampleLevel(..., 0.0)` clamped) — verbatim.
- hue_shift PHI formula and alpha formula — verbatim.
- `dataTextureA` stays DISPLAY color; `dataTextureC` reads untouched (engine manages A→C copy).
- extraBuffer touched in [133..137] only (within [133..255]).
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, writes writeTexture + writeDepthTexture + dataTextureA every frame. No binding 13 added.

## JSON
- `shader_definitions/artistic/melting-oil.json` replaced verbatim with the brief's JSON (additive `updatedParams` mirror + `updated: true`); params ids/names/defaults/ranges/mappings unchanged.

## Naga
- `naga public/shaders/melting-oil.wgsl` → **Validation successful**, no warnings.
