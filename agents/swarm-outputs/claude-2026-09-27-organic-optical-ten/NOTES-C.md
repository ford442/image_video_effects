# NOTES — Group C (Track B second-pass): reaction-diffusion, dragonfly, oracle-jelly

## gen-bioluminescent-reaction-diffusion
- Existing ideas' code confirmed intact and untouched: Gray-Scott reaction, 9-tap Laplacian via `loadStateClamped`, luciferin quench decay/growth, excitation-front flash.
- New ideas landed: (3) pointer-wake luciferin-age reset (`luciferinAge = mix(luciferinAgeGrown, 0.0, mouseSeed * 0.85)`), (4) quorum-sensing ignition flash using the already-loaded 8-neighbor samples (`neighborMaxB`, `isLocalMax`, `ignition`), added into `finalRGB`.
- A packing unchanged: raw `(A, B, luciferinAge, 1)` in `dataTextureA`, never tone-mapped. No new state, no new texture reads.
- Header: `Upgraded: 2026-09-27`, `Ideas:` appended (old text preserved verbatim + 2 new). No JSON change needed — `features` already accurate.
- naga: PASS.

## gen-celestial-quantum-glass-dragonfly
- Existing ideas' code confirmed intact: Cauchy thin-film dispersion, quantum glass caustic core/eye glow, acoustic wingtip vortex trail in the fog loop, spring-damper cursor, exact-load `dataTextureC` 6% trail blend.
- New ideas landed: (4) velocity-banked flight roll — `bank = clamp(mouseVel.x * 0.35, -0.5, 0.5)` computed once in `main()`, consumed as an extra `rot3z(bank)` in `mapScene`'s scene transform (threaded through `mapScene`/`getNormal` signatures, which now also carry a `treble` param). (5) vortex-synced wingtip flutter inside `mapWings` — reuses the same `sin(dist*4 - time*8)` / `pow(max(x,0),6)` shape as the fog's `vortexWave`/`vortexEmission`, applied as a small subtractive bump at the trailing edge (`abs(p_w.x)` large), amplitude scaled by `treble`.
- Deviation from card: rather than literally reusing the fog loop's `vortexWave` variable (out of scope inside `mapWings`, different coordinate domain), re-derived the same functional form locally using the wing's own local coordinates and the function's already-scaled local `time` — same "vortex" identity, native to the wing SDF rather than copy-pasted across scopes.
- Fixed the missing `Upgraded:` header line (previously absent entirely) → `Upgraded: 2026-09-27`. Added `upgraded-rgba` to JSON `features` (ACES + Idea Card are both genuinely implemented; tag was simply missing before).
- A packing unchanged: display RGBA (ACES-toned scene color + semantic alpha) in `writeTexture`/`dataTextureA`; `dataTextureC` still read exactly for the existing trail.
- naga: PASS.

## gen-chromatic-oracle-jelly
- Existing ideas' code confirmed intact: pulse-swim contraction/coast (`swimPhase`), pointer-tracking pupil with seeded blink (`gaze`, `blinkPhase`/`lid`).
- New ideas landed: (3) tentacle-anchored luminous wake — a second `historyLoadUV` sample offset along `tentaclePhase`, screened additively into `hdr` scaled by the `tentacles` mask (`tentacleWake * tentacles * 0.55`). (4) click-triggered startle contraction — relocated the existing ripple loop earlier (before the pulse-swim `contraction` calc) and added a `startleKick` accumulator (ripples younger than 0.6s near the cell's world-space center), folded into `contraction` and clamped to `[0, 1.4]`. (5, optional) audio-linked pupil dilation — bass (`audio.x`) widens the pupil falloff radius.
- Deviation from card: relocated the pre-existing ripple `for` loop (previously computing only `clickOracle` for the deep-glow ring) earlier in the function rather than duplicating it, so `startleKick` and `clickOracle` share one pass — avoids a second 50-iteration loop. `clickOracle` usage further down is unaffected (same variable, computed earlier).
- A packing unchanged: ACES display RGBA, read back as color history via `historyLoadUV`. No new state added.
- Header: `Upgraded: 2026-09-27`, `Ideas:` appended (old text preserved verbatim + 3 new). JSON already lists `click-reactive`/`audio-reactive`/`mouse-driven`/`upgraded-rgba` — no change needed.
- naga: PASS.

## Summary
| Shader | naga | JSON updated |
|---|---|---|
| gen-bioluminescent-reaction-diffusion | PASS | no (already accurate) |
| gen-celestial-quantum-glass-dragonfly | PASS | yes — added `upgraded-rgba` |
| gen-chromatic-oracle-jelly | PASS | no (already accurate) |

No `params` were renamed or re-defaulted on any of the three. No spring/ripple/palette overlays added beyond what each card explicitly permitted.
