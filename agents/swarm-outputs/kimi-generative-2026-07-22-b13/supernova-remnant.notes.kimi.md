# Supernova Remnant — Visualist Upgrade Notes (2026-07-22, batch b13)

## Line delta
- `public/shaders/supernova-remnant.wgsl`: 174 → 232 lines (**+58**, within the +50–90 target; brief target band 224–264 ✓)

## Key changes per technique

### Blackbody age ramp
- Added `blackbodyRamp(t)` helper: white-hot (1.0, 0.96, 0.88) → orange (1.0, 0.52, 0.12) → deep-red (0.42, 0.05, 0.02), blended with two smoothsteps.
- Shell/filament/core colors are now modulated by this ramp instead of the fixed RGB shell weights (`col.r/g/b = shell*X + ...`). Core uses `blackbodyRamp(age * 0.4)` so the dense core cools more slowly and stays hotter than the shell.

### Inertial age accumulator (bass momentum kicks)
- `age` is no longer `fract(time * rate + bass * 0.05)` (direct rescale). It is now an accumulator stored in `dataTextureA` alpha and read back from last frame's copy via `textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0).a`:
  - `age = prevAge + expansionRate * 0.0016` (slow steady aging)
  - `age += bass² * 0.012 * expansionRate` (bass nudges the accumulator → momentum feel, not zoom)
  - `fract(age)` keeps the cyclic rebirth of the remnant.
- `shockRadius = age * 0.8` unchanged in form.

### Click detonation via ripples[]
- Uses `u.ripples[i]` with `rippleCount = min(u32(u.config.y), 50u)` (project convention from gen-spectral-ferrofluid / sim-volumetric-fake-em): `xy` = click pos (0–1 uv), `z` = click time.
- Each live ripple (elapsed in (0, 4s)) emits an expanding ring (`frontR = elapsed * 0.55`, Gaussian band, `exp(-elapsed * 1.2)` fade) plus a hot flash at the click origin.
- `detonate` perturbs the main shell: `shellRadius = shockRadius + detonate * 0.05`, and `shellRadius` is used for the shock front, RT-finger mask, filament mask, and all three chromatic shells — so the secondary front visibly deforms the primary shock where it passes.
- Color: blue-white ring `(0.75, 0.85, 1.0) * detonate * 1.2` + warm flash `(1.0, 0.9, 0.7) * detonateGlow * 2.0`. `detonate` added to the alpha `energy` sum.

### Slider params (unchanged contract, still shader-specific)
- Kept existing mappings exactly: `x`→Expansion Rate (0.1–1.0, drives age accumulator rate), `y`→Filament Turbulence (0–2.0, fbm polar turbulence amplitude), `z`→Shock Density (0.5–3.0, filament brightness), `w`→Decay Sparkles (0–1.5, treble sparkle gain). All four drive real constants of this shader's algorithm; no renames/re-defaults.
- JSON: added `updatedParams` (4 entries, index 0–3, same names/defaults/min/max/step as `params`) and `"updated": true`. Nothing else touched.

## Preserved per CAUTION
- `normalize(uv01 - vec2(0.5) + vec2(0.001))` epsilon guard intact.
- Chromatic-dispersed feedback untouched: decay 0.92, mix 0.15 + bass * 0.03, same per-channel `cStr` scaling.
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, writes to writeTexture/writeDepthTexture/dataTextureA every frame, `textureSampleLevel(..., 0.0)` for all sampler reads, no new/renumbered bindings, no reserved identifiers (avoided `pow` with possibly-negative base by squaring manually).

## QA flags
- `dataTextureA` alpha now carries the **age accumulator** instead of the energy alpha (RGB still carries color for feedback). writeTexture alpha is unchanged (energy-based), so compositing is unaffected; only consumers of dataTextureA alpha would see the semantic change — feedback path uses RGB only, verified safe.
- Age accumulation is per-frame (framerate-dependent increment), consistent with other temporal shaders in this repo; no delta-time uniform is available in the canonical layout.
- **No-GPU caveat:** the Cloud VM has no WebGPU adapter, so visual QA (blackbody ramp feel, detonation ring look, bass-kick momentum) is deferred to real hardware. Validation here was: naga via precommit gate (pass, 0 warnings), bindgroup compatibility (pass), and JSON parse (pass).
