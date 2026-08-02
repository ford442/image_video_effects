# Swarm Completion Note: quantum-flux (kimi, b27)

**Date:** 2026-08-02
**Shader:** `public/shaders/quantum-flux.wgsl` (category: interactive-mouse)
**JSON:** `shader_definitions/interactive-mouse/quantum-flux.json`

## Line count

- Before: **117** lines
- After: **182** lines (+65, within the 167–207 target band)

## Changes implemented

1. **Sprung flux center (priority 1):** Critically-damped spring (zeta = 1,
   omega = 9.0) computed coherently by every invocation and persisted by invocation (0,0) into `extraBuffer[133..138]`
   — [133..134] sprung center, [135..136] velocity, [137] init flag,
   [138] last integration time (dt clamped to [0.0005, 0.05]). Raw mouse
   (`u.zoom_config.yz`) remains only the spring TARGET; all threads ride the
   same current-frame sprung center. Existing aspect correction
   preserved: `uvCorrected`/`mouseCorrected`, where `mouseCorrected` is now
   built from the sprung center.
2. **Click decoherence bursts:** Ripple loop guarded with
   `min(u32(u.config.y), 50u)`. Each live ripple (age in (0, 1.2s)) adds a
   decaying `+0.6 * jitterBase` bump inside an aspect-corrected ~0.25-radius
   smoothstep, attenuated by `exp(-rippleAge * 2.0)`, accumulated into
   `clickBurst` and added to the local jitter magnitude.
3. **Per-sector FFT voices:** The influence zone is divided into 8 angular
   sectors around the sprung center via `atan2`; each sector's jitter
   magnitude is modulated by `plasmaBuffer[(sector % 8u) + 1u].x * 0.3`,
   so different wedges vibrate to different frequency bins.
4. **Sliders (4, roles kept EXACTLY):** x = Flux Jitter → jitter magnitude
   (treble-modulated), y = Wave Freq → radial wave frequency
   (mids-modulated), z = Color Drift → hue drift speed (mids-modulated),
   w = Flux Radius → influence radius (bass-modulated). Mapping order and
   audio modulation unchanged from the original shader.

## Contracts preserved (CAUTION block — all VERBATIM)

- `rgb2hsv`, `hsv2rgb`, `rand` helpers: byte-for-byte unchanged.
- jitter/wave/split construction lines: unchanged (the sector/burst
  modulation feeds into `jitterAmount` *before* those lines).
- 3 chromatic tap offsets (`uvR`/`uvG`/`uvB`): unchanged.
- Hue-drift `driftMask` gate: unchanged.
- Interference scanlines block: unchanged.
- `splitMag` alpha formula: unchanged.
- `dataTextureA` stays DISPLAY color (same `vec4(color, alpha)` as writeTexture).
- extraBuffer usage in **[133..138] only** (inside [133..255]); no writes to
  [0..4] (reserved) or [5..132] (engine FFT).
- Canonical 13-binding layout unchanged; no binding 13 added.
- `@workgroup_size(16, 16, 1)` unchanged.
- `writeTexture` + `writeDepthTexture` + `dataTextureA` written every frame.
- All sampler reads via `textureSampleLevel(..., 0.0)`; no reserved-keyword
  identifiers.
- Engine truth honored: config = [time, rippleCount, resW, resH],
  zoom_config = [time, mouseX, mouseY, mouseDown].

## JSON update

Applied the brief's JSON verbatim: added `updatedParams` (indices 0–3 with
step 0.01, additive mirror) and `updated: true`. Param ids, names,
defaults, min/max, features, tags untouched. Validated with `json.load`.

## Naga status

```
$ /root/.cargo/bin/naga public/shaders/quantum-flux.wgsl
Validation successful
```

Clean — no errors, no warnings.
