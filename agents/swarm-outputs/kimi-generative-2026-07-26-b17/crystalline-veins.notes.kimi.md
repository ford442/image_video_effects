# crystalline-veins — Batch 17 Upgrade Notes (Kimi)

## Line delta
- Before: 203 lines
- After: 273 lines (+70, within target 253–293)

## Changes per technique

### 1. HDR blowout taming (priority 1)
- Added `huePreserveClamp(col, maxV)` — scales the full RGB triplet by `maxV/peak` only when the brightest channel exceeds 1.2, preserving hue instead of per-channel clipping.
- Added `acesTonemap` (Narkowicz ACES fit), applied AFTER the accumulation + temporal-feedback block, immediately before the texture stores. Never inside the accumulation loop; the `veinNoise` ridge formula (`1.0 - abs(n-0.5)*2.0`, `pow(combined, 2.5)`) is preserved verbatim.
- Result: treble sparkle (x2.5) stacked on pulse (x1.4) rolls off smoothly instead of clipping to white; feedback loop now ingests sanitized color.

### 2. Worley F2-F1 crack complement
- New `worleyCrack(p, time)` — 3x3-cell Worley with `hash22` feature points and a slow sinusoidal drift (`wob`) so cracks creep like cooling stone.
- Per-bin FFT modulation: cell hash selects `plasmaBuffer[1..8].x` (`binIndex = 1u + u32(cellHash.y * 7.999) % 8u`); the bin value drives both crack width (`0.04 + binFFT*0.10`) and crack intensity (`0.4 + binFFT*0.8`), so cracks shimmer across the spectrum.
- Cracks render as ore seams (`crackOreColor`) in a palette hue offset +0.13 from the main vein color, masked out where main veins already exist and gated by `growthMask`.

### 3. IQ mineral palette
- Replaced hardcoded gold/copper/silver triple-lerp with `mineralPalette(t) = a + b*cos(2π(c·t+d))`.
- Constants (a=0.62/0.48/0.32, b=0.42/0.36/0.30, d=0/0.10/0.22) tuned so `t` near 0 lands on the legacy warm gold look; sweeping `t` rotates through copper, silver, and rarer bands.
- Palette parameter: `mineralT = fract(cellHash.x * 0.65 + mineralShift)` — cell variation retained, slider sweeps the whole field. Chromatic-dispersion angular offsets now keyed to `mineralT` (replaces old `mineralType`).

## Slider wiring (contract preserved: same ids/defaults/ranges/order)
| Slider | mapping | Drives |
|---|---|---|
| Vein Density (0.3) | zoom_params.x | `veinDensity = mix(1.5, 5.0, x)` — FBM vein frequency AND Worley crack scale (`veinDensity * 2.5`) AND sparkle cell size |
| Glow Intensity (0.5) | zoom_params.y | `glowIntensity` — vein halo brightness and feedback glow injection |
| Growth Speed (0.4) | zoom_params.z | `growthSpeed` — growth-phase rate `fract(time*0.03*(0.5+z*1.5))`, which gates vein/crack emergence threshold |
| Mineral Shift (0.5) | zoom_params.w | `mineralShift` — IQ palette phase sweep over the full mineral spectrum |

## Binding compliance
- Canonical 13-binding layout untouched (0–12), no renumbering, no binding 13 added.
- `@workgroup_size(16, 16, 1)` preserved.
- Writes `writeTexture`, `dataTextureA`, `writeDepthTexture` every frame (crack term added to depth).
- Sampler read via `textureSampleLevel(dataTextureC, u_sampler, uv, 0.0)`; no extraBuffer writes at all (audit clean); plasmaBuffer read-only ([0] aggregates + [1..8] per-bin).
- No ripple loop used (no guard needed); no reserved-keyword identifiers.

## Gate / audit status
- `wgsl_precommit_gate.py --files public/shaders/crystalline-veins.wgsl` → PASS, 0 warnings (naga binary unavailable in this VM — bindgroup + workgroup checks still ran and passed).
- `audit_extrabuffer.py --files public/shaders/crystalline-veins.wgsl` → AUDIT PASS (0 violations).
- `audit_dead_sliders.py --files crystalline-veins` → AUDIT PASS (0 dead sliders).

## QA flags
- JSON definition written verbatim from the brief (features/tags/description unchanged per contract; WGSL header comment adds new feature keywords only in the comment, not in JSON).
- Not visually verifiable in headless VM (no GPU adapter); validated via static gates only.
- `dataTextureB`/`readTexture`/`readDepthTexture` remain declared-but-unused, matching the canonical layout and prior shader behavior.
