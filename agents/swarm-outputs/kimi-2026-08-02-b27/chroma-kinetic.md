# Swarm Completion: chroma-kinetic

**Agent:** kimi (Optimizer role) | **Batch:** kimi-2026-08-02-b27 | **Date:** 2026-08-02

## Changes

- **Sprung effect center (priority 1):** critically-damped spring integrated by thread (0,0) into
  `extraBuffer[133..138]` ([133..134] position, [135..136] velocity, [137] last time, [138] init flag);
  raw mouse stays the spring target, `omega = 10.0`, `dt` clamped to [0.001, 0.05]. The distortion field
  now glides behind the cursor instead of snapping.
- **Flick-speed strength bonus:** `strength *= 1.0 + min(springSpeed * 3.0, 0.4)` exactly per brief —
  fast flicks smear harder (the shader is named kinetic).
- **Click kinetic bursts:** ripple loop guarded with `min(u32(u.config.y), 50u)`; each live ripple
  (`0 <= age <= 1.2s`) adds a radial-from-click velocity boost `exp(-rippleAge * 2.0)` inside an
  aspect-corrected ~0.25 radius, scaled by `strength * 2.0` and aspect-un-corrected like `uvOffsetDir`.
- **Per-sector FFT voices:** field divided into 8 angular sectors around the sprung center via
  `atan2(diffAspect.y, diffAspect.x)`; each sector's smear mix adds
  `plasmaBuffer[(sector % 8u) + 1u].x * 0.25` to the bass/mids/treble blends so trails shimmer directionally.
- **Stale comments fixed:** config.y = RippleCount, zoom_config.w = MouseDown.
- **JSON:** applied the brief's JSON verbatim (additive `updatedParams` mirror, indices 0–3, `updated: true`);
  param ids/names/defaults/ranges untouched (`luma_influence` keeps the non-standard -2..2 range, rotation default 0).

## Contracts preserved (CAUTION block)

- `bass_env` helper verbatim.
- Rotation matrix + `uvOffsetDir` construction verbatim.
- `falloff` / `modFactor` math verbatim.
- Lead/lag chromatic taps (`uvR`/`uvG`/`uvB`) verbatim.
- 3-sample smear loop with `(1.0 - t)` weights verbatim.
- Per-channel smear mix structure (`mix(r, smearR, bass*0.3 ...)` etc.) preserved, sector voice added additively.
- `depthMod = mix(0.5, 1.5, depth)` verbatim; alpha formula verbatim.
- `dataTextureA` stays DISPLAY color (same `finalRGBA` as writeTexture).
- extraBuffer usage confined to [133..138] (inside [133..255]); [0..4] reserved and [5..132] engine FFT untouched.
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, writes writeTexture + writeDepthTexture + dataTextureA every frame.
- Slider mapping: x=strength, y=radius, z=luma_influence, w=rotation (existing mapping already shader-specific, kept).

## Line count

117 → **184** (+67, within the 167–207 target)

## Validation

`naga public/shaders/chroma-kinetic.wgsl` → **Validation successful** (no errors, no warnings).
JSON validated with `python3 -m json.tool` → OK.
