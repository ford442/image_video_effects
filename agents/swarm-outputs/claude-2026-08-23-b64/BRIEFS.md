# Batch 64 briefs — 2026-08-23 (tracker #511–520)

**Status: CLAIMED.** Ten liquid / optical / crystal / cyber shaders. Tracker
entries #511–520 are reserved by this batch; parallel agents should take #521+.

Note on the request: `glass-refraction.wgsl` does not exist in `public/shaders/`.
The intended target is `glass_refraction_alpha` (underscore variant,
`shader_definitions/artistic/`), confirmed with the requester before work began.

| # | Shader | Standing | Upgrade focus |
|---|--------|----------|---------------|
| 511 | `optical-feedback` | worst | Time-correct spring, ripple shockwaves, per-band hue rotation |
| 512 | `glass_refraction_alpha` | legacy | Cauchy-dispersion refraction, per-band caustic focusing |
| 513 | `crystal-facets` | legacy | Facet-normal Fresnel with TIR, crystal-axis birefringence |
| 514 | `ambient-liquid` | legacy | Real Gray-Scott state, metaball surface-tension coupling |
| 515 | `frosted-glass-lens` | legacy | Beckmann roughness lobe, depth-dependent frost thickness |
| 516 | `cyber-lens` | partial | Rolling-shutter scan skew, per-band HUD telemetry rings |
| 517 | `bubble-lens` | partial | Thin-film interference on the wall, Marangoni drainage |
| 518 | `liquid-metal` | partial | Ferrofluid spike instability, anisotropic metal BRDF |
| 519 | `magnetic-interference` | modern | Per-band domain-wall spectrum, hysteresis memory through C |
| 520 | `digital-mold` | modern | Nutrient-gradient chemotaxis, sporulation click bursts |

## Shared contract

- Canonical 13 bindings, `@workgroup_size(16, 16, 1)`, bounds guard.
- Preserve source `params` ids/names/defaults/ranges; corrections land in
  additive `updatedParams`.
- `plasmaBuffer[0].xyz` audio plus per-band `plasmaBuffer[1..8].x`.
- Held pointer via `zoom_config.w`; spring-damped pointer state confined to
  `extraBuffer[133..138]`, written only by invocation `(0,0)`.
- Click loops guarded `min(u32(u.config.y), 50u)`.
- Exact `textureLoad` for `dataTextureC`; manual bilinear where advection needs
  sub-pixel. Never the filtering sampler on rgba32float.
- ACES tone map and semantic alpha before write.
- Display RGBA in `dataTextureA` unless the shader runs a genuine simulation, in
  which case A carries state, display goes to `writeTexture`, diagnostics to B.

## Bugs targeted

1. **`optical-feedback` uses `u.config.y` as delta time.** That field is the
   ripple count (`docs/BINDING_CONTRACT.md` do-not-reintroduce list). It feeds a
   spring integrator, so with no clicks `dt == 0` and the smoothed pointer and
   hue are frozen; with clicks it jumps to 1–50 and the integrator explodes.
2. **`optical-feedback` writes nine state values into `extraBuffer[0..8]`** —
   the engine's bass / mid / treble / reserved / `historyHead` / FFT bins 5–8.
   It corrupts the audio the whole chain reads. Currently carried as nine
   grandfathered entries in the extraBuffer audit baseline; this batch retires
   them by moving the state to `[133..135]`.
3. **`magnetic-interference` ripple loop is unguarded** (`u32(u.config.y)` with
   no `min(..., 50u)`).
4. **`ambient-liquid` advertises `reaction-diffusion` with no state at all** —
   it never writes A nor reads C. A real Gray-Scott step gets wired.
5. **`glass_refraction_alpha` never reads `plasmaBuffer`** despite binding it.

## Validation

Structural only in this container: `wgsl_precommit_gate.py` (naga + bindgroup +
workgroup + extraBuffer), `audit_extrabuffer.py`, `audit_dead_sliders.py`,
`audit_audio_mappings.py`, `audit_config_y_misuse.py`, shader-list and uniform
checks, Jest, production build. Real-GPU visual QA remains external.
