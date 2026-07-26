# cosmic-jellyfish — Batch 16 upgrade notes (Kimi)

## Line delta
- Before: 195 lines → After: 267 lines (+72, within +50..+90 target, inside 245–285 window)

## Key changes per technique

### 1. DISPLAY THE DEAD FEEDBACK (priority 1)
- The old shader computed `temporal = mix(prev*0.96, col, 0.25)` into `dataTextureA` but displayed raw `col` — dead feedback.
- Now: `temporal` is computed, clamped pre-tint at 1.2 (`min(temporal, vec3(1.2))`), stored to `dataTextureA`, **and** blended into the displayed frame via `col = mix(col, temporal, 0.6)` before tonemapping. The jelly leaves visible bioluminescent motion trails.
- Decay kept at 0.96 (< 1.0, stable accumulation).

### 2. Honest depth + tonemap
- `writeDepthTexture` no longer stores flat 0.0. It now writes the real normalized raymarch hit distance: `clamp(t / 10.0, 0, 1)` on hit (10.0 = march far plane), 1.0 on miss — chained shaders now receive honest scene depth.
- Added Narkowicz ACES tonemap (`acesTonemap`) applied after the trail blend, plus a `huePreserveClamp(col, 1.0)` (scales by peak channel instead of per-channel clipping) so Glow Intensity up to 5.0 stays colorful instead of washing to white.

### 3. Audio + palette
- Bass (`plasmaBuffer[0].x`) drives bell pulse amplitude **inside `map()`**: `pulse = sin(time * pulse_speed) * (0.1 + bass * 0.12)`.
- Treble (`plasmaBuffer[0].z`) drives tentacle wave frequency inside `map()`: `wave_freq = 2.0 + treble * 4.0` replaces the hard-coded `time * 2.0` in the wave terms.
- Rodrigues RGB hue rotation replaced with an IQ cosine palette (`cosinePalette`), tuned so `Hue Shift = 0.0` reproduces the original deep-blue bioluminescent glow; cheaper and smoother.

## Slider wiring (4 sliders, existing JSON params, unchanged ids/defaults/ranges)
- `u.zoom_params.x` — Pulse Speed (0–2, default 0.5): bell pulse speed, read INSIDE `map()` (`pulse_speed = x * 2.0`).
- `u.zoom_params.y` — Tentacle Activity (0–2, default 0.5): tentacle wave amplitude, read INSIDE `map()`.
- `u.zoom_params.z` — Hue Shift (0–1, default 0): cosine palette phase for the glow color.
- `u.zoom_params.w` — Glow Intensity (0–5, default 1): multiplies accumulated glow (tamed by ACES + hue-preserving clamp).
- Each slider drives a real constant of this shader's algorithm; no generic boilerplate rewiring needed beyond the palette swap.

## Binding contract compliance
- Canonical 13-binding compute layout preserved exactly (bindings 0–12, no additions/renumbering; binding 13 not declared — shader never used historyTexture).
- `@workgroup_size(16, 16, 1)` kept.
- Writes to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- `textureSampleLevel(..., 0.0)` for sampler reads (dataTextureC prev frame); storage reads via `plasmaBuffer[0]` indexing.
- No WGSL reserved keywords as identifiers (renamed `target_pos` → `look_at` for safety).
- extraBuffer: unused (only declared per contract) — no persistent state written.
- Uniform truth respected: `u.config.x` = time, `u.config.zw` = resolution, `u.zoom_config.yz` = mouse. No ripple loop (rippleCount guard not needed).
- CAUTION honored: `map()` SDF structure (bell hollow + 8-tentacle capsule loop, smin k=0.2) preserved verbatim; `u.zoom_params` reads kept inside `map()`; JSON ranges/defaults kept exactly (Pulse Speed 0–2, Glow 0–5).

## Gate
- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/cosmic-jellyfish.wgsl`
- Result: **GREEN** — 1 passed, 0 failed, 0 warnings, bindgroup compatible.
- Note: naga binary not installed in this environment, so naga validation step was skipped by the gate itself (environmental, same for all local runs); bindgroup + workgroup checks ran clean.

## QA flags
- ⚠️ No GPU adapter in this VM — visual verification (trail aesthetics, palette hue at non-zero Hue Shift, audio reactivity) not possible here; verify visually on a GPU machine.
- ⚠️ Naga skipped locally — recommend running the gate on a machine with naga for full validation (WGSL uses only standard constructs; store coords normalized to `vec2<i32>` for strict type safety).
- First frame after load: `dataTextureC` may be uninitialized → trails may take a few frames to settle (inherent to the existing feedback design; decay 0.96 converges quickly).
- Depth output convention: 1.0 = miss/far, smaller = closer hit. Chained shaders expecting 0 = far would need inversion, but this matches "normalized hit distance" per the brief.
