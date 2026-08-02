# Swarm Completion: aero-chromatics (b27, Interactivist)

**Status:** DONE — naga clean, no errors/warnings.

## Line count
- Before: 117 → After: 179 (+62, within 167–207 target)

## Changes
- **Wired the dead audio (priority 1):**
  - Bass gusts: `bass = plasmaBuffer[1].x`, then `windStrength *= 1.0 + bass * 0.6` so drops push the smoke.
  - Per-band flutter: 8 horizontal bands (`band = min(u32(uv.y * 8.0), 7u)`), each wobbles its velocity perpendicular component by `plasmaBuffer[(band % 8u) + 1u].x * 0.003` along the normalized perpendicular of the flow.
- **Sprung wind source:** critically-damped spring (k=60, damp=2·√k, dt=0.016) chasing the raw mouse; state in `extraBuffer[133..137]` (pos + vel + explicit init flag). All invocations compute the coherent current-frame state; thread (0,0) persists it. Aspect-corrected directions are safely converted back to UV space.
- **Click gust bursts:** ripple loop guarded by `min(u32(u.config.y), 50u)`; each live ripple (age 0–1.5s) adds `aspect-corrected dir * 0.02 * exp(-rippleAge * 2.0) * smoothstep(0.35, 0.0, distR)` to velocity. Stale struct comment fixed (comment-only): `config.y = RippleCount`.
- **Sliders:** 4 existing params wired via `u.zoom_params.x/y/z/w` with unchanged ids/names/defaults/ranges/mappings (windStrength, decay, chromaSplit, sourceMix); each still drives a real constant of the algorithm, windStrength now additionally rides bass.

## Contracts preserved
- Canonical 13-binding layout, no additions/renumbering; `@workgroup_size(16, 16, 1)`.
- Feedback contract SACRED: dataTextureC read as advected history (3 chromatic offsetR/G/B taps + alpha carry), dataTextureA written with display color, no tonemap on A write.
- Original dev commentary and the luma-drag/advection model remain intact; dead locals and the fourth unused history-alpha sample were removed.
- baseWind/mouseWind construction, decay/injectAmount mix, and depth-weighted alpha remain intact.
- extraBuffer use confined to [133..255] (indices 133–137 only).
- writeTexture + writeDepthTexture + dataTextureA written every frame.
- `textureSampleLevel(..., 0.0)` for sampler reads.

## JSON
- `shader_definitions/simulation/aero-chromatics.json` has additive `updatedParams` indices 0–3, `updated: true`, and truthful `depth-aware` / `audio-reactive` features. Parses clean.

## Validation
- `naga public/shaders/aero-chromatics.wgsl` → **Validation successful** (no errors, no warnings).
- Did not run `wgsl_precommit_gate.py` (coordinator runs it centrally). No other files touched; no git commands used.
