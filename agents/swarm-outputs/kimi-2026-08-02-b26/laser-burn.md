# Swarm Completion: laser-burn (kimi, 2026-08-02, batch b26)

## Summary
Upgraded `public/shaders/laser-burn.wgsl` per the Interactivist brief. Three
techniques implemented on top of the preserved burn state machine:

1. **Spring-damped beam** — heavy critically-damped spring (omega = 6,
   `a = w^2*(target-pos) - 2w*vel`, fixed dt = 1/60) eases the beam toward
   the raw cursor. State lives in `extraBuffer[133..137]` (posX, posY, velX,
   velY, explicit init flag) — [0..4] reserved and [5..132] engine FFT
   untouched; nothing outside [133..255] used. Cold-start snap prevents the
   initial streak from (0,0) without making top-left an invalid cursor target.
   All invocations compute the same local step; only invocation (0,0) persists
   state, avoiding non-atomic same-value writes.
2. **Click brand stamps** — ripple loop guarded by
   `min(u32(u.config.y), 50u)`; each live ripple sears a one-shot brand:
   `heatLevel += 0.6 * smoothstep(0.08, 0.08*0.3, aspectCorrectedDist) * exp(-rippleAge * 1.5)`,
   feeding the SAME char/ember pipeline.
3. **Per-sector spark bins** — beam zone split into 8 angular sectors
   (`atan2` around beam center); each sector's sparkChance threshold rides
   `plasmaBuffer[(sector % 8u) + 1u].x` instead of global treble.

Also: stale comments fixed (config.y = RippleCount, zoom_config.w = MouseDown);
`bass_env` is now actually wired — bass envelope scales beam heat injection
("bass deepens the char"). All 4 sliders wired via `u.zoom_params.x/y/z/w`
with existing ids/defaults/roles kept EXACTLY (Beam Size → beam radius,
Burn Intensity → heat injection, Heal Rate → healFactor, Heat Glow → heatMix).

## Line count
116 → 186 (+70, within target 166–206)

## Contract items preserved VERBATIM
- 13-binding canonical layout; `@workgroup_size(16, 16, 1)`; no binding 13.
- `hash12` and `bass_env` helpers byte-identical.
- Heat→char→ember accumulation: `cooledHeat = heatLevel * 0.9`;
  `charLevel += cooledHeat * 0.1`; `clamp(0,1)`; `charLevel *= healFactor`;
  `emberLevel = mix(emberLevel, cooledHeat, 0.1)`; `emberLevel *= 0.95`.
- `fireColor` / `emberColor` / `sparkColor` ramps unchanged.
- `burnAlpha` formula byte-identical.
- State packing `vec4(charLevel, cooledHeat, emberLevel, burnAlpha)` written
  raw to dataTextureA every frame — no tonemap, no extra clamps.
- `textureSampleLevel(..., 0.0)` for sampler reads; writes to writeTexture,
  writeDepthTexture, dataTextureA every frame.
- extraBuffer restricted to [133..255] (used [133..137] only).

## JSON
`shader_definitions/interactive-mouse/laser-burn.json` replaced with the
brief's JSON verbatim (additive `updatedParams` mirror indices 0–3,
`updated: true`, params/features/tags/description unchanged). Validated
with python json.load.

## Naga
`naga public/shaders/laser-burn.wgsl` → **Validation successful** (exit 0,
no errors/warnings).
