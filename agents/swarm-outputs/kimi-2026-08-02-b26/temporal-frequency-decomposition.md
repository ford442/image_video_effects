# Completion: temporal-frequency-decomposition (swarm b26, Algorithmist)

## Summary of changes

Rewrote `public/shaders/temporal-frequency-decomposition.wgsl` per the brief, preserving the core 8-frame temporal DFT and adding the three wired interactions:

1. **Sprung analysis lens** — raw mouse (`zoom_config.yz`, normalised 0..1) is the target of a critically-damped spring (omega=9, k=81, c=18, fixed 60 Hz step). Persistent state in `extraBuffer[133..137]` (lensPosX/Y, lensVelX/Y, explicit init flag) ONLY; cold-start snaps to cursor, including a valid top-left pointer. One invocation persists the state, avoiding non-atomic same-value stores from every pixel. Aspect-corrected smoothstep lens mask (~0.35 radius) sharpens the frequency response (`energy * (1.0 + lensMask * 0.8)`) and widens the glow via a gamma curve (`pow(..., 1.0 - lensMask * 0.25)`).
2. **Click tuning-fork pings** — ripple loop guarded by `min(u32(u.config.y), 50u)`; each live ripple (age 0..4s) injects `cos/sin(TAU * freq * ageFrames)` weighted by an aspect-corrected ~0.2-radius ping mask and `exp(-rippleAge * 1.5)` decay directly into the DFT real/imag accumulators.
3. **Per-region FFT voices** — screen split into 8 vertical bands; each band's glow boost rides `plasmaBuffer[(band % 8u) + 1u].x * 0.4` added to the global bass boost (`1.0 + bass * 0.6 + voice`).

Also fixed the stale header comment (comment-only): `extraBuffer[0..2]` are NOT bass/mid/treble — `[4]`=historyHead, `[5..132]`=engine FFT, persistent state in `[133..255]` only.

All 4 sliders keep their exact saved-preset roles and defaults (freq / glowBright / glowHue / baseBlend via `zoom_params.x/y/z/w`, mapping constants unchanged). JSON updated verbatim from the brief: additive `updatedParams` (index 0–3) + `updated: true`; `params` array untouched.

## Line count

- Before: 114 → After: **192** (+78, inside the 164–204 target)

## Contract items preserved verbatim

- Canonical 13-binding layout + binding 13 `historyTexture` (texture_2d_array)
- `@workgroup_size(16, 16, 1)`
- Ring indexing `(historyHead + HISTORY_DEPTH - age) % HISTORY_DEPTH` (SACRED)
- `extraBuffer[4]` historyHead read — READ-ONLY, never written
- DFT accumulation loop (age 1..7), `hue2rgb` helper, magnitude/energy math, base+glow composite, alpha line
- Writes `writeTexture` + `writeDepthTexture` + `dataTextureA` every frame; `dataTextureA` = DISPLAY color
- Persistent state confined to `extraBuffer[133..137]`; no writes to [0..132]

## Naga status

`naga public/shaders/temporal-frequency-decomposition.wgsl` → **Validation successful** (no errors, no warnings).
