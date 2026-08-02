# Completion: spec-iridescence-engine (kimi, swarm b27)

**Date:** 2026-08-02
**Shader:** `public/shaders/spec-iridescence-engine.wgsl`
**JSON:** `shader_definitions/advanced-hybrid/spec-iridescence-engine.json`

## Line count

- Before: 116 lines
- After: **189 lines** (+73, within the +50..+90 expansion window; target 166–206 ✓)

## Changes

1. **Wired the dead audio (priority 1).** `plasmaBuffer` was declared and never sampled.
   - Global bass breathing: `intensity *= 1.0 + plasmaBuffer[0].x * 0.3`.
   - Per-wavelength spectral voices at the `thinFilmColor` call site:
     `iridescent.r *= 1.0 + plasmaBuffer[7].x * 0.25`, `.g` rides bin 4, `.b`
     rides bin 2 (high wavelengths → high bins), all multiplied by the
     bass-breathed intensity.
2. **Sprung film lens.** Critically-damped spring (omega=10, fixed dt=0.016)
   chasing the raw mouse; persistent state in `extraBuffer[133..137]`
   (pos.xy, vel.xy, explicit init flag) — [0..4] reserved, [5..132] engine FFT untouched.
   All invocations compute the same current-frame state and thread (0,0) persists it. Always-on aspect-corrected
   gaussian thickness lens around the sprung point:
   `thickness += 80nm * exp(-d²/0.25²)`. The existing mouseDown perturbation
   now rides the SPRUNG position (verbatim math, `mousePos → sprung`).
3. **Click film waves.** Ripple loop guarded by
   `min(u32(u.config.y), 50u)`; each live ripple (age 0–1.5s) adds
   `150nm * sin(age*20 - dist*40) * exp(-age*2) * ring` with an expanding
   aspect-corrected ring mask (`exp(-|dist - age*0.45| * 18)`).
4. **4 sliders wired via `u.zoom_params.x/y/z/w`** with the existing JSON
   param ids/defaults (saved-preset contract preserved): Film Thickness →
   `mix(200,800)` nm, Film IOR → `mix(1.2,2.4)`, Intensity → `mix(0.3,1.5)`
   (then bass-breathed), Turbulence → `mix(0,1)` noise amplitude.

## Contracts preserved (CAUTION block)

- `hash12`, `wavelengthToRGB`, `thinFilmColor` (spectral loop 380–700nm @
  20nm, OPD/cosTheta_t math) kept **verbatim**.
- Depth+noise thickness construction, fresnel blend
  (`pow(1-cosTheta,3)`, `mix(base, iridescent, fresnel*0.7)`), HDR tonemap
  (`outColor / (1.0 + outColor*0.2)`) kept verbatim.
- `alpha = thickness / 1000.0` semantic retained and clamped to [0,1] in **both** writes
  (`writeTexture` and `dataTextureA`); `dataTextureA` packing stays
  `(iridescent, thickness/1000)`.
- Canonical 13-binding layout unchanged; no binding added/renumbered; no
  binding-13 historyTexture. `@workgroup_size(16, 16, 1)`.
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame.
- extraBuffer usage confined to **[133..255]** only ([133..137] used).
- A missing global-invocation bounds guard was added, and the already sampled depth value is reused for the pass-through write.
- Engine uniform truth respected: config=[time, rippleCount, resW, resH],
  zoom_config=[time, mouseX, mouseY, mouseDown].

## JSON

- Added the additive `updatedParams` mirror (indices 0–3, matching
  names/defaults/min/max/step), `updated: true`, and the truthful
  `audio-reactive` feature. Validated as parseable JSON.

## Naga

- `naga public/shaders/spec-iridescence-engine.wgsl` → **Validation successful** (no errors, no warnings).

## Notes / ambiguities

- Ripple record semantic assumed `ripples[i] = (clickX, clickY, startTime, _)`
  per repo convention; loop is guarded and age-clamped to 1.5s so stale
  slots are no-ops.
- No other files modified; no git commands run; precommit gate left to the
  coordinator.
