# supernova-core — Batch 15 Upgrade Notes (Kimi, Optimizer role)

## Line delta
- Before: 187 lines → After: 275 lines (+88, within the +50..+90 / 237–277 target band)

## Key changes per technique

### 1. Spectrum-driven rays
- Ray loop now reads `plasmaBuffer[u32(ri % 8) + 1u].x` per ray (bin = (i % 8) + 1).
- Intensity = `shimmer * spectral` where `shimmer = 0.3 + hash21(rf, time) * 0.7` is the original
  per-ray hash shimmer kept as the floor, and `spectral = 0.45 + binVal * 1.4` lifts each ray
  by its FFT bin so the light echo decomposes into the audio spectrum.
- Chromatic prism split (rayR/rayB) and hue-cycling unchanged.

### 2. Click Sedov rings
- New loop guarded by `let rippleCount = min(u32(u.config.y), 50u);` over `u.ripples[ci]`.
- Each click (xy = position uv, z = click time) spawns a secondary ring with Sedov-Taylor
  self-similar growth `ringRadius = pow(age * 0.30 * (1.0 + shockwaves * 0.8), 0.4) * 0.6`,
  age-decayed intensity `exp(-age * 1.1)`, and a cooling blackbody ramp 12000K → 2800K.
- Active window: `0 < age < 6s`. Contributes to hdr, shockTemp, and ejectaDensity so the
  rings participate in fog, depth output, and the alpha compositor.

### 3. Spring-damper companion star
- `extraBuffer[133..134]` holds the eased companion-star position (world space).
- Position-only critically damped step: `k = 1 - exp(-dt * 9.0)`, `companion = mix(companion, target, k)`.
- Only invocation (0,0) integrates/writes; all pixels read. Cold-start snap when `time < 0.1`
  avoids a startup swoop from zero-initialized buffer.
- `mouseWorld` now uses the eased value, so asymmetry + rim light relax smoothly after fast moves.

## Slider wiring (saved-preset contract preserved — same ids/defaults/mappings)
- `zoom_params.x` Expansion → blast radius scale + ray reach (`smoothstep(0.35 * (1.0 + expansion) ...)`).
- `zoom_params.y` Ray Count → ray count 6..24 (`6 + i32(y * 18.0)`), also ray hue spacing.
- `zoom_params.z` Shockwave Speed → Sedov rate of main blast AND click rings (`(1.0 + shockwaves)` / `(1.0 + shockwaves * 0.8)`).
- `zoom_params.w` Chromatic Shift → prism split width `cs = chromatic * 0.025 * dist * (1.0 + treble)`.
- JSON `updatedParams` index 0–3 + `updated: true` written verbatim from the brief block (validated as JSON).

## Binding contract compliance
- Canonical 13-binding layout untouched (0 sampler … 12 plasmaBuffer read); no binding 13 added.
- `@workgroup_size(16, 16, 1)` kept. Writes `writeTexture`, `dataTextureA`, `writeDepthTexture` every frame.
- `textureLoad` for storage reads; no sampler reads needed (none added). No reserved-keyword identifiers.
- extraBuffer usage confined to [133..134] (within [133..255] persistent region); [0..4]/[5..132] untouched.
- Advanced alpha compositor block preserved VERBATIM (luminanceKey → depthAlpha → beerLambertAlpha →
  edgeAlpha, same mix weights, premultiplied `finalColor = color * alpha`).
- OkLab mix, blackbodyRGB, and `hue_preserve_clamp(hdr, 8.0)` → ACES → gamma → IGN dither stack byte-identical.

## Gate
- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/supernova-core.wgsl`
- Result: ✅ GREEN — Passed: 1, Failed: 0, Warnings: 0 (naga binary unavailable in env, bindgroup + workgroup checks ran clean).

## QA flags
- Naga validation skipped (binary not installed in this environment) — bindgroup/workgroup gates passed; recommend a naga run in CI if available.
- Spring state is per-frame approximate (fixed dt = 1/60) — acceptable for critically damped ease; no visual QA possible headless (no GPU).
- Click rings assume engine convention ripple.xy = uv position, ripple.z = click time (matches other shaders in repo).
