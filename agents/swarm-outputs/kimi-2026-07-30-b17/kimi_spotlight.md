# Agent Notes — kimi_spotlight (Batch 17, Interactivist)

## Lines
- **Before:** 94 lines
- **After:** 163 lines (+69, within the +50..+90 target / 144–184 window)

## Techniques implemented (all 3 from the brief)

1. **Spring-damper spotlight glide (priority 1).** The beam no longer snaps 1:1
   to the cursor. A critically-damped spring (stiffness 36, damping 12 = 2·√36)
   eases the spotlight center toward the mouse. State lives in
   `extraBuffer[133..138]` ONLY (pos xy, vel xy, lastTime, init flag);
   [0..4] reserved and [5..132] engine FFT bins untouched. Single writer
   thread (global_id 0,0) integrates with `dt = clamp(time - lastTime, 0, 0.1)`;
   all threads read the smoothed center. Negative-mouse sentinel glides the
   beam back to screen center. The existing `clickPulse` term is preserved
   verbatim and applied AFTER the spring, as required.

2. **Click light rings.** Loop over `u.ripples[]` guarded by
   `min(u32(u.config.y), 50u)`. Each live ripple (age 0–2s) emits an expanding
   luminous ring from its click point: `ringRadius = age * 0.4`, band via
   `smoothstep(0.08, 0.0, |rDist - ringRadius|)`, intensity decaying
   `exp(-age * 2)` (~2s life). The accumulated `ringGlow` locally lifts the
   desaturated darkness (flash-reveal) through a `reveal` factor added into
   the existing mix, plus a faint cool-white additive tint.

3. **Honest depth + audio rim.** `writeDepthTexture` now gets a real depth
   bump: `clamp(depthIn + spotlight * 0.05, 0, 1)` instead of pure passthrough.
   Per-bin treble (`(plasmaBuffer[6].x + [7].x + [8].x) / 3`) drives a
   `rimFlicker` multiplier on the beam rim band (with a time/dist shimmer),
   in addition to the kept global-treble alpha term.

## What each slider now drives (ids/defaults/mapping unchanged — preset contract kept)

- **Spotlight Size** (`zoom_params.x`): base beam radius, `mix(0.1, 0.6, x)`,
  still pulsed by bass/mids — unchanged mapping (already shader-specific).
- **Edge Softness** (`zoom_params.y`): smoothstep edge width of the beam falloff,
  `mix(0.001, 0.5, y)` — unchanged.
- **Edge Darkness** (`zoom_params.z`): how dark the desaturated surroundings get,
  `mix(0.1, 1.0, z)` multiplier — unchanged.
- **Color Boost** (`zoom_params.w`): saturation boost inside the spot,
  `mix(1.0, 3.0, w)` — unchanged.

The existing mapping was already shader-specific (not generic boilerplate), so
sliders keep their exact wiring per the CAUTION/contract; interactivity gains
come from the spring, rings, and rim flicker around them.

## CAUTION compliance (VERBATIM preserved)
- Desaturate-outside / saturate-inside mix structure: `mix(desaturated * edgeDarkness, saturated, X)` intact.
- Beam ring band `abs(dist - spotSize * 0.8)` and its `* 0.2 * spotlight` core intact (flicker appended as a multiplier).
- Hotspot term `smoothstep(spotSize * 0.3, 0.0, dist) * 0.3` verbatim.
- `clickPulse` formula verbatim, applied after the spring.
- `dataTextureA` stays DISPLAY color (same `finalRGBA` as `writeTexture`).
- extraBuffer used only in [133..255] (specifically [133..138]).

## Contract compliance
- 13-binding canonical layout unchanged, no binding 13 added.
- `@workgroup_size(16, 16, 1)`; writes `writeTexture`, `writeDepthTexture`,
  `dataTextureA` every frame.
- All sampler reads use `textureSampleLevel(..., 0.0)`; no `textureLoad` needed.
- No WGSL reserved keywords as identifiers (`springTarget`, not `target`).
- JSON: added ONLY `updatedParams` (indices 0–3) and `"updated": true`;
  existing params untouched (no rename/re-default/reorder).

## Deviations
- None from the brief's techniques. Minor note: brief text mentioned
  "extraBuffer[133..134]" for the spring; the implementation uses [133..138]
  (pos + vel + time + init flag) for a proper velocity-based spring — still
  strictly inside the allowed [133..255] range.
