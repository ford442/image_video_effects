# Swarm Completion: spectral-waves (Luma Ripple)

**Batch:** kimi-2026-08-02-b27 · **Role:** Visualist · **Status:** ✅ Complete

## Changes

1. **Sprung wave origin (priority 1):** Critically-damped spring (Game Programming Gems 4 formulation, omega=9.0, dt=1/60) eases the ripple epicenter toward the raw cursor. State persists in `extraBuffer[133..137]` ([133..134]=pos, [135..136]=vel, [137]=explicit init flag) — [0..4] reserved and [5..132] engine FFT untouched. Every thread integrates the same state deterministically; only thread (0,0) writes it back, so the whole frame uses a consistent sprung origin. Raw mouse stays the spring target; the aspect-space radial direction is safely converted back to UV space.
2. **Click wave trains:** Loop over `u.ripples[]` guarded by `min(u32(u.config.y), 50u)`. Each live ripple (age 0..2s) emits `sin(distR * frequency * 0.8 - rippleAge * 8.0) * exp(-rippleAge * 1.5) * maxAmplitude * 0.8` in an aspect-corrected falloff (`exp(-distR*3.0)` with a 1.6–2.0s fade), composed into `displacement` before the 3-tap chromatic aberration.
3. **Per-ring FFT voices:** Radial distance quantized into 8 rings; `plasmaBuffer[(ring % 8u) + 1u].x * 0.35` added into the caustic term (`+ pow(crest, 2.0) * ringVoice`), so each ring's crest glow rides its own bin.
4. **Stale comments fixed (comment-only):** `config.y = RippleCount`, `zoom_config.w = MouseDown`, `zoom_params` components named per slider, `ripples[]` layout documented.
5. **JSON:** `shader_definitions/interactive-mouse/spectral-waves.json` replaced with the brief's JSON verbatim (same 4 param ids/names/defaults/min/max/step + additive `updatedParams` mirror index 0–3 + `updated: true`). Slider wiring unchanged and honest: x→ripple frequency (10–100 rad), y→wave speed (0–5), z→intensity/amplitude (bass/treble boosted), w→chromatic split (0–0.05).

## Contracts preserved

- Canonical 13-binding layout, no renumbering; no binding 13 (not previously used).
- `@workgroup_size(16, 16, 1)`; writes `writeTexture` + `writeDepthTexture` + `dataTextureA` every frame.
- `getLuminance`/`palette`/`aces`/`ign` helpers, dual-wave construction (wave + echoWave), crest smoothsteps, displacement luma weighting, 3-tap chromatic aberration with `safeDir`, spectral/caustic/bass-glow HDR assembly, radial vignette, IGN dither, alpha formula — all verbatim.
- PREMULTIPLIED `finalRGBA = vec4(finalColor * alpha, alpha)` verbatim; `dataTextureA` stores the same premultiplied value as `writeTexture`.
- `extraBuffer` written only in [133..137]; sampler reads via `textureSampleLevel(..., 0.0)`.

## Metrics

- **Line count:** 116 → **180** (+64, target 166–206 ✓)
- **Naga:** `naga public/shaders/spectral-waves.wgsl` → **Validation successful** (0 errors, 0 warnings)
