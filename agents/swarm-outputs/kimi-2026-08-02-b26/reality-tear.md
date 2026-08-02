# Swarm Completion: reality-tear (kimi, b26)

**Status:** DONE
**Lines:** 115 → 193 (target 165–205, +78)
**Naga:** `Validation successful` — clean exit, no errors/warnings
**JSON:** brief JSON applied verbatim (params ids/defaults unchanged, updatedParams 0–3 mirror, `updated: true`); parses clean

## Changes

1. **Spring-damper tear center (priority 1):** `extraBuffer[133..137]` = eased pos.xy + vel.xy + explicit init flag ([0..4] reserved / [5..132] engine FFT untouched). Critically damped spring (fixed 60 Hz step, ~2.5 Hz settle), raw mouse (`zoom_config.yz`) stays the spring target, and top-left remains a valid position. Every pixel computes the same local step, while only invocation (0,0) persists state. Existing aspect correction preserved (applied after the spring).
2. **Click rifts:** ripple loop guarded by `min(u32(u.config.y), 50u)`; each live ripple (age 0–1.5s) opens a secondary tear at its click point, radius `0.15 * sin(life * PI)` (grows then collapses, max 0.15), evaluated through the same void/border/select pipeline and composed branchlessly (`select()` over masks; border under void, over main tear). Rift masks also feed voidMask/borderMask/edgeProx via `max()`.
3. **Angular FFT voices:** 8 angular sectors (`u32((angle + PI) / TAU * 8.0) % 8u`), each modulating the dual-octave noiseVal by `plasmaBuffer[sector + 1u].x * 0.3`; treble bins 5–8 (`plasmaBuffer[5u + (sector % 4u)].x`) flicker the burn color per sector on top of the global treble term.
4. **Sliders:** existing 4 params wired via `zoom_params.x/y/z/w` with roles EXACTLY as before (size→radiusBase, jagged→jaggedness, border→borderWidth, static→staticAmt), same audio modulation.

## Contract items preserved verbatim

- Canonical 13-binding layout, no adds/renumbers; `@workgroup_size(16, 16, 1)`
- `hash21` / `valueNoise2D` helpers VERBATIM; dual-octave angular noise lines VERBATIM (modulation applied to the result); `currentRadius` construction unchanged in shape
- Branchless `select()` void/border composition; void static/inverted mix (`mix(inverted, voidStatic, 0.5)`)
- Alpha formula VERBATIM: `clamp(baseA * 0.4 + voidMask * 0.4 + borderMask * 0.6 + edgeProx * 0.3 + bass * 0.1, 0.0, 1.0)`
- `dataTextureA` stays DISPLAY color (`vec4(finalRGB, alpha)`); writeTexture + writeDepthTexture + dataTextureA written every frame
- All new logic branchless (select/step/smoothstep/max); PI/TAU defined locally; no reserved identifiers
- extraBuffer writes confined to [133..137]

No other files modified. No git commands run. Precommit gate not run (coordinator's job).
