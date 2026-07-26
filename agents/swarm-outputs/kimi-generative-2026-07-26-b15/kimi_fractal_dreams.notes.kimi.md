# Batch 15 Upgrade Notes: kimi_fractal_dreams

**Date:** 2026-07-26
**Shader:** `public/shaders/kimi_fractal_dreams.wgsl`
**JSON:** `shader_definitions/generative/kimi_fractal_dreams.json` (verbatim from brief)

## Line delta

- Before: **186** lines
- After: **276** lines
- Delta: **+90** (within brief target 236–276, expansion +50..+90)

## Key changes per technique

1. **NaN fix (priority 1):** `cdiv()` denominator is now epsilon-clamped:
   `let denom = max(b.x*b.x + b.y*b.y, 1e-4);`. Formula behavior unchanged for
   all normal inputs (denominator ≥ 1e-4 in practice); only kills the inf/NaN
   pixels when `z ≈ (-0.01, -0.01)` under `complexity > 1.5`.
2. **Spring-damper Julia morph:** critically-damped spring (ω = 7.0, dt = 1/60)
   integrates the Julia constant toward `mix((-0.8, 0.156), mousePos, 0.5)` in
   `extraBuffer[133..136]` = (c.x, c.y, v.x, v.y). Only invocation (0,0)
   writes; all others read (benign race, per project convention). Zero-init
   first frame snaps to target to avoid a long glide from origin.
3. **Click ripples:** `rippleCount = min(u32(u.config.y), 50u)` (guarded).
   Each ripple adds a decaying zoom-pulse impulse
   `exp(-age*2.2) * (0.35 + 0.65*local) * strength * 0.25` into the zoom term;
   age measured against raw `u.config.x` timebase, active window 0–2.5 s.
4. **Orbit-trap palette:** added `iqCosinePalette(t)` (IQ cosine palette) keyed
   on `orbitTrap*2.0 + hue*0.35 + time*0.05`, mixed 45% with the original HSL
   color so the classic look still reads through.
5. **Treble filaments:** per-layer per-bin audio via `plasmaBuffer[1 + layer].x`;
   filament term `exp(-orbitTrap * filamentSharp)` multiplied by
   `(0.25 + treble*1.2 + binGlow*2.0)` lights fractal edges on high-hat energy.
6. **Honest sliders:** JSON names/ids/defaults/mapping untouched (preset
   contract); each slider gained an additional label-matching effect that is
   identity at the default 0.5:
   - *Intensity* → also `glowGain = 0.5 + x` (glow/filament brightness)
   - *Speed* → also layer-orbit rate `0.5 + y` and rotation-angle wobble
     `(y - 0.5) * 0.35 * sin(time*0.6)` (zero at default)
   - *Scale* → also orbit-trap radius `0.5 * (0.6 + z*0.8)` (0.5 at default)
   - *Detail* → also filament sharpness `5.0 + w*9.0`
7. **Extra:** inline HSL block factored into `hslToRgb()`; previously-unused
   `hash()` now drives a ±0.002 dither to break palette banding.

## Slider wiring (updatedParams index → uniform)

| Index | Name      | Mapping         | WGSL uses                                        |
|-------|-----------|-----------------|--------------------------------------------------|
| 0     | Intensity | zoom_params.x   | zoom base + glowGain                             |
| 1     | Speed     | zoom_params.y   | iteration count + orbit rate + rotation wobble   |
| 2     | Scale     | zoom_params.z   | color cycles + orbit-trap radius                 |
| 3     | Detail    | zoom_params.w   | complexity (cdiv term) + filament sharpness      |

## Binding contract compliance

- Canonical 13-binding layout preserved exactly (0–12, no renumbering, no
  binding 13 added).
- `@workgroup_size(16, 16, 1)` kept.
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame.
- No reserved keywords as identifiers; no `textureSampleLevel` added (none needed).
- `extraBuffer` persistent state confined to **[133..136]** (inside [133..255]);
  reserved [0..4] and FFT bins [5..132] untouched.
- CAUTION honored: Burning-Ship `abs()` + `cmul` core verbatim;
  `smoothIter = f32(i) - log2(log2(r)) + 4.0` verbatim; 3-layer structure with
  1.047 rad base rotation and 0.8 scale preserved (slider wobble is additive
  and zero at default).

## Gate / QA

- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/kimi_fractal_dreams.wgsl`
  → **GREEN**: Passed 1, Failed 0, Workgroup errors 0, **Warnings 0**.
- QA flags:
  - naga binary unavailable in this VM (skipped by gate); bindgroup +
    workgroup checks ran clean. Syntax follows existing validated patterns.
  - extraBuffer (0,0)-thread write vs. other-thread read is a benign race
    (same convention as other upgraded shaders, e.g. holographic-crystal).
  - First frame after buffer zero-init may show one frame of c=(0,0) for
    non-zero invocations before the snap write lands — self-corrects frame 2.
  - Default-look preservation is by construction (all new slider terms are
    identity at 0.5) but could not be visually verified (no GPU in VM).
