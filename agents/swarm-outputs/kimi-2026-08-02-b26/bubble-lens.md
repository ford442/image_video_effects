# Swarm b26 Completion: bubble-lens (distortion)

**Status:** DONE
**Lines:** 116 -> 208 (+92)
**Naga:** `naga public/shaders/bubble-lens.wgsl` -> "Validation successful", zero errors/warnings.

## Changes

1. **Spring-damper buoyancy (priority 1):** critically-damped spring (stiffness 90, damping 2*sqrt(90), zeta=1) eases the bubble center toward the raw mouse target. State in `extraBuffer[133..136]` (pos.xy, vel.xy) + `[137]` lastTime + `[138]` explicit init flag; integrated by thread (0,0) only, dt clamped to 0.05. Top-left is a valid target rather than an uninitialized sentinel. Aspect-corrected delta kept. No writes outside [133..255]; [0..4] reserved and [5..132] engine FFT untouched.
2. **Click pops + satellite bubbles:** ripple loop guarded by `min(u32(u.config.y), 50u)`. Each live ripple (age 0..1.2s) spawns a satellite bubble at the click point (radius 0.06*(0.4+0.6*grow), grow-in 0.18s, pop-out 0.85-1.2s) reusing the same lens displacement + interference evaluation at reduced strength (magnification halved toward 1, filmThickness*0.7), with a coarse radius cull before the expensive evaluation. It also adds a film-shockwave on the main bubble: a Gaussian ring (`exp(-pow((clickDist-wavefront)*16,2))`, wavefront = age*0.55, decaying over 1.2s) that perturbs drainedThickness.
3. **Per-octave FFT shimmer:** broad noise octave weighted by `(1.0 + (plasmaBuffer[2].x-0.5)*0.3)`, fine octave by `(1.0 + (plasmaBuffer[6].x-0.5)*0.3)` = +/-15%. `audio.x` still on filmThickness, `audio.y` still on spec.
4. **Sliders:** exactly the 4 existing params via `u.zoom_params.x/y/z/w` with unchanged ids/defaults/ranges and unchanged shader-specific mappings (BubbleSize->radius, Magnification->lens, FilmThickness->film, IOR->Schlick). JSON updated verbatim from brief (additive `updatedParams` index 0-3 + `updated: true`); nothing else touched.

## Contract items preserved VERBATIM

- dataTextureA packing: `(inside, drainedThickness * 0.2, spec, finalAlpha)` — MASK data, not display color (values sourced from main-bubble eval fields).
- `safeNormalize` helper, lens displacement math, drainage/turbulence/drainedThickness construction, 3-phase interference cosines (phase, +2.09, +4.18) + blackSpot mix, Schlick fresnel from ior, rim/spec terms, transmittance/alpha clamps — all moved into `evalBubble()` with formulas character-identical (shockwave/shimmer applied as external multiplicative terms, construction untouched).
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, writes to writeTexture + writeDepthTexture + dataTextureA every frame, `textureSampleLevel(..., 0.0)` sampler reads, no binding 13, no reserved-keyword identifiers.
- Engine truth used: config=[time, rippleCount, resW, resH], zoom_config=[time, mouseX, mouseY, mouseDown].

## Files touched

- `public/shaders/bubble-lens.wgsl` (rewritten)
- `shader_definitions/distortion/bubble-lens.json` (brief JSON verbatim)

No other files modified; no git commands run; precommit gate left to coordinator.
